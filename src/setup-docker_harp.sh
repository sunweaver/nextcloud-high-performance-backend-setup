#!/bin/bash

HARP_PORT_BASE="${HARP_PORT_BASE:-8780}"                    # Default base port for internal HaRP container ports. Override in settings.sh if needed.
HARP_EXTERNAL_PORT_BASE="${HARP_EXTERNAL_PORT_BASE:-18780}" # Default base port for external HTTPS reverse-proxied HaRP ports. Override in settings.sh if needed.
HARP_BASE_DIR="$NCHPB_DOCKER_RUNTIME_DIR/harp"
HARP_TEMPLATE_COMPOSE_PATH="$TMP_DIR_PATH/harp/docker-compose.yml"
HARP_TEMPLATE_NGINX_CONF_PATH="$TMP_DIR_PATH/harp/harp-exapps.conf.template"

# Explicitly document naming behavior for both compose-managed and HaRP-spawned containers.
HARP_CONTAINER_NAMING_POLICY="Compose resources are prefixed via per-instance project name. HaRP-spawned containers use slug prefix when supported by upstream runtime, else instance labels/network scoping applies."

declare -A HARP_INSTANCE_IDS
declare -A HARP_INSTANCE_PORTS
declare -A HARP_INSTANCE_HTTPS_PORTS
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

	harp_config_sanity_check || return $?

	for idx in "${!NEXTCLOUD_SERVER_FQDNS[@]}"; do
		local nc_server
		local instance_index
		local nc_server_slug
		local instance_id
		local instance_dir
		local local_port
		local https_port
		local nc_instance_url
		local hp_shared_key
		local project_name

		nc_server="${NEXTCLOUD_SERVER_FQDNS[$idx]}"
		instance_index=$((idx + 1))
		nc_server_slug="$(echo "$nc_server" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
		if [ -z "$nc_server_slug" ]; then
			HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]="failed"
			HARP_SETUP_ERRORS+=("compose deploy: failed to generate slug for '$nc_server'")
			DOCKER_SETUP_ERRORS+=("compose deploy: failed to generate slug for '$nc_server'")
			continue
		fi

		instance_id="${nc_server_slug}-${instance_index}"
		instance_dir="$HARP_BASE_DIR/$instance_id"
		local_port=$((HARP_PORT_BASE + idx))
		https_port=$((HARP_EXTERNAL_PORT_BASE + idx))
		nc_instance_url="https://$nc_server"
		hp_shared_key="$(openssl rand -hex 32)"
		project_name="nchpb-harp-$instance_id"

		if [ "${#hp_shared_key}" -lt 12 ]; then
			HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]="failed"
			HARP_SETUP_ERRORS+=("compose deploy: generated HP_SHARED_KEY too short for instance '$instance_id'")
			DOCKER_SETUP_ERRORS+=("compose deploy: shared key length guard failed for '$instance_id'")
			continue
		fi

		if ! is_dry_run && ! harp_preflight_port_free "$local_port" "$instance_id" "exapps" "$project_name"; then
			HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]="failed"
			HARP_SETUP_ERRORS+=("compose deploy: local exapps port '$local_port' already in use for '$instance_id'")
			DOCKER_SETUP_ERRORS+=("compose deploy: exapps port conflict '$local_port' for '$instance_id'")
			continue
		fi

		HARP_INSTANCE_IDS["$nc_server"]="$instance_id"
		HARP_INSTANCE_PORTS["$nc_server"]="$local_port"
		HARP_INSTANCE_HTTPS_PORTS["$nc_server"]="$https_port"
		HARP_INSTANCE_SHARED_KEYS["$nc_server"]="$hp_shared_key"
		HARP_INSTANCE_PROJECT_NAMES["$nc_server"]="$project_name"

		HARP_SERVER_FQDN_ESC=$(printf '%s' "$SERVER_FQDN" | sed -e "$awk_escape_sed_replacement")
		SSL_CERT_PATH_RSA_ESC=$(printf '%s' "$SSL_CERT_PATH_RSA" | sed -e "$awk_escape_sed_replacement")
		SSL_CERT_KEY_PATH_RSA_ESC=$(printf '%s' "$SSL_CERT_KEY_PATH_RSA" | sed -e "$awk_escape_sed_replacement")
		SSL_CHAIN_PATH_RSA_ESC=$(printf '%s' "$SSL_CHAIN_PATH_RSA" | sed -e "$awk_escape_sed_replacement")
		SSL_CERT_PATH_ECDSA_ESC=$(printf '%s' "$SSL_CERT_PATH_ECDSA" | sed -e "$awk_escape_sed_replacement")
		SSL_CERT_KEY_PATH_ECDSA_ESC=$(printf '%s' "$SSL_CERT_KEY_PATH_ECDSA" | sed -e "$awk_escape_sed_replacement")
		SSL_CHAIN_PATH_ECDSA_ESC=$(printf '%s' "$SSL_CHAIN_PATH_ECDSA" | sed -e "$awk_escape_sed_replacement")
		DHPARAM_PATH_ESC=$(printf '%s' "$DHPARAM_PATH" | sed -e "$awk_escape_sed_replacement")
		DNS_RESOLVER_ESC=$(printf '%s' "$DNS_RESOLVER" | sed -e "$awk_escape_sed_replacement")
		PROJECT_NAME_ESC=$(printf '%s' "$project_name" | sed -e "$awk_escape_sed_replacement")

		rendered_nginx_conf_path="$TMP_DIR_PATH/harp/harp-exapps-${instance_index}.conf"
		if ! cp "$HARP_TEMPLATE_NGINX_CONF_PATH" "$rendered_nginx_conf_path" 2>&1 | tee -a "$LOGFILE_PATH"; then
			HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]="failed"
			HARP_SETUP_ERRORS+=("compose deploy: failed copying nginx template for '$instance_id'")
			DOCKER_SETUP_ERRORS+=("compose deploy: nginx template copy failed for '$instance_id'")
			continue
		fi

		if ! sed -i "s|{{SERVER_FQDN}}|$HARP_SERVER_FQDN_ESC|g" "$rendered_nginx_conf_path" \
			|| ! sed -i "s|{{SSL_CERT_PATH_RSA}}|$SSL_CERT_PATH_RSA_ESC|g" "$rendered_nginx_conf_path" \
			|| ! sed -i "s|{{SSL_CERT_KEY_PATH_RSA}}|$SSL_CERT_KEY_PATH_RSA_ESC|g" "$rendered_nginx_conf_path" \
			|| ! sed -i "s|{{SSL_CHAIN_PATH_RSA}}|$SSL_CHAIN_PATH_RSA_ESC|g" "$rendered_nginx_conf_path" \
			|| ! sed -i "s|{{SSL_CERT_PATH_ECDSA}}|$SSL_CERT_PATH_ECDSA_ESC|g" "$rendered_nginx_conf_path" \
			|| ! sed -i "s|{{SSL_CERT_KEY_PATH_ECDSA}}|$SSL_CERT_KEY_PATH_ECDSA_ESC|g" "$rendered_nginx_conf_path" \
			|| ! sed -i "s|{{SSL_CHAIN_PATH_ECDSA}}|$SSL_CHAIN_PATH_ECDSA_ESC|g" "$rendered_nginx_conf_path" \
			|| ! sed -i "s|{{DHPARAM_PATH}}|$DHPARAM_PATH_ESC|g" "$rendered_nginx_conf_path" \
			|| ! sed -i "s|{{DNS_RESOLVER}}|$DNS_RESOLVER_ESC|g" "$rendered_nginx_conf_path" \
			|| ! sed -i "s|{{HARP_HTTPS_PORT}}|$https_port|g" "$rendered_nginx_conf_path" \
			|| ! sed -i "s|{{HARP_LOCAL_PORT}}|$local_port|g" "$rendered_nginx_conf_path" \
			|| ! sed -i "s|{{PROJECT_NAME}}|$PROJECT_NAME_ESC|g" "$rendered_nginx_conf_path"; then
			HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]="failed"
			HARP_SETUP_ERRORS+=("compose deploy: failed rendering nginx config for '$instance_id'")
			DOCKER_SETUP_ERRORS+=("compose deploy: nginx template substitution failed for '$instance_id'")
			continue
		fi

		if grep -qE '\{\{[A-Z_]+\}\}' "$rendered_nginx_conf_path"; then
			HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]="failed"
			HARP_SETUP_ERRORS+=("compose deploy: incomplete placeholder substitution in '$rendered_nginx_conf_path' for '$instance_id'")
			DOCKER_SETUP_ERRORS+=("compose deploy: incomplete nginx template substitution for '$instance_id'")
			log_err "Incomplete placeholder substitution in '$rendered_nginx_conf_path' for '$instance_id'."
			continue
		fi

		# Deploy to sites-available and symlink into sites-enabled.
		is_dry_run "Would've created sites-available and sites-enabled dirs." || {
			mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled || {
				HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]="failed"
				HARP_SETUP_ERRORS+=("compose deploy: failed creating nginx sites dirs for '$instance_id'")
				DOCKER_SETUP_ERRORS+=("compose deploy: nginx sites dir creation failed for '$instance_id'")
				continue
			}
		}

		deploy_file "$rendered_nginx_conf_path" "/etc/nginx/sites-available/harp-exapps-${instance_index}.conf"

		is_dry_run "Would've symlinked sites-enabled/harp-exapps-${instance_index}.conf." || {
			ln -sf "/etc/nginx/sites-available/harp-exapps-${instance_index}.conf" "/etc/nginx/sites-enabled/harp-exapps-${instance_index}.conf" || {
				HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]="failed"
				HARP_SETUP_ERRORS+=("compose deploy: failed symlinking nginx vhost for '$instance_id'")
				DOCKER_SETUP_ERRORS+=("compose deploy: nginx vhost symlink failed for '$instance_id'")
				continue
			}
		}

		# Open UFW for the public HTTPS port.
		if ! ufw_allow_harp_ports "$https_port"; then
			HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]="failed"
			HARP_SETUP_ERRORS+=("compose deploy: failed opening UFW port '$https_port' for '$instance_id'")
			DOCKER_SETUP_ERRORS+=("compose deploy: UFW port '$https_port' not opened for '$instance_id'")
			continue
		fi

		is_dry_run "Would've validated nginx config with 'nginx -t'." || {
			nginx -t 2>&1 | tee -a "$LOGFILE_PATH" || {
				HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]="failed"
				HARP_SETUP_ERRORS+=("compose deploy: nginx -t failed for '$instance_id'")
				DOCKER_SETUP_ERRORS+=("compose deploy: nginx config invalid for '$instance_id'")
				continue
			}
		}

		# Set state even in dry-run mode
		if is_dry_run "Would've prepared and deployed HaRP docker container for instance '$instance_id' (compose + verify, local exapps port '$local_port')."; then
			HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]="dry-run (skipped)"
			continue
		fi

		if ! harp_prepare_instance "$instance_dir" "$nc_instance_url" "$hp_shared_key" "$local_port" "$project_name" "$instance_id"; then
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

		if ! harp_verify_instance "$instance_dir" "$project_name" "$local_port" "$hp_shared_key" "$instance_id"; then
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
		log "Deployed HaRP instance '$instance_id' for '$nc_server' on local exapps port '$local_port' (public HTTPS port $https_port)."
	done

	if [ "$DRY_RUN" = true ]; then
		DOCKER_PHASE_COMPOSE_DEPLOY_STATUS="dry-run (skipped)"
		DOCKER_PHASE_VERIFY_STATUS="dry-run (skipped)"
		DOCKER_PHASE_PROXY_INTEGRATION_STATUS="dry-run (skipped)"
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
		DOCKER_PHASE_PROXY_INTEGRATION_STATUS="completed"
		log "HaRP deployment completed successfully."
	fi

	return 0
}

function harp_config_sanity_check() {
	# Reject duplicate NEXTCLOUD_SERVER_FQDNS entries (whitespace-trimmed, lowercased).
	# The `|| true` guard keeps the pipeline from aborting under `set -eo pipefail`.
	dups=$(printf '%s\n' "${NEXTCLOUD_SERVER_FQDNS[@]}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]' | sort | uniq -d | tr '\n' ' ' 2>/dev/null || true)
	if [ -n "$dups" ]; then
		for dup in $dups; do
			HARP_SETUP_ERRORS+=("compose deploy: duplicate NEXTCLOUD_SERVER_FQDNS entry '$dup'")
			DOCKER_SETUP_ERRORS+=("compose deploy: duplicate Nextcloud instance domain '$dup'")
		done
		DOCKER_PHASE_COMPOSE_DEPLOY_STATUS="failed"
		DOCKER_PHASE_VERIFY_STATUS="failed"
		log_err "Duplicate Nextcloud instance domains detected: $dups"
		return 1
	fi

	if ! [[ "$HARP_PORT_BASE" =~ ^[0-9]+$ ]]; then
		HARP_SETUP_ERRORS+=("compose deploy: HARP_PORT_BASE must be numeric, got '$HARP_PORT_BASE'")
		DOCKER_PHASE_COMPOSE_DEPLOY_STATUS="failed"
		DOCKER_PHASE_VERIFY_STATUS="failed"
		DOCKER_SETUP_ERRORS+=("compose deploy: invalid HARP_PORT_BASE '$HARP_PORT_BASE'")
		log_err "Invalid HARP_PORT_BASE '$HARP_PORT_BASE'."
		return 1
	fi

	if [ "$HARP_PORT_BASE" -lt 1024 ] || [ "$HARP_PORT_BASE" -gt 65535 ]; then
		HARP_SETUP_ERRORS+=("compose deploy: HARP_PORT_BASE must be between 1024 and 65535, got '$HARP_PORT_BASE'")
		DOCKER_PHASE_COMPOSE_DEPLOY_STATUS="failed"
		DOCKER_PHASE_VERIFY_STATUS="failed"
		DOCKER_SETUP_ERRORS+=("compose deploy: invalid HARP_PORT_BASE range '$HARP_PORT_BASE'")
		log_err "Invalid HARP_PORT_BASE '$HARP_PORT_BASE'. Allowed range is 1024..65535."
		return 1
	fi

	if ! [[ "$HARP_EXTERNAL_PORT_BASE" =~ ^[0-9]+$ ]]; then
		HARP_SETUP_ERRORS+=("compose deploy: HARP_EXTERNAL_PORT_BASE must be numeric, got '$HARP_EXTERNAL_PORT_BASE'")
		DOCKER_PHASE_COMPOSE_DEPLOY_STATUS="failed"
		DOCKER_PHASE_VERIFY_STATUS="failed"
		DOCKER_SETUP_ERRORS+=("compose deploy: invalid HARP_EXTERNAL_PORT_BASE '$HARP_EXTERNAL_PORT_BASE'")
		log_err "Invalid HARP_EXTERNAL_PORT_BASE '$HARP_EXTERNAL_PORT_BASE'."
		return 1
	fi

	if [ "$HARP_EXTERNAL_PORT_BASE" -lt 1024 ] || [ "$HARP_EXTERNAL_PORT_BASE" -gt 65535 ]; then
		HARP_SETUP_ERRORS+=("compose deploy: HARP_EXTERNAL_PORT_BASE must be between 1024 and 65535, got '$HARP_EXTERNAL_PORT_BASE'")
		DOCKER_PHASE_COMPOSE_DEPLOY_STATUS="failed"
		DOCKER_PHASE_VERIFY_STATUS="failed"
		DOCKER_SETUP_ERRORS+=("compose deploy: invalid HARP_EXTERNAL_PORT_BASE range '$HARP_EXTERNAL_PORT_BASE'")
		log_err "Invalid HARP_EXTERNAL_PORT_BASE '$HARP_EXTERNAL_PORT_BASE'. Allowed range is 1024..65535."
		return 1
	fi

	# Upper-bound check: the LAST instance's HTTPS port must be <= 65535.
	n_harp_instances=${#NEXTCLOUD_SERVER_FQDNS[@]}
	if [ "$n_harp_instances" -gt 0 ]; then
		last_https_port=$((HARP_EXTERNAL_PORT_BASE + n_harp_instances - 1))
		if [ "$last_https_port" -gt 65535 ]; then
			HARP_SETUP_ERRORS+=("compose deploy: HARP_EXTERNAL_PORT_BASE $HARP_EXTERNAL_PORT_BASE with $n_harp_instances instances yields last HTTPS port $last_https_port (exceeds 65535)")
			DOCKER_PHASE_COMPOSE_DEPLOY_STATUS="failed"
			DOCKER_PHASE_VERIFY_STATUS="failed"
			DOCKER_SETUP_ERRORS+=("compose deploy: HARP_EXTERNAL_PORT_BASE upper-bound violated: $HARP_EXTERNAL_PORT_BASE + ($n_harp_instances-1) = $last_https_port > 65535")
			log_err "Invalid HARP_EXTERNAL_PORT_BASE '$HARP_EXTERNAL_PORT_BASE' for $n_harp_instances instances: last HTTPS port $last_https_port > 65535."
			return 1
		fi
	fi

	# Upper-bound check: the LAST instance's local exapps port must be <= 65535.
	if [ "$n_harp_instances" -gt 0 ]; then
		last_local_port=$((HARP_PORT_BASE + n_harp_instances - 1))
		if [ "$last_local_port" -gt 65535 ]; then
			HARP_SETUP_ERRORS+=("compose deploy: HARP_PORT_BASE $HARP_PORT_BASE with $n_harp_instances instances yields last local port $last_local_port (exceeds 65535)")
			DOCKER_PHASE_COMPOSE_DEPLOY_STATUS="failed"
			DOCKER_PHASE_VERIFY_STATUS="failed"
			DOCKER_SETUP_ERRORS+=("compose deploy: HARP_PORT_BASE upper-bound violated: $HARP_PORT_BASE + ($n_harp_instances-1) = $last_local_port > 65535")
			log_err "Invalid HARP_PORT_BASE '$HARP_PORT_BASE' for $n_harp_instances instances: last local port $last_local_port > 65535."
			return 1
		fi
	fi

	# Range-overlap check: the local exapps range must not overlap the external HTTPS range.
	if [ "$n_harp_instances" -gt 0 ] \
		&& [ "$HARP_PORT_BASE" -le $((HARP_EXTERNAL_PORT_BASE + n_harp_instances - 1)) ] \
		&& [ "$HARP_EXTERNAL_PORT_BASE" -le $((HARP_PORT_BASE + n_harp_instances - 1)) ]; then
		HARP_SETUP_ERRORS+=("compose deploy: local HaRP port range overlaps the external HTTPS port range")
		DOCKER_PHASE_COMPOSE_DEPLOY_STATUS="failed"
		DOCKER_PHASE_VERIFY_STATUS="failed"
		DOCKER_SETUP_ERRORS+=("compose deploy: local HaRP port range overlaps the external HTTPS port range")
		log_err "Invalid port configuration: local HaRP port range overlaps the external HTTPS port range."
		return 1
	fi

	if [ "${#NEXTCLOUD_SERVER_FQDNS[@]}" -eq 0 ]; then
		HARP_SETUP_ERRORS+=("compose deploy: NEXTCLOUD_SERVER_FQDNS is empty")
		DOCKER_PHASE_COMPOSE_DEPLOY_STATUS="failed"
		DOCKER_PHASE_VERIFY_STATUS="failed"
		DOCKER_SETUP_ERRORS+=("compose deploy: missing Nextcloud instance domains")
		log_err "No Nextcloud domains available for HaRP deployment."
		return 1
	fi

	if [ ! -f "$HARP_TEMPLATE_COMPOSE_PATH" ]; then
		HARP_SETUP_ERRORS+=("compose deploy: missing template '$HARP_TEMPLATE_COMPOSE_PATH'")
		DOCKER_PHASE_COMPOSE_DEPLOY_STATUS="failed"
		DOCKER_PHASE_VERIFY_STATUS="failed"
		DOCKER_SETUP_ERRORS+=("compose deploy: missing HaRP compose template in tmp dir")
		log_err "Missing HaRP template '$HARP_TEMPLATE_COMPOSE_PATH'."
		return 1
	fi
}

function harp_prepare_instance() {
	local instance_dir="$1"
	local nc_instance_url="$2"
	local hp_shared_key="$3"
	local instance_port="$4"
	local project_name="$5"
	local instance_id="$6"
	local compose_file_path="$instance_dir/docker-compose.yml"

	install -d -m 0770 -o "$NCHPB_DOCKER_USER" -g "$NCHPB_DOCKER_GROUP" "$HARP_BASE_DIR" 2>&1 | tee -a "$LOGFILE_PATH"
	install -d -m 0770 -o "$NCHPB_DOCKER_USER" -g "$NCHPB_DOCKER_GROUP" "$instance_dir" 2>&1 | tee -a "$LOGFILE_PATH"

	cp "$HARP_TEMPLATE_COMPOSE_PATH" "$compose_file_path" 2>&1 | tee -a "$LOGFILE_PATH"

	nc_instance_url_esc=$(printf '%s' "$nc_instance_url" | sed -e "$awk_escape_sed_replacement")
	instance_port_esc=$(printf '%s' "$instance_port" | sed -e "$awk_escape_sed_replacement")
	project_name_esc=$(printf '%s' "$project_name" | sed -e "$awk_escape_sed_replacement")
	instance_id_esc=$(printf '%s' "$instance_id" | sed -e "$awk_escape_sed_replacement")

	sed -i "s|<NC_INSTANCE_URL>|$nc_instance_url_esc|g" "$compose_file_path"
	sed -i "s|<HARP_PORT>|$instance_port_esc|g" "$compose_file_path"
	sed -i "s|<HARP_COMPOSE_PROJECT>|$project_name_esc|g" "$compose_file_path"
	sed -i "s|<HARP_INSTANCE_ID>|$instance_id_esc|g" "$compose_file_path"
	replace_placeholder_in_files "<HP_SHARED_KEY>" "$hp_shared_key" "$compose_file_path"

	if grep -q "<NC_INSTANCE_URL>\|<HARP_PORT>\|<HARP_COMPOSE_PROJECT>\|<HARP_INSTANCE_ID>\|<HP_SHARED_KEY>" "$compose_file_path"; then
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
	local project_name="$4"

	if command -v ss >/dev/null 2>&1; then
		if ss -ltn "sport = :$port" 2>/dev/null | tail -n +2 | grep -q .; then
			# Allow re-runs when the occupied port belongs to the same compose project.
			if command -v docker >/dev/null 2>&1; then
				if docker ps \
					--filter "label=com.docker.compose.project=$project_name" \
					--format '{{.Ports}}' 2>/dev/null | grep -q "127.0.0.1:$port->"; then
					log "Port '$port' for '$instance_id' ($role) is already bound by compose project '$project_name'; allowing reuse."
					return 0
				fi
			fi

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
		echo -e "HaRP external port base: $HARP_EXTERNAL_PORT_BASE"
		echo -e "HaRP naming policy: $HARP_CONTAINER_NAMING_POLICY"
		for nc_server in "${NEXTCLOUD_SERVER_FQDNS[@]}"; do
			deploy_status="${HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]}"
			https_port="${HARP_INSTANCE_HTTPS_PORTS["$nc_server"]}"
			instance_id="${HARP_INSTANCE_IDS["$nc_server"]}"
			local_port="${HARP_INSTANCE_PORTS["$nc_server"]}"
			project_name="${HARP_INSTANCE_PROJECT_NAMES["$nc_server"]}"
			shared_key="${HARP_INSTANCE_SHARED_KEYS["$nc_server"]}"

			echo -e "Instance domain: $nc_server"
			echo -e "  Instance ID: $instance_id"
			echo -e "  Compose project: $project_name"
			echo -e "  Local exapps port: $local_port"
			echo -e "  Public HTTPS port: $https_port"
			echo -e "  Deploy status: $deploy_status"
			echo -e "  HP shared key: $shared_key"
		done
	} >> "$1"
}

function docker_harp_print_info() {
	log "=== Docker HaRP Setup ==="
	if [ ${#HARP_SETUP_ERRORS[@]} -gt 0 ]; then
		log_err "HaRP setup phase failures:"
		for err in "${HARP_SETUP_ERRORS[@]}"; do
			log_err "  - $err"
		done
	else
		for nc_server in "${NEXTCLOUD_SERVER_FQDNS[@]}"; do
			deploy_status="${HARP_INSTANCE_DEPLOY_STATUSES["$nc_server"]}"
			https_port="${HARP_INSTANCE_HTTPS_PORTS["$nc_server"]}"
			instance_id="${HARP_INSTANCE_IDS["$nc_server"]}"
			project_name="${HARP_INSTANCE_PROJECT_NAMES["$nc_server"]}"
			shared_key="${HARP_INSTANCE_SHARED_KEYS["$nc_server"]}"

			if [ -z "$instance_id" ]; then
				continue
			fi

			log "\nHaRP registration for ${cyan}$nc_server${blue} (instance ${cyan}$instance_id${blue}, status ${cyan}$deploy_status${blue}):"
			log "  1. Log into Nextcloud ${magenta}https://$nc_server${blue} as administrator."
			log "  2. Install and enable the ${cyan}AppAPI${blue} app."
			# These are instructions how to register via UI. Unfortunately HTTPS setting is hidden in the UI, so we recommend using occ instead.
			# log "  3. Open ${cyan}Settings -> Administration -> AppAPI${blue}."
			# log "  4. Click ${cyan}Add new HaRP instance${blue} and choose ${cyan}HaRP Proxy (Docker)${blue}."
			# log "  5. Paste HP shared key: ${cyan}$shared_key${blue}"
			# log "  6. Replace ${cyan}appapi-harp:8780${blue} with ${cyan}$SERVER_FQDN:$https_port${blue} (no scheme, no trailing slash)."
			# log "  7. Enable ${cyan}Deactivate FRP${blue}."
			# log "  8. Set docker network to ${cyan}${project_name}_default${blue}."
			# log "  9. Click ${cyan}Check connection${blue} and verify success."
			# log ""
			log "  3. Register daemon via ${white}occ ${yellow}(Do not register via AppAPI Nextcloud UI - the HTTPS setting is hidden unfortunately)${blue}:"
			log "    - ${red}On containerized installs like Nextcloud AIO: Prefix the following occ command with"
			log "      * ${yellow}docker exec -u www-data -it nextcloud-aio-nextcloud php"
			log "    - ${cyan}occ app_api:daemon:register harp_proxy_host \"$(hostname -s) HaRP\" docker-install \\${normal}"
			log "      ${cyan}https $SERVER_FQDN:$https_port \"https://$nc_server\" \\${normal}"
			log "      ${cyan}--net ${project_name}_default --harp --harp_frp_address \"none\" \\${normal}"
			log "      ${cyan}--harp_shared_key '$shared_key' --harp_exapp_direct --set-default${normal}"
			log ""
			log "  4. Route ExApps path on the Nextcloud host to this proxy (one-time per Nextcloud instance):"
			log "    - ${green}Nextcloud Standalone${blue}: If you're using your own reverse proxy, use this URL:"
			log "      * ${cyan}https://${SERVER_FQDN}:${https_port}/exapps"
			log "      * See ${magenta}https://github.com/nextcloud/HaRP#configuring-your-reverse-proxy${blue} for details and examples."
			log ""
			log "    - ${green}Nextcloud AIO${blue}: Not supported for an external HaRP"
			log "      * See ${magenta}https://github.com/nextcloud/app_api/blob/main/docs/appapi/aio.md#what-not-to-do-on-aio${blue}"
			log ""
			log "  5. Verify the HaRP proxy is working:"
			log "    - Execute this command on any machine (preferably on your local machine):"
			log "      * ${cyan}curl -fsS -H \"harp-shared-key: $shared_key\" -H \"docker-engine-port: 24000\" https://$SERVER_FQDN:$https_port/exapps/app_api/v1.44/_ping"
			log "      * Expected output is: OK"
			log "    - Visit using webbrowser: ${magenta}https://${nc_server}/settings/admin/app_api"
			log "    - Under "Deploy daemons" -> Click on the 3 dots on the newly registered daemon."
			log "    - Click "Test deploy" and wait for the result."
			log ""
		done

		log "\nSee the wiki for more details: ${magenta}https://github.com/sunweaver/nextcloud-high-performance-backend-setup/wiki${blue}"
	fi
}
