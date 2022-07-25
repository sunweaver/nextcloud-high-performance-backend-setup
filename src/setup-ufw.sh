#!/bin/bash

function install_ufw() {
	log "Installing UFW…"

	ufw_step1
	ufw_step2

	log "UFW install completed."
}

function ufw_step1() {
	# 1. Install packages
	log "\nStep 1: Install package"

	is_dry_run || apt update 2>&1 | tee -a $LOGFILE_PATH

	# Installing:
	#   - ufw
	if ! is_dry_run; then
		if [ "$UNATTENTED_INSTALL" == true ]; then
			log "Trying unattended install for UFW."
			export DEBIAN_FRONTEND=noninteractive
			args_apt="-qqy"
		else
			args_apt="-y"
		fi

		apt-get install "$args_apt" ufw 2>&1 | tee -a $LOGFILE_PATH
	fi
}

function ufw_step2() {
	# 2. Configure firewall
	log "\nStep 2: Configure firewall"

	# Prefix command with 'log' if in dry run mode.
	local _cmdprefix=""
	is_dry_run && _cmdprefix="log " || true

	${_cmdprefix}ufw default deny incoming
	${_cmdprefix}ufw default allow outgoing

	if [ -e "/etc/ufw/applications.d/openssh-server" ]; then
		${_cmdprefix}ufw allow "OpenSSH"
	fi
	${_cmdprefix}ufw allow "WWW Full"

	_ufwargs=""
	is_dry_run || _ufwargs="--force"
	${_cmdprefix}ufw "$_ufwargs" enable
}

# arg: $1 is secret file path
# function ufw_write_secrets_to_file() { }
# function ufw_print_info() { }
