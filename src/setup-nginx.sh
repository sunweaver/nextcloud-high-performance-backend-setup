#!/bin/bash

function install_nginx() {
    if [ "$SHOULD_INSTALL_NGINX" != true ]; then
        log "Won't install Nginx, since" \
            "\$SHOULD_INSTALL_NGINX is *not* true."
        return 0
    fi

    log "Installing Nginx…"

    # apt install Nginx
    if ! is_dry_run; then
        if [ "$UNATTENTED_INSTALL" == true ]; then
            log "Trying unattented install for Nginx."
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -qqy nginx 2>&1 | tee -a $LOGFILE_PATH
        else
            apt-get install -y nginx 2>&1 | tee -a $LOGFILE_PATH
        fi
    fi

    deploy_file "$TMP_DIR_PATH"nginx/nextcloud-hpb.conf /etc/nginx/sites-enabled/nextcloud-hpb.conf || true

    is_dry_run || systemctl enable --now nginx

    log "Nginx install completed."
}

function nginx_print_info() {
    if [ "$SHOULD_INSTALL_NGINX" == true ]; then
        log "Nginx got installed which acts as a reverse proxy for Signaling" \
            "and Collabora. No extra configuration needed.\n"
    else
        return 0
    fi

    if [ "$SHOULD_INSTALL_LETSENCRYPT" != true ]; then
        log "Except one thing. Since you choose to not install an automatic" \
            "\nSSL-Certificate renewer (certbot for example), you need to make" \
            "\nsure that at all time a valid SSL-Cert is located at: " \
            "\n'$SSL_CERT_PATH' and '$SSL_CERT_KEY_PATH'.\n"
    fi
}
