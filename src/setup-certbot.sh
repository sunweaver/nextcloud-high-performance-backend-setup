#!/bin/bash

# Warning: recursive function
# $1 can enable staging certificates arguments for certbot if $1 = "true".
function run_certbot_command() {
	arg_dry_run=""
	if is_dry_run; then
		arg_dry_run="--dry-run"
	fi

	arg_interactive=""
	if [ "$UNATTENDED_INSTALL" == true ]; then
		arg_interactive="--non-interactive --agree-tos"
	else
		arg_interactive="--force-interactive $CERTBOT_AGREE_TOS"
	fi

	arg_staging=""
	if [ "$1" == "true" ]; then
		arg_staging="--staging --break-my-certs"
	fi

	error_message_ratelimited=$(echo -e "You have issued too many certificates already $(
	)in the last 168 hours. You have to wait before you can issue another certificate.\n$(
	)Please see https://letsencrypt.org/docs/duplicate-certificate-limit/")

	error_message_ratelimited_extra=$(echo -e "\nIf you are currently testing: $(
	)Do you want to enable testing certificates?\n\n$(
	)PROCEED WITH CAUTION! You will break your current SSL certificates if you $(
	)choose to enable testing certificates.")

	error_title_ratelimited="LetsEncrypt rate limit reached!"

	# RSA certificate
	certbot_args=(certonly --nginx $arg_staging $arg_interactive $arg_dry_run
		--key-path "$SSL_CERT_KEY_PATH_RSA" --domains "$SERVER_FQDN"
		--fullchain-path "$SSL_CERT_PATH_RSA" --email "$EMAIL_USER_ADDRESS"
		--rsa-key-size 4096 --cert-name "$SERVER_FQDN"-rsa
		--chain-path "$SSL_CHAIN_PATH_RSA")

	log "Executing Certbot using arguments: '${certbot_args[@]}'…"

	if ! certbot "${certbot_args[@]}" |& tee -a $LOGFILE_PATH; then
		# Checking if Certbot reported rate limit error
		# Let the user decide if they want staging certificates (for testing
		# purposes for example).
		error_ratelimited="$(tail $LOGFILE_PATH | grep 'too many certificates (5) already issued for this exact set of domains in the last 168 hours')"
		if [ -n "$error_ratelimited" ]; then
			if [ "$UNATTENDED_INSTALL" != true ]; then
				if whiptail --title "$error_title_ratelimited" --defaultno \
					--yesno "$error_message_ratelimited $error_message_ratelimited_extra" 16 65 3>&1 1>&2 2>&3; then
					# Recursively call this function
					run_certbot_command "true"
					return 0
				fi
			else
				log "$error_message_ratelimited"
			fi
		fi

		return 1
	fi

	# ECDSA certificate
	certbot_args=(certonly --nginx $arg_staging $arg_interactive $arg_dry_run
		--key-path "$SSL_CERT_KEY_PATH_ECDSA" --domains "$SERVER_FQDN"
		--fullchain-path "$SSL_CERT_PATH_ECDSA" --email "$EMAIL_USER_ADDRESS"
		--key-type ecdsa --cert-name "$SERVER_FQDN"-ecdsa
		--chain-path "$SSL_CHAIN_PATH_ECDSA")

	log "Executing Certbot using arguments: '${certbot_args[@]}'…"

	if ! certbot "${certbot_args[@]}" |& tee -a $LOGFILE_PATH; then
		# Checking if Certbot reported rate limit error
		# Let the user decide if they want staging certificates (for testing
		# purposes for example).
		error_ratelimited="$(tail $LOGFILE_PATH | grep 'too many certificates (5) already issued for this exact set of domains in the last 168 hours')"
		if [ -n "$error_ratelimited" ]; then
			if [ "$UNATTENDED_INSTALL" != true ]; then
				if whiptail --title "$error_title_ratelimited" --defaultno \
					--yesno "$error_message_ratelimited $error_message_ratelimited_extra" 16 65 3>&1 1>&2 2>&3; then
					# Recursively call this function
					run_certbot_command "true"
					return 0
				fi
			else
				log "$error_message_ratelimited"
			fi
		fi

		return 1
	fi

	# Force renewal of certificates
	certbot_args=(renew --force-renewal $arg_staging $arg_interactive $arg_dry_run)

	log "Executing Certbot using arguments: '${certbot_args[@]}'…"

	if certbot "${certbot_args[@]}" |& tee -a $LOGFILE_PATH; then
		return 0
	else
		# Checking if Certbot reported rate limit error
		# Let the user decide if they want staging certificates (for testing
		# purposes for example).
		error_ratelimited="$(tail $LOGFILE_PATH | grep 'too many certificates (5) already issued for this exact set of domains in the last 168 hours')"
		if [ -n "$error_ratelimited" ]; then
			if [ "$UNATTENDED_INSTALL" != true ]; then
				if whiptail --title "$error_title_ratelimited" --defaultno \
					--yesno "$error_message_ratelimited $error_message_ratelimited_extra" 16 65 3>&1 1>&2 2>&3; then
					# Recursively call this function
					run_certbot_command "true"
					return 0
				fi
			else
				log "$error_message_ratelimited"
			fi
		fi
	fi
}

function install_certbot() {
	log "Installing Certbot…"

	certbot_step1
	certbot_step2

	log "Certbot install completed."
}

function certbot_step1() {
	log "\nStep 1: Installing Certbot packages"
	packages_to_install=(python3-certbot-nginx certbot ssl-cert)
	if ! is_dry_run; then
		if [ "$UNATTENDED_INSTALL" == true ]; then
			log "Trying unattended install for Certbot."
			export DEBIAN_FRONTEND=noninteractive
			apt-get install -qqy "${packages_to_install[@]}" 2>&1 | tee -a $LOGFILE_PATH
		else
			apt-get install -y "${packages_to_install[@]}" 2>&1 | tee -a $LOGFILE_PATH
		fi
	else
		log "Would have installed '${packages_to_install[@]}' via APT now."
	fi
}

function certbot_step2() {
	log "\nStep 2: Configuring Certbot"

	generate_dhparam_file

	if ! run_certbot_command && ! is_dry_run; then
		log "Something wen't wrong while starting Certbot."

		if [ "$UNATTENDED_INSTALL" != true ]; then
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

	log "Making SSL certificates available for 'ssl-cert' group."
	is_dry_run || chmod 2750 /etc/letsencrypt/archive
	is_dry_run || chmod 2750 /etc/letsencrypt/live
	is_dry_run || find /etc/letsencrypt/archive -type d -exec chmod 2750 {} +
	is_dry_run || find /etc/letsencrypt/live -type d -exec chmod 2750 {} +
	is_dry_run || chown -R :ssl-cert /etc/letsencrypt/archive
	is_dry_run || chown -R :ssl-cert /etc/letsencrypt/live
	is_dry_run || find /etc/letsencrypt/archive -name "privkey*.pem" -exec chmod 640 {} +

	deploy_file "$TMP_DIR_PATH"/certbot/deploy-hook-certbot.sh /etc/letsencrypt/renewal-hooks/deploy/deploy-hook-certbot.sh || true
	is_dry_run || chmod 750 /etc/letsencrypt/renewal-hooks/deploy/deploy-hook-certbot.sh
}

# arg: $1 is secret file path
function certbot_write_secrets_to_file() {
	# No secrets, passwords, keys or something to worry about.
	if is_dry_run; then
		return 0
	fi

	echo -e "=== Certbot ===" >>$1
	echo -e "Notifications regarding SSL certificates get sent to:" >>$1
	echo -e " - '$EMAIL_USER_ADDRESS'" >>$1
}

function certbot_print_info() {
	log "SSL certificate we're installed successfully and get refreshed" \
		"\nautomatically by Certbot."
	log "Notifications regarding SSL-Certificates get sent to:"
	log " - '$EMAIL_USER_ADDRESS'"
}
