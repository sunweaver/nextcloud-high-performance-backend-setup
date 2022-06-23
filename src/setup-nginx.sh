#!/bin/bash

function install_nginx() {
    if [ "$SHOULD_INSTALL_NGINX" != true ]; then
        log "Won't install Nginx, since" \
            "\$SHOULD_INSTALL_NGINX is *not* true."
        return 0
    fi

    log "Installing Nginx…"

    nginx_step1
    nginx_step2
    nginx_step3

    log "Restarting service…"
    is_dry_run || systemctl enable --now nginx || true

    if is_dry_run || service nginx restart; then
        log "Nginx restarted succesfully."
    else
        # This has to have some consequences…
        log "Nginx did *not* restart succesfully."
    fi

    log "Nginx install completed."
}

function nginx_step1() {
    log "\nStep 1: Installing Nginx package"
    if ! is_dry_run; then
        if [ "$UNATTENTED_INSTALL" == true ]; then
            log "Trying unattented install for Nginx."
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -qqy nginx 2>&1 | tee -a $LOGFILE_PATH
        else
            apt-get install -y nginx 2>&1 | tee -a $LOGFILE_PATH
        fi
    fi
}

function nginx_step2() {
    log "\nStep 2: Prepare configuration"
    include_snippet_signaling_forwarding=""
    include_snippet_signaling_upstream_servers=""
    if [ "$SHOULD_INSTALL_SIGNALING" == true ]; then
        include_snippet_signaling_forwarding="# Signaling\n  include snippets/signaling-forwarding.conf;\n"
        include_snippet_signaling_upstream_servers="include snippets/signaling-upstream-servers.conf;\n"
        log "Replacing '<INCLUDE_SNIPPET_SIGNALING_FORWARDING>' with '$include_snippet_signaling_forwarding'…"
        log "Replacing '<INCLUDE_SNIPPET_SIGNALING_UPSTREAM_SERVERS>' with '$include_snippet_signaling_upstream_servers'…"
    fi
    sed -i "s|<INCLUDE_SNIPPET_SIGNALING_FORWARDING>|$include_snippet_signaling_forwarding|g" "$TMP_DIR_PATH"/nginx/nextcloud-hpb.conf
    sed -i "s|<INCLUDE_SNIPPET_SIGNALING_UPSTREAM_SERVERS>|$include_snippet_signaling_upstream_servers|g" "$TMP_DIR_PATH"/nginx/nextcloud-hpb.conf

    include_snippet_collabora=""
    if [ "$SHOULD_INSTALL_COLLABORA" == true ]; then
        include_snippet_collabora="# Collabora\n  include snippets/coolwsd.conf;"
        log "Replacing '<INCLUDE_SNIPPET_COLLABORA>' with '$include_snippet_collabora'…"
    fi
    sed -i "s|<INCLUDE_SNIPPET_COLLABORA>|$include_snippet_collabora|g" "$TMP_DIR_PATH"/nginx/nextcloud-hpb.conf

    log "Replacing '<HOST_FQDN>' with '$SERVER_FQDN'…"
    sed -i "s|<HOST_FQDN>|$SERVER_FQDN|g" "$TMP_DIR_PATH"/nginx/*

    log "Replacing '<SSL_CERT_PATH>' with '$SSL_CERT_PATH'…"
    sed -i "s|<SSL_CERT_PATH>|$SSL_CERT_PATH|g" "$TMP_DIR_PATH"/nginx/*

    log "Replacing '<SSL_CERT_KEY_PATH>' with '$SSL_CERT_KEY_PATH'…"
    sed -i "s|<SSL_CERT_KEY_PATH>|$SSL_CERT_KEY_PATH|g" "$TMP_DIR_PATH"/nginx/*
}

function nginx_step3() {
    log "Deploying config files…"
    deploy_file "$TMP_DIR_PATH"/nginx/nextcloud-hpb.conf /etc/nginx/sites-enabled/nextcloud-hpb.conf || true
}

# arg: $1 is secret file path
function nginx_write_secrets_to_file() {
    # No secrets, passwords, keys or something to worry about.
    if is_dry_run; then
        return 0
    fi
}

function nginx_print_info() {
    if [ "$SHOULD_INSTALL_NGINX" == true ]; then
        log "Nginx got installed which acts as a reverse proxy for Signaling" \
            "and Collabora. No extra configuration needed.\n"
    else
        return 1
    fi

    if [ "$SHOULD_INSTALL_LETSENCRYPT" != true ]; then
        log "Except one thing. Since you choose to not install an automatic" \
            "\nSSL-Certificate renewer (certbot for example), you need to make" \
            "\nsure that at all time a valid SSL-Cert is located at: " \
            "\n'$SSL_CERT_PATH' and '$SSL_CERT_KEY_PATH'."
    fi
}
