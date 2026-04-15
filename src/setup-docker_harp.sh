#!/bin/bash

HARP_PORT_BASE="${HARP_PORT_BASE:-8780}"
HARP_BASE_DIR="$NCHPB_DOCKER_RUNTIME_DIR/harp"
HARP_TEMPLATE_COMPOSE_PATH="$TMP_DIR_PATH/harp/docker-compose.yml"

# Explicitly document naming behavior for both compose-managed and HaRP-spawned containers.
HARP_CONTAINER_NAMING_POLICY="Compose resources are prefixed via per-instance project name. HaRP-spawned containers use slug prefix when supported by upstream runtime, else instance labels/network scoping applies."

declare -A HARP_INSTANCE_IDS
declare -A HARP_INSTANCE_PORTS
declare -A HARP_INSTANCE_FRP_PORTS
declare -A HARP_INSTANCE_SHARED_KEYS
declare -A HARP_INSTANCE_PROJECT_NAMES
declare -A HARP_INSTANCE_DEPLOY_STATUSES
declare -a HARP_SETUP_ERRORS
HARP_ABORT_REQUESTED=false

awk_escape_sed_replacement='s/[&\\]/\\&/g'

function install_harp() {
	announce_installation "Deploying Docker HaRP"
	log "Installing Docker HaRP instances..."
	log "Using '$HARP_PORT_BASE' for HARP_PORT_BASE."

	HARP_SETUP_ERRORS=()
	HARP_ABORT_REQUESTED=false
	DOCKER_PHASE_COMPOSE_DEPLOY_STATUS="running"
	DOCKER_PHASE_VERIFY_STATUS="running"

	if ! [[ "$HARP_PORT_BASE" =~ ^[0-9]+$ ]]; then
		HARP_SETUP_ERRORS+=("compose deploy: HARP_PORT_BASE must be numeric, got '$HARP_PORT_BASE'")
		DOCKER_PHASE_COMPOSE_DEPLOY_STATUS="failed"
		DOCKER_PHASE_VERIFY_STATUS="failed"
		DOCKER_SETUP_ERRORS+=("compose deploy: invalid HARP_PORT_BASE '$HARP_PORT_BASE'")
		log_err "Invalid HARP_PORT_BASE '$HARP_PORT_BASE'."
		return 0
	fi

	if [ "$HARP_PORT_BASE" -lt 1024 ] || [ "$HARP_PORT_BASE" -gt 65533 ]; then
		HARP_SETUP_ERRORS+=("compose deploy: HARP_PORT_BASE must be between 1024 and 65533, got '$HARP_PORT_BASE'")
		DOCKER_PHASE_COMPOSE_DEPLOY_STATUS="failed"
		DOCKER_PHASE_VERIFY_STATUS="failed"
		DOCKER_SETUP_ERRORS+=("compose deploy: invalid HARP_PORT_BASE range '$HARP_PORT_BASE'")
		log_err "Invalid HARP_PORT_BASE '$HARP_PORT_BASE'. Allowed range is 1024..65533."
		return 0
	fi

	if [ "${#NEXTCLOUD_SERVER_FQDNS[@]}" -eq 0 ]; then
		HARP_SETUP_ERRORS+=("compose deploy: NEXTCLOUD_SERVER_FQDNS is empty")
		DOCKER_PHASE_COMPOSE_DEPLOY_STATUS="failed"
		DOCKER_PHASE_VERIFY_STATUS="failed"
		DOCKER_SETUP_ERRORS+=("compose deploy: missing Nextcloud instance domains")
		log_err "No Nextcloud domains available for HaRP deployment."
		return 0
	fi

	if [ ! -f "$HARP_TEMPLATE_COMPOSE_PATH" ]; then
		HARP_SETUP_ERRORS+=("compose deploy: missing template '$HARP_TEMPLATE_COMPOSE_PATH'")
		DOCKER_PHASE_COMPOSE_DEPLOY_STATUS="failed"
		DOCKER_PHASE_VERIFY_STATUS="failed"
		DOCKER_SETUP_ERRORS+=("compose deploy: missing HaRP compose template in tmp dir")
		log_err "Missing HaRP template '$HARP_TEMPLATE_COMPOSE_PATH'."
		return 0
	fi

	for idx in "${!NEXTCLOUD_SERVER_FQDNS[@]}"; do
		local nc_server
		local instance_index
		local nc_server_slug
		local instance_id
		local instance_dir
		local instance_port
		local instance_frp_port
		local nc_instance_url
		local hp_shared_key
		local project_name

		nc_server="${NEXTCLOUD_SERVER_FQDNS[$idx]}"
		instance_index=$((idx + 1))
		nc_server_slug="$(echo "$nc_server" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
		if [ -z "$nc_server_slug" ]; then
			nc_server_slug="nc-instance"
		fi

		instance_id="${nc_server_slug}-${instance_index}"
		instance_dir="$HARP_BASE_DIR/$instance_id"
		instance_port=$((HARP_PORT_BASE + idx))
		instance_frp_port=$((instance_port + 2))
		nc_instance_url="https://$nc_server"
		hp_shared_key="$(openssl rand -hex 32)"
		project_name="nchpb-harp-$instance_id"

		if [ "${#hp_shared_key}" -lt 12 ]; then
			HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]="failed"
			HARP_SETUP_ERRORS+=("compose deploy: generated HP_SHARED_KEY too short for instance '$instance_id'")
			DOCKER_SETUP_ERRORS+=("compose deploy: shared key length guard failed for '$instance_id'")
			continue
		fi

		if ! is_dry_run && ! harp_preflight_port_free "$instance_port" "$instance_id" "exapps"; then
			HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]="failed"
			HARP_SETUP_ERRORS+=("compose deploy: local exapps port '$instance_port' already in use for '$instance_id'")
			DOCKER_SETUP_ERRORS+=("compose deploy: exapps port conflict '$instance_port' for '$instance_id'")
			continue
		fi

		if ! is_dry_run && ! harp_preflight_port_free "$instance_frp_port" "$instance_id" "frp"; then
			HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]="failed"
			HARP_SETUP_ERRORS+=("compose deploy: local frp port '$instance_frp_port' already in use for '$instance_id'")
			DOCKER_SETUP_ERRORS+=("compose deploy: frp port conflict '$instance_frp_port' for '$instance_id'")
			continue
		fi

		HARP_INSTANCE_IDS["$nc_server"]="$instance_id"
		HARP_INSTANCE_PORTS["$nc_server"]="$instance_port"
		HARP_INSTANCE_FRP_PORTS["$nc_server"]="$instance_frp_port"
		HARP_INSTANCE_SHARED_KEYS["$nc_server"]="$hp_shared_key"
		HARP_INSTANCE_PROJECT_NAMES["$nc_server"]="$project_name"

		if is_dry_run "Would've prepared and deployed HaRP instance '$instance_id' for '$nc_server' on local exapps/frp ports '$instance_port/$instance_frp_port'."; then
			HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]="dry-run (skipped)"
			continue
		fi

		if ! harp_prepare_instance "$instance_dir" "$nc_instance_url" "$hp_shared_key" "$instance_port" "$instance_frp_port" "$project_name" "$instance_id"; then
			HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]="failed"
			HARP_SETUP_ERRORS+=("compose deploy: failed preparing instance '$instance_id' for '$nc_server'")
			DOCKER_SETUP_ERRORS+=("compose deploy: failed preparing HaRP instance '$instance_id'")
			continue
		fi

		if ! harp_compose_up "$instance_dir" "$project_name"; then
			HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]="failed"
			HARP_SETUP_ERRORS+=("compose deploy: failed docker compose up for instance '$instance_id' ('$nc_server')")
			DOCKER_SETUP_ERRORS+=("compose deploy: failed for HaRP instance '$instance_id'")
			continue
		fi

		if ! harp_verify_instance "$instance_dir" "$project_name" "$instance_port" "$hp_shared_key" "$instance_id"; then
			HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]="failed"
			HARP_SETUP_ERRORS+=("verify: failed checks for instance '$instance_id' ('$nc_server')")
			DOCKER_SETUP_ERRORS+=("verify: failed for HaRP instance '$instance_id'")
			if [ "$HARP_ABORT_REQUESTED" = true ]; then
				log_err "Aborting installation after user request during HaRP verification."
				exit 1
			fi
			continue
		fi

		HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]="completed"
		log "Deployed HaRP instance '$instance_id' for '$nc_server' on local exapps/frp ports '$instance_port/$instance_frp_port'."
	done

	if [ "$DRY_RUN" = true ]; then
		DOCKER_PHASE_COMPOSE_DEPLOY_STATUS="dry-run (skipped)"
		DOCKER_PHASE_VERIFY_STATUS="dry-run (skipped)"
		log "HaRP deployment skipped due to dry-run mode."
		return 0
	fi

	if [ ${#HARP_SETUP_ERRORS[@]} -gt 0 ]; then
		DOCKER_PHASE_COMPOSE_DEPLOY_STATUS="failed"
		DOCKER_PHASE_VERIFY_STATUS="failed"
		log_err "HaRP deployment finished with failures."
	else
		DOCKER_PHASE_COMPOSE_DEPLOY_STATUS="completed"
		DOCKER_PHASE_VERIFY_STATUS="completed"
		log "HaRP deployment completed successfully."
	fi

	return 0
}

function harp_prepare_instance() {
	local instance_dir="$1"
	local nc_instance_url="$2"
	local hp_shared_key="$3"
	local instance_port="$4"
	local instance_frp_port="$5"
	local project_name="$6"
	local instance_id="$7"
	local compose_file_path="$instance_dir/docker-compose.yml"

	install -d -m 0770 -o "$NCHPB_DOCKER_USER" -g "$NCHPB_DOCKER_GROUP" "$HARP_BASE_DIR" 2>&1 | tee -a "$LOGFILE_PATH"
	install -d -m 0770 -o "$NCHPB_DOCKER_USER" -g "$NCHPB_DOCKER_GROUP" "$instance_dir" 2>&1 | tee -a "$LOGFILE_PATH"

	cp "$HARP_TEMPLATE_COMPOSE_PATH" "$compose_file_path" 2>&1 | tee -a "$LOGFILE_PATH"

	nc_instance_url_esc=$(printf '%s' "$nc_instance_url" | sed -e "$awk_escape_sed_replacement")
	instance_port_esc=$(printf '%s' "$instance_port" | sed -e "$awk_escape_sed_replacement")
	instance_frp_port_esc=$(printf '%s' "$instance_frp_port" | sed -e "$awk_escape_sed_replacement")
	project_name_esc=$(printf '%s' "$project_name" | sed -e "$awk_escape_sed_replacement")
	instance_id_esc=$(printf '%s' "$instance_id" | sed -e "$awk_escape_sed_replacement")

	sed -i "s|<NC_INSTANCE_URL>|$nc_instance_url_esc|g" "$compose_file_path"
	sed -i "s|<HARP_PORT>|$instance_port_esc|g" "$compose_file_path"
	sed -i "s|<HARP_FRP_PORT>|$instance_frp_port_esc|g" "$compose_file_path"
	sed -i "s|<HARP_COMPOSE_PROJECT>|$project_name_esc|g" "$compose_file_path"
	sed -i "s|<HARP_INSTANCE_ID>|$instance_id_esc|g" "$compose_file_path"
	replace_placeholder_in_files "<HP_SHARED_KEY>" "$hp_shared_key" "$compose_file_path"

	if grep -q "<NC_INSTANCE_URL>\|<HARP_PORT>\|<HARP_FRP_PORT>\|<HARP_COMPOSE_PROJECT>\|<HARP_INSTANCE_ID>\|<HP_SHARED_KEY>" "$compose_file_path"; then
		log_err "Placeholder substitution incomplete in '$compose_file_path'."
		return 1
	fi

	return 0
}

function harp_compose_up() {
	local instance_dir="$1"
	local project_name="$2"

	if command -v docker-compose >/dev/null 2>&1; then
		(
			cd "$instance_dir"
			docker-compose -p "$project_name" up -d
		) 2>&1 | tee -a "$LOGFILE_PATH"
		return ${PIPESTATUS[0]}
	fi

	(
		cd "$instance_dir"
		docker compose -p "$project_name" up -d
	) 2>&1 | tee -a "$LOGFILE_PATH"
	return ${PIPESTATUS[0]}
}

function harp_verify_instance() {
	local instance_dir="$1"
	local project_name="$2"
	local instance_port="$3"
	local hp_shared_key="$4"
	local instance_id="$5"
	local verify_timeout_secs=180
	local verify_interval_secs=5
	local max_attempts=$((verify_timeout_secs / verify_interval_secs))
	local attempt
	local path
	local endpoint
	local -a ping_paths

	ping_paths=(
		"/exapps/app_api/v1.44/_ping"
		"/exapps/app_api/v1.41/_ping"
		"/exapps/app_api/_ping"
	)

	if ! grep -q "$project_name" "$instance_dir/docker-compose.yml"; then
		log_err "Compose sanity check failed for instance '$instance_id': missing project name marker."
		return 1
	fi

	container_count=$(docker ps --filter "label=com.docker.compose.project=$project_name" --format '{{.Names}}' | wc -l)
	if [ "$container_count" -eq 0 ]; then
		log_err "No running compose-managed containers found for project '$project_name'."
		return 1
	fi

	for attempt in $(seq 1 "$max_attempts"); do
		for path in "${ping_paths[@]}"; do
			endpoint="http://127.0.0.1:$instance_port$path"
			if curl -fsS --max-time 10 \
				-H "harp-shared-key: $hp_shared_key" \
				-H "docker-engine-port: 24000" \
				"$endpoint" >/dev/null 2>&1; then
				log "HaRP AppAPI ping successful for instance '$instance_id' via '$path'."
				return 0
			fi
		done

		if [ "$attempt" -lt "$max_attempts" ]; then
			log "HaRP AppAPI ping not ready for '$instance_id' (attempt $attempt/$max_attempts). Retrying in ${verify_interval_secs}s..."
			sleep "$verify_interval_secs"
		fi
	done

	log_err "HaRP AppAPI ping failed for instance '$instance_id' after ${verify_timeout_secs}s of retries."

	if [ "$UNATTENDED_INSTALL" != true ] && command -v whiptail >/dev/null 2>&1; then
		if whiptail --title "HaRP Verification Failed" --defaultyes \
			--yesno "HaRP verification for instance '$instance_id' failed after ${verify_timeout_secs} seconds.\n\nDo you want to abort the installation now?" \
			12 78 3>&1 1>&2 2>&3; then
			HARP_ABORT_REQUESTED=true
		fi
	fi

	return 1
}

function harp_preflight_port_free() {
	local port="$1"
	local instance_id="$2"
	local role="$3"

	if command -v ss >/dev/null 2>&1; then
		if ss -ltn "sport = :$port" 2>/dev/null | tail -n +2 | grep -q .; then
			log_err "Port preflight failed for '$instance_id' ($role): local TCP port '$port' is already in use."
			return 1
		fi
	fi

	return 0
}

function docker_harp_write_secrets_to_file() {
	if is_dry_run; then
		return 0
	fi

	{
		echo -e "=== Docker HaRP Setup ==="
		echo -e "HaRP port base: $HARP_PORT_BASE"
		echo -e "HaRP naming policy: $HARP_CONTAINER_NAMING_POLICY"
		for nc_server in "${NEXTCLOUD_SERVER_FQDNS[@]}"; do
			instance_id="${HARP_INSTANCE_IDS["$nc_server"]}"
			instance_port="${HARP_INSTANCE_PORTS["$nc_server"]}"
			instance_frp_port="${HARP_INSTANCE_FRP_PORTS["$nc_server"]}"
			project_name="${HARP_INSTANCE_PROJECT_NAMES["$nc_server"]}"
			shared_key="${HARP_INSTANCE_SHARED_KEYS["$nc_server"]}"
			deploy_status="${HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]}"

			echo -e "Instance domain: $nc_server"
			echo -e "  Instance ID: $instance_id"
			echo -e "  Compose project: $project_name"
			echo -e "  Local exapps port: $instance_port"
			echo -e "  Local frp port: $instance_frp_port"
			echo -e "  Deploy status: $deploy_status"
			echo -e "  HP shared key: $shared_key"
		done
	} >> "$1"
}

function docker_harp_print_info() {
	log "=== Docker HaRP Setup ==="
	log "HaRP enabled: ${cyan}$SHOULD_INSTALL_HARP"
	log "HaRP port base: ${cyan}$HARP_PORT_BASE"
	log "HaRP naming policy: ${cyan}$HARP_CONTAINER_NAMING_POLICY"

	for nc_server in "${NEXTCLOUD_SERVER_FQDNS[@]}"; do
		instance_id="${HARP_INSTANCE_IDS["$nc_server"]}"
		instance_port="${HARP_INSTANCE_PORTS["$nc_server"]}"
		instance_frp_port="${HARP_INSTANCE_FRP_PORTS["$nc_server"]}"
		project_name="${HARP_INSTANCE_PROJECT_NAMES["$nc_server"]}"
		deploy_status="${HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]}"

		if [ -n "$instance_id" ]; then
			log "HaRP instance '$instance_id' for '$nc_server': project=${cyan}$project_name${normal}, exapps-port=${cyan}$instance_port${normal}, frp-port=${cyan}$instance_frp_port${normal}, status=${cyan}$deploy_status"
		fi
	done

	if [ ${#HARP_SETUP_ERRORS[@]} -gt 0 ]; then
		log_err "HaRP setup phase failures:"
		for err in "${HARP_SETUP_ERRORS[@]}"; do
			log_err "  - $err"
		done
	fi
}
