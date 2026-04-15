#!/bin/bash

NCHPB_DOCKER_USER="nc-hpb"
NCHPB_DOCKER_GROUP="nc-hpb"
NCHPB_DOCKER_BASE_DIR="/var/lib/nc-hpb"
NCHPB_DOCKER_RUNTIME_DIR="$NCHPB_DOCKER_BASE_DIR/docker"

DOCKER_PHASE_INSTALL_STATUS="not started"
DOCKER_PHASE_COMPOSE_DEPLOY_STATUS="pending (phase 3)"
DOCKER_PHASE_VERIFY_STATUS="not started"
DOCKER_PHASE_PROXY_INTEGRATION_STATUS="pending (phase 4)"

declare -a DOCKER_SETUP_ERRORS

function install_docker() {
	announce_installation "Installing Docker platform"
	log "Installing Docker platform support..."

	DOCKER_SETUP_ERRORS=()
	DOCKER_PHASE_INSTALL_STATUS="running"
	DOCKER_PHASE_COMPOSE_DEPLOY_STATUS="pending (phase 3)"
	DOCKER_PHASE_VERIFY_STATUS="not started"
	DOCKER_PHASE_PROXY_INTEGRATION_STATUS="pending (phase 4)"

	if ! docker_step1; then
		DOCKER_PHASE_INSTALL_STATUS="failed"
		DOCKER_SETUP_ERRORS+=("install: failed to install Docker Engine packages")
		log_err "Docker platform setup failed during phase: install"
		return 1
	fi

	if ! docker_step2; then
		DOCKER_PHASE_INSTALL_STATUS="failed"
		DOCKER_SETUP_ERRORS+=("install: failed to prepare nc-hpb Docker runtime user/group/directories")
		log_err "Docker platform setup failed during phase: install"
		return 1
	fi

	DOCKER_PHASE_INSTALL_STATUS="completed"
	DOCKER_PHASE_VERIFY_STATUS="running"

	if ! docker_step3; then
		DOCKER_PHASE_VERIFY_STATUS="failed"
		DOCKER_SETUP_ERRORS+=("verify: failed to verify Docker platform prerequisites")
		log_err "Docker platform setup failed during phase: verify"
		return 1
	fi

	if [ "$DRY_RUN" = true ]; then
		DOCKER_PHASE_VERIFY_STATUS="dry-run (skipped)"
	else
		DOCKER_PHASE_VERIFY_STATUS="completed"
	fi

	log "Docker platform setup completed."
}

function docker_step1() {
	log "\n${green}Step 1: Install Docker Engine packages"

	is_dry_run || apt update 2>&1 | tee -a $LOGFILE_PATH

	if ! is_dry_run; then
		if [ "$UNATTENDED_INSTALL" == true ]; then
			log "Trying unattended install for Docker Engine."
			export DEBIAN_FRONTEND=noninteractive
			args_apt="-qqy"
		else
			args_apt="-y"
		fi

		# Use Debian distribution packages only.
		apt-get install "$args_apt" docker.io docker-compose 2>&1 | tee -a $LOGFILE_PATH
	else
		log "Would've installed Docker packages from Debian repositories: docker.io docker-compose"
	fi
}

function docker_step2() {
	log "\n${green}Step 2: Prepare nc-hpb Docker runtime user and directories"

	if is_dry_run; then
		log "Would've ensured system group '$NCHPB_DOCKER_GROUP'."
		log "Would've ensured system user '$NCHPB_DOCKER_USER'."
		log "Would've created runtime directory '$NCHPB_DOCKER_RUNTIME_DIR' with restrictive permissions."
		return 0
	fi

	if ! getent group "$NCHPB_DOCKER_GROUP" >/dev/null; then
		log "Creating system group '$NCHPB_DOCKER_GROUP'."
		groupadd --system "$NCHPB_DOCKER_GROUP" 2>&1 | tee -a $LOGFILE_PATH
	else
		log "System group '$NCHPB_DOCKER_GROUP' already exists."
	fi

	if ! id -u "$NCHPB_DOCKER_USER" >/dev/null 2>&1; then
		log "Creating system user '$NCHPB_DOCKER_USER'."
		useradd --system --gid "$NCHPB_DOCKER_GROUP" --home-dir "$NCHPB_DOCKER_BASE_DIR" \
			--shell /usr/sbin/nologin "$NCHPB_DOCKER_USER" 2>&1 | tee -a $LOGFILE_PATH
	else
		log "System user '$NCHPB_DOCKER_USER' already exists."
	fi

	install -d -m 0750 -o root -g "$NCHPB_DOCKER_GROUP" "$NCHPB_DOCKER_BASE_DIR" 2>&1 | tee -a $LOGFILE_PATH
	install -d -m 0770 -o "$NCHPB_DOCKER_USER" -g "$NCHPB_DOCKER_GROUP" "$NCHPB_DOCKER_RUNTIME_DIR" 2>&1 | tee -a $LOGFILE_PATH
}

function docker_step3() {
	log "\n${green}Step 3: Verify Docker platform prerequisites"

	if is_dry_run "Would've verified Docker binary and runtime directory ownership."; then
		return 0
	fi

	if ! command -v docker >/dev/null 2>&1; then
		log_err "Docker binary not found after package installation."
		return 1
	fi

	if ! [ -d "$NCHPB_DOCKER_RUNTIME_DIR" ]; then
		log_err "Docker runtime directory '$NCHPB_DOCKER_RUNTIME_DIR' is missing."
		return 1
	fi

	runtime_owner_group=$(stat -c "%U:%G" "$NCHPB_DOCKER_RUNTIME_DIR")
	if [ "$runtime_owner_group" != "$NCHPB_DOCKER_USER:$NCHPB_DOCKER_GROUP" ]; then
		log_err "Unexpected ownership for '$NCHPB_DOCKER_RUNTIME_DIR': '$runtime_owner_group'"
		return 1
	fi

	log "Docker prerequisites validated successfully."
}

# arg: $1 is secret file path
function docker_write_secrets_to_file() {
	if is_dry_run; then
		return 0
	fi

	{
		echo -e "=== Docker Platform Setup ==="
		echo -e "Docker services selected: $DOCKER_SERVICES"
		echo -e "Docker runtime user/group: $NCHPB_DOCKER_USER:$NCHPB_DOCKER_GROUP"
		echo -e "Docker runtime directory: $NCHPB_DOCKER_RUNTIME_DIR"
		echo -e "Phase install: $DOCKER_PHASE_INSTALL_STATUS"
		echo -e "Phase compose deploy: $DOCKER_PHASE_COMPOSE_DEPLOY_STATUS"
		echo -e "Phase verify: $DOCKER_PHASE_VERIFY_STATUS"
		echo -e "Phase proxy integration: $DOCKER_PHASE_PROXY_INTEGRATION_STATUS"
	} >> "$1"
}

function docker_print_info() {
	log "=== Docker Platform Setup ==="
	log "Docker support enabled: ${cyan}$SHOULD_INSTALL_DOCKER"
	log "Docker services selected: ${cyan}$DOCKER_SERVICES"
	log "Docker runtime user/group: ${cyan}$NCHPB_DOCKER_USER:$NCHPB_DOCKER_GROUP"
	log "Docker runtime directory: ${cyan}$NCHPB_DOCKER_RUNTIME_DIR"
	log "Phase install: ${cyan}$DOCKER_PHASE_INSTALL_STATUS"
	log "Phase compose deploy: ${cyan}$DOCKER_PHASE_COMPOSE_DEPLOY_STATUS"
	log "Phase verify: ${cyan}$DOCKER_PHASE_VERIFY_STATUS"
	log "Phase proxy integration: ${cyan}$DOCKER_PHASE_PROXY_INTEGRATION_STATUS"

	if [ ${#DOCKER_SETUP_ERRORS[@]} -gt 0 ]; then
		log_err "Docker setup phase failures:"
		for err in "${DOCKER_SETUP_ERRORS[@]}"; do
			log_err "  - $err"
		done
	fi
}
