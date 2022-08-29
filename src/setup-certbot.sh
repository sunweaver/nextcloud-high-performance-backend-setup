#!/bin/bash

function run_certbot_command() {
	arg_dry_run=""
	if is_dry_run; then
		arg_dry_run="--dry-run"
	fi

	arg_interactive=""
	if [ "$UNATTENTED_INSTALL" == true ]; then
		arg_interactive="--non-interactive --agree-tos"
	else
		arg_interactive="--force-interactive $CERTBOT_AGREE_TOS"
	fi

	certbot_args=(certonly --nginx $arg_interactive $arg_dry_run
		--key-path "$SSL_CERT_KEY_PATH" --domains "$SERVER_FQDN"
		--fullchain-path "$SSL_CERT_PATH" --email "$EMAIL_ADDRESS")

	log "Executing Certbot using arguments: '${certbot_args[@]}'…"

	if certbot "${certbot_args[@]}" |& tee -a $LOGFILE_PATH; then
		:
	else
		return 1
	fi

	certbot_args=(renew --force-renewal $arg_dry_run)

	log "Executing Certbot using arguments: '${certbot_args[@]}'…"

	if certbot "${certbot_args[@]}" |& tee -a $LOGFILE_PATH; then
		return 0
	else
		return 1
	fi
}

function install_certbot() {
	log "Installing Certbot…"

	log "\nStep 1: Installing Certbot packages"
	if ! is_dry_run; then
		if [ "$UNATTENTED_INSTALL" == true ]; then
			log "Trying unattended install for Certbot."
			export DEBIAN_FRONTEND=noninteractive
			apt-get install -qqy python3-certbot-nginx certbot 2>&1 | tee -a $LOGFILE_PATH
		else
			apt-get install -y python3-certbot-nginx certbot 2>&1 | tee -a $LOGFILE_PATH
		fi
	fi

	log "\nStep 2: Configuring Certbot"

	if ! run_certbot_command; then
		log "Something wen't wrong while starting Certbot."

		if [ "$UNATTENTED_INSTALL" != true ]; then
			log "Maybe the error is in the nextcloud-hpb.conf" \
				"file (please read the error message above).\n"
			read -p "Do you wish to delete this file:$(
			)'/etc/nginx/sites-enabled/nextcloud-hbp.conf'? [YyNn]" -n 1 -r && echo
			if [[ $REPLY =~ ^[YyJj]$ ]]; then
				rm -v "/etc/nginx/sites-enabled/nextcloud-hpb.conf" |& tee -a $LOGFILE_PATH || true
				log "File got deleted. Please try again now."
			fi
		fi

		exit 1
	fi

	log "Certbot install completed."
}

# arg: $1 is secret file path
function certbot_write_secrets_to_file() {
	# No secrets, passwords, keys or something to worry about.
	if is_dry_run; then
		return 0
	fi

	echo -e "=== Certbot ===" >>$1
	echo -e "Notifications regarding SSL certificates get sent to:" >>$1
	echo -e " ↳ '$EMAIL_ADDRESS'" >>$1
}

function certbot_print_info() {
	log "SSL certificate we're installed successfully and get refreshed" \
		"\nautomatically by Certbot."
	log "Notifications regarding SSL-Certificates get sent to:"
	log " ↳ '$EMAIL_ADDRESS'"
}
