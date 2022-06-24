#!/bin/bash

function install_certbot() {
    if [ "$SHOULD_INSTALL_CERTBOT" != true ]; then
        log "Won't install Certbot, since \$SHOULD_INSTALL_CERTBOT is *not* true."
        return 0
    fi

    log "Installing Certbot…"

    log "\nStep 1: Installing Certbot packages"
    if ! is_dry_run; then
        if [ "$UNATTENTED_INSTALL" == true ]; then
            log "Trying unattented install for Certbot."
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -qqy python3-certbot-nginx certbot 2>&1 | tee -a $LOGFILE_PATH
        else
            apt-get install -y python3-certbot-nginx certbot 2>&1 | tee -a $LOGFILE_PATH
        fi
    fi

    log "\nStep 2: Configuring Certbot"

    arg_dry_run=""
    if is_dry_run; then
        arg_dry_run="--dry-run"
    fi

    arg_interactive=""
    if [ "$UNATTENTED_INSTALL" == true ]; then
        arg_interactive="--non-interactive --domains "$SERVER_FQDN""
    else
        arg_interactive="--force-interactive"
    fi

    certbot certonly --nginx $arg_interactive $arg_dry_run \
        --key-path "$SSL_CERT_KEY_PATH" \
        --fullchain-path "$SSL_CERT_PATH"

    log "Certbot install completed."
}

# arg: $1 is secret file path
function certbot_write_secrets_to_file() {
    # No secrets, passwords, keys or something to worry about.
    if is_dry_run; then
        return 0
    fi
}

function certbot_print_info() {
    return 0
}
