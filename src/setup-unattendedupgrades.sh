#!/bin/bash

function unattendedupgrades_do_preseed() {
	pkg="$1"
	template="$2"
	type="$3"
	value="$4"
	is_dry_run ||
		echo $pkg $template $type "$value" | debconf-set-selections ||
		log "Failed to load preseed '$template'"
}

function unattendedupgrades_do_reconfigure() {
	package="$1"
	log "Silently running dpkg-reconfigure on package $package…"
	is_dry_run || dpkg -l $package 1>/dev/null 2>/dev/null && {
		dpkg-reconfigure -fnoninteractive -pcritical $package &&
			log "Reconfigure DONE" || log "Reconfigure FAILED"
	}
}

function install_unattendedupgrades() {
	announce_installation "Installing unattended-upgrades"
	log "Installing unattended-upgrades…"

	unattendedupgrades_step1
	unattendedupgrades_step2
	unattendedupgrades_step3
	unattendedupgrades_step4

	log "unattended-upgrades install completed."
}

function unattendedupgrades_step1() {
	log "\n${green}Step 1: Install unattended-upgrades package"

	is_dry_run || apt update 2>&1 | tee -a $LOGFILE_PATH

	# Installing:
	#   - unattended-upgrades
	if ! is_dry_run; then
		if [ "$UNATTENDED_INSTALL" == true ]; then
			log "Trying unattended install for unattended upgrades."
			export DEBIAN_FRONTEND=noninteractive
			args_apt="-qqy"
		else
			args_apt="-y"
		fi

		apt-get install "$args_apt" unattended-upgrades \
			2>&1 | tee -a $LOGFILE_PATH

	fi
}

function unattendedupgrades_step2() {
	log "\n${green}Step 2: Preseed and reconfigure unattended-upgrades package"

	if ! is_dry_run; then
		# preseed and reconfigure
		unattendedupgrades_do_preseed \
			unattended-upgrades unattended-upgrades/enable_auto_updates \
			boolean true \
			2>&1 | tee -a $LOGFILE_PATH

		unattendedupgrades_do_reconfigure \
			unattended-upgrades \
			2>&1 | tee -a $LOGFILE_PATH
	fi
}

function unattendedupgrades_step3() {
	log "\n${green}Step 3: Prepare unattended-upgrades configuration"

	UNATTENDED_UPGRADES_ENABLE_COLLABORA_UPGRADES=""
	if [ "$SHOULD_INSTALL_COLLABORA" = true ]; then
		UNATTENDED_UPGRADES_ENABLE_COLLABORA_UPGRADES="\
Unattended-Upgrade::Origins-Pattern {\"site=www.collaboraoffice.com\";}"
	fi

	log "Replacing '<UNATTENDED_UPGRADES_ENABLE_COLLABORA_UPGRADES>' with '$UNATTENDED_UPGRADES_ENABLE_COLLABORA_UPGRADES'…"
	sed -i "s|<UNATTENDED_UPGRADES_ENABLE_COLLABORA_UPGRADES>|$UNATTENDED_UPGRADES_ENABLE_COLLABORA_UPGRADES|g" "$TMP_DIR_PATH"/unattended-upgrades/*
}

function unattendedupgrades_step4() {
	log "\n${green}Step 4: Deploy unattended-upgrades configuration"

	deploy_file "$TMP_DIR_PATH"/unattended-upgrades/60unattended-upgrades-nextcloud-hpb-setup /etc/apt/apt.conf.d/60unattended-upgrades-nextcloud-hpb-setup || true
}

# arg: $1 is secret file path
# function unattendedupgrades_write_secrets_to_file() { }
# function unattendedupgrades_print_info() { }
