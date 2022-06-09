#!/bin/bash

function install_nginx() {
    if [ "$SHOULD_INSTALL_NGINX" != true ]; then
        log "Won't install nginx, since" \
            "\$SHOULD_INSTALL_NGINX is *not* true."
        return 0
    fi

    log "Installing nginx…"

    # apt install nginx
    if ! is_dry_run; then
        if [ "$UNATTENTED_INSTALL" == true ]; then
            log "Trying unattented install for nginx."
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -qqy nginx 2>&1 | tee -a $LOGFILE_PATH
        else
            apt-get install -y nginx 2>&1 | tee -a $LOGFILE_PATH
        fi
    fi

    deploy_file "$TMP_DIR_PATH"nginx/nextcloud-hpb.conf /etc/nginx/sites-enabled/nextcloud-hpb.conf || true

    is_dry_run || systemctl enable --now nginx

    log "nginx install completed."
}
