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
	log "Installing unattended-upgrades…"

	unattendedupgrades_step1
	unattendedupgrades_step2

	log "unattended-upgrades install completed."
}

function unattendedupgrades_step1() {
	# 1. Install package
	log "\nStep 1: Install package"

	is_dry_run || apt update 2>&1 | tee -a $LOGFILE_PATH

	# Installing:
	#   - unattended-upgrades
	if ! is_dry_run; then
		if [ "$UNATTENTED_INSTALL" == true ]; then
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
	# 2. Preseed and reconfigure package
	log "\nStep 2: Preseed and reconfigure package"

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

# arg: $1 is secret file path
# function unattendedupgrades_write_secrets_to_file() { }
# function unattendedupgrades_print_info() { }
