#!/bin/bash

# Tracks the last certbot failure class for better user-facing follow-up messages.
CERTBOT_LAST_ERROR_KIND=""

normalize_domains() {
	echo "$1" | tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}

certbot_log_has_rate_limit_error() {
	tail -n 50 "$LOGFILE_PATH" | grep -Eiq 'too many certificates|exact set of identifiers|rate limit'
}

# args: $1 certificate name, $2 expected domain list (space separated)
certbot_existing_matching_certificate_is_not_close_to_expiry() {
	local cert_name="$1"
	local expected_domains="$2"
	local certbot_output=""
	local expected_domains_normalized=""
	local line=""
	local current_cert_name=""
	local current_domains=""
	local current_domains_normalized=""
	local valid_days_until_expiry=""
	local minimum_days_until_expiry=30

	certbot_output="$(certbot certificates 2>/dev/null || true)"
	if [[ -z "$certbot_output" ]]; then
		# No certificates found, so we cannot verify if a matching certificate exists.
		return 1
	fi

	expected_domains_normalized="$(normalize_domains "$expected_domains")"

	while IFS= read -r line; do
		if [[ "$line" =~ ^[[:space:]]*Certificate[[:space:]]Name:[[:space:]]*(.*)$ ]]; then
			current_cert_name="${BASH_REMATCH[1]}"
			# Reset parsed state to avoid carrying over data from previous cert blocks.
			current_domains=""
			current_domains_normalized=""
			valid_days_until_expiry=""
			continue
		fi

		if [[ "$line" =~ ^[[:space:]]*Domains:[[:space:]]*(.*)$ ]]; then
			current_domains="${BASH_REMATCH[1]}"
			continue
		fi

		# Note: If a certificate expires in less than 24 hours, Certbot outputs
		# e.g. "(VALID: 23 hours)". This regex intentionally fails in that case,
		# which is correct behavior since we require at least 30 days anyway.
		if [[ "$line" =~ VALID:[[:space:]]*([0-9]+)[[:space:]]*days ]]; then
			valid_days_until_expiry="${BASH_REMATCH[1]}"
			current_domains_normalized="$(normalize_domains "$current_domains")"

			if [[ "$valid_days_until_expiry" -gt "$minimum_days_until_expiry" ]] && \
			   [[ "$current_cert_name" == "$cert_name" ]] && \
			   [[ "$current_domains_normalized" == "$expected_domains_normalized" ]]; then
				return 0
			fi
		fi
	done <<<"$certbot_output"

	return 1
}

# args: $1 certificate name, $2 expected domain list, $3 title, $4 message, $5 extra message
handle_certbot_rate_limit() {
	local cert_name="$1"
	local expected_domains="$2"
	local error_title_ratelimited="$3"
	local error_message_ratelimited="$4"
	local error_message_ratelimited_extra="$5"

	if ! certbot_log_has_rate_limit_error; then
		# No rate-limit error found in the last 50 lines of the log file, so we assume it's a different error.
		return 1
	fi

	CERTBOT_LAST_ERROR_KIND="rate_limit"

	if certbot_existing_matching_certificate_is_not_close_to_expiry "$cert_name" "$expected_domains"; then
		log "Rate-limit hit, but existing certificate '$cert_name' is still valid and not close to expiry. Keeping it unchanged."
		return 0
	fi

	if [[ "$UNATTENDED_INSTALL" != true ]]; then
		if whiptail --title "$error_title_ratelimited" --defaultno \
			--yesno "$error_message_ratelimited $error_message_ratelimited_extra" 16 65 3>&1 1>&2 2>&3; then
			# Recursively call this function
			run_certbot_command "true"
			return $?
		fi
	else
		log "$error_message_ratelimited"
	fi

	return 1
}

# Warning: recursive function
# $1 can enable staging certificates arguments for certbot if $1 = "true".
run_certbot_command() {
	local use_staging_request="$1"
	local arg_dry_run=""
	local arg_interactive=""
	local arg_staging=""
	local error_message_ratelimited=""
	local error_message_ratelimited_extra=""
	local error_title_ratelimited=""
	local -a certbot_args=()

	CERTBOT_LAST_ERROR_KIND=""

	if is_dry_run; then
		arg_dry_run="--dry-run"
	fi

	if [[ "$UNATTENDED_INSTALL" == true ]]; then
		arg_interactive="--non-interactive --agree-tos"
	else
		arg_interactive="--force-interactive $CERTBOT_AGREE_TOS"
	fi

	if [[ "$use_staging_request" == "true" ]] || [[ "$CERTBOT_SSL_USE_STAGING_CERTS" == true ]]; then
		arg_staging="--staging --break-my-certs"
	fi

	error_message_ratelimited=$(echo -e "You have issued too many certificates already $(
	)in the last 168 hours. You have to wait before you can issue another certificate.\n$(
	)Please see https://letsencrypt.org/docs/rate-limits/")

	error_message_ratelimited_extra=$(echo -e "\nIf you are currently testing: $(
	)Do you want to enable testing certificates?\n\n$(
	)PROCEED WITH CAUTION! You will break your current SSL certificates if you $(
	)choose to enable testing certificates.")

	error_title_ratelimited="LetsEncrypt rate limit reached!"

	#
	# --- RSA certificate ---
	#
	certbot_args=(certonly --nginx $arg_staging $arg_interactive $arg_dry_run
		--key-path "$SSL_CERT_KEY_PATH_RSA" --domains "$SERVER_FQDN"
		--fullchain-path "$SSL_CERT_PATH_RSA" --email "$EMAIL_USER_ADDRESS"
		--rsa-key-size 4096 --cert-name "$SERVER_FQDN"-rsa
		--chain-path "$SSL_CHAIN_PATH_RSA")

	# Skip issuance when an existing matching certificate is not close to expiry.
	if ! certbot_existing_matching_certificate_is_not_close_to_expiry "$SERVER_FQDN-rsa" "$SERVER_FQDN"; then
		log "Executing Certbot using arguments: '${certbot_args[@]}'…"

		if ! certbot "${certbot_args[@]}" |& tee -a "$LOGFILE_PATH"; then
			if ! handle_certbot_rate_limit "$SERVER_FQDN-rsa" "$SERVER_FQDN" \
				"$error_title_ratelimited" "$error_message_ratelimited" "$error_message_ratelimited_extra"; then
				return 1
			fi
		fi
	else
		log "Existing matching RSA certificate '$SERVER_FQDN-rsa' is not close to expiry. Skipping issuance."
	fi

	#
	# --- ECDSA certificate ---
	#
	certbot_args=(certonly --nginx $arg_staging $arg_interactive $arg_dry_run
		--key-path "$SSL_CERT_KEY_PATH_ECDSA" --domains "$SERVER_FQDN"
		--fullchain-path "$SSL_CERT_PATH_ECDSA" --email "$EMAIL_USER_ADDRESS"
		--key-type ecdsa --cert-name "$SERVER_FQDN"-ecdsa
		--chain-path "$SSL_CHAIN_PATH_ECDSA")

	# Skip issuance when an existing matching certificate is not close to expiry.
	if ! certbot_existing_matching_certificate_is_not_close_to_expiry "$SERVER_FQDN-ecdsa" "$SERVER_FQDN"; then
		log "Executing Certbot using arguments: '${certbot_args[@]}'…"

		if ! certbot "${certbot_args[@]}" |& tee -a "$LOGFILE_PATH"; then
			if ! handle_certbot_rate_limit "$SERVER_FQDN-ecdsa" "$SERVER_FQDN" \
				"$error_title_ratelimited" "$error_message_ratelimited" "$error_message_ratelimited_extra"; then
				return 1
			fi
		fi
	else
		log "Existing matching ECDSA certificate '$SERVER_FQDN-ecdsa' is not close to expiry. Skipping issuance."
	fi

	# Force renewal of certificates
	certbot_args=(renew --force-renewal $arg_staging $arg_interactive $arg_dry_run)

	log "Executing Certbot using arguments: '${certbot_args[@]}'…"

	if certbot "${certbot_args[@]}" |& tee -a "$LOGFILE_PATH"; then
		return 0
	else
		if handle_certbot_rate_limit "$SERVER_FQDN-rsa" "$SERVER_FQDN" \
			"$error_title_ratelimited" "$error_message_ratelimited" "$error_message_ratelimited_extra"; then
			return 0
		fi
	fi
}

install_certbot() {
	announce_installation "Installing Certbot"
	log "Installing Certbot…"

	certbot_step1
	certbot_step2

	log "Certbot install completed."
}

certbot_step1() {
	log "\n${green}Step 1: Installing Certbot packages"
	local -a packages_to_install=(python3-certbot-nginx certbot ssl-cert)
	if ! is_dry_run; then
		if [[ "$UNATTENDED_INSTALL" == true ]]; then
			log "Trying unattended install for Certbot."
			export DEBIAN_FRONTEND=noninteractive
			apt-get install -qqy "${packages_to_install[@]}" 2>&1 | tee -a "$LOGFILE_PATH"
		else
			apt-get install -y "${packages_to_install[@]}" 2>&1 | tee -a "$LOGFILE_PATH"
		fi
	else
		log "Would have installed '${packages_to_install[@]}' via APT now."
	fi
}

certbot_step2() {
	log "\n${green}Step 2: Configuring Certbot"

	generate_dhparam_file

	if ! run_certbot_command && ! is_dry_run; then
		log_err "Something went wrong while starting Certbot."

		if [[ "$CERTBOT_LAST_ERROR_KIND" == "rate_limit" ]] || certbot_log_has_rate_limit_error; then
			log_err "Certbot hit a Let's Encrypt rate limit."
			exit 1
		fi

		if [[ "$UNATTENDED_INSTALL" != true ]]; then
			log_err "Maybe the error is in the nextcloud-hpb.conf" \
			        "file (please read the error message above).\n"
			read -p "Do you wish to delete this file:$(
			)'/etc/nginx/sites-enabled/nextcloud-hpb.conf'? [YyNn]" -n 1 -r && echo
			if [[ $REPLY =~ ^[YyJj]$ ]]; then
				rm -v "/etc/nginx/sites-enabled/nextcloud-hpb.conf" |& tee -a "$LOGFILE_PATH" || true
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
certbot_write_secrets_to_file() {
	# No secrets, passwords, keys or something to worry about.
	if is_dry_run; then
		return 0
	fi

	echo -e "=== Certbot ===" >>"$1"
	echo -e "Notifications regarding SSL certificates get sent to:" >>"$1"
	echo -e " - '$EMAIL_USER_ADDRESS'" >>"$1"
}

certbot_print_info() {
	log "SSL certificate were installed successfully and get refreshed" \
		"\nautomatically by Certbot."
	log "Notifications regarding SSL-Certificates get sent to:"
	log " - ${cyan}'$EMAIL_USER_ADDRESS'"
}
