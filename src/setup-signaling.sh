#!/bin/bash

# Signaling server
# https://github.com/strukturag/nextcloud-spreed-signaling

SIGNALING_SUNWEAVER_SOURCE_FILE="/etc/apt/sources.list.d/sunweaver.list"

SIGNALING_TURN_STATIC_AUTH_SECRET="$(openssl rand -hex 32)"
SIGNALING_JANUS_API_KEY="$(openssl rand -base64 16)"
SIGNALING_HASH_KEY="$(openssl rand -hex 16)"
SIGNALING_BLOCK_KEY="$(openssl rand -hex 16)"
SIGNALING_NEXTCLOUD_SECRET_KEY="$(openssl rand -hex 16)"

SIGNALING_NEXTCLOUD_URL="https://$NEXTCLOUD_SERVER_FQDN"
SIGNALING_COTURN_URL="$SERVER_FQDN"

function install_signaling() {
    if [ "$SHOULD_INSTALL_SIGNALING" != true ] ||
        [ "$SHOULD_INSTALL_NGINX" != true ]; then
        log "Won't install Signaling, since" \
            "\$SHOULD_INSTALL_SIGNALING or \$SHOULD_INSTALL_NGINX is *not* true."
        return 0
    fi

    log "Installing Signaling…"

    signaling_step1
    signaling_step2
    signaling_step3
    signaling_step4
    signaling_step5

    log "Signaling install completed."
}

function signaling_step1() {
    log "\nStep 1: Import sunweaver's gpg key."
    is_dry_run || wget http://packages.sunweavers.net/archive.key \
        -O /etc/apt/trusted.gpg.d/sunweaver-archive-keyring.asc
}

function signaling_step2() {
    log "\nStep 2: Add sunweaver package repository"

    is_dry_run || cat <<EOF >$SIGNALING_SUNWEAVER_SOURCE_FILE
# Added by nextcloud-high-performance-backend setup-script.
deb http://packages.sunweavers.net/debian bookworm main
EOF
}

function signaling_step3() {
    log "\nStep 3: Install packages"

    is_dry_run || apt update 2>&1 | tee -a $LOGFILE_PATH

    # Installing:
    # - janus
    # - nats Server
    # - nextcloud-spreed-signaling
    # - coturn
    if ! is_dry_run; then
        if [ "$UNATTENTED_INSTALL" == true ]; then
            log "Trying unattented install for Collabora."
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -qqy janus nats-server \
                nextcloud-spreed-signaling coturn 2>&1 | tee -a $LOGFILE_PATH
        else
            apt-get install -y janus nats-server \
                nextcloud-spreed-signaling coturn 2>&1 | tee -a $LOGFILE_PATH
        fi
    fi
}

function signaling_step4() {
    log "\nStep 4: Prepare configuration"

    is_dry_run || (mkdir -p /etc/turnserver/ && touch /etc/turnserver/dhp.pem)
    is_dry_run || openssl dhparam -dsaparam -out /etc/turnserver/dhp.pem 4096
    is_dry_run || adduser turnserver ssl-cert

    # Don't actually *log* passwords! (Or do for debugging…)

    # log "Replacing '<SIGNALING_TURN_STATIC_AUTH_SECRET>' with '$SIGNALING_TURN_STATIC_AUTH_SECRET'…"
    log "Replacing '<SIGNALING_TURN_STATIC_AUTH_SECRET>'…"
    sed -i "s|<SIGNALING_TURN_STATIC_AUTH_SECRET>|$SIGNALING_TURN_STATIC_AUTH_SECRET|g" "$TMP_DIR_PATH"/signaling/*

    # log "Replacing '<SIGNALING_JANUS_API_KEY>' with '$SIGNALING_JANUS_API_KEY'…"
    log "Replacing '<SIGNALING_JANUS_API_KEY>…'"
    sed -i "s|<SIGNALING_JANUS_API_KEY>|$SIGNALING_JANUS_API_KEY|g" "$TMP_DIR_PATH"/signaling/*

    # log "Replacing '<SIGNALING_HASH_KEY>' with '$SIGNALING_HASH_KEY'…"
    log "Replacing '<SIGNALING_HASH_KEY>…'"
    sed -i "s|<SIGNALING_HASH_KEY>|$SIGNALING_HASH_KEY|g" "$TMP_DIR_PATH"/signaling/*

    # log "Replacing '<SIGNALING_BLOCK_KEY>' with '$SIGNALING_BLOCK_KEY'…"
    log "Replacing '<SIGNALING_BLOCK_KEY>…'"
    sed -i "s|<SIGNALING_BLOCK_KEY>|$SIGNALING_BLOCK_KEY|g" "$TMP_DIR_PATH"/signaling/*

    # log "Replacing '<SIGNALING_NEXTCLOUD_SECRET_KEY>' with '$SIGNALING_NEXTCLOUD_SECRET_KEY'…"
    log "Replacing '<SIGNALING_NEXTCLOUD_SECRET_KEY>…'"
    sed -i "s|<SIGNALING_NEXTCLOUD_SECRET_KEY>|$SIGNALING_NEXTCLOUD_SECRET_KEY|g" "$TMP_DIR_PATH"/signaling/*

    log "Replacing '<SIGNALING_NEXTCLOUD_URL>' with '$SIGNALING_NEXTCLOUD_URL'…"
    sed -i "s|<SIGNALING_NEXTCLOUD_URL>|$SIGNALING_NEXTCLOUD_URL|g" "$TMP_DIR_PATH"/signaling/*

    log "Replacing '<SIGNALING_COTURN_URL>' with '$SIGNALING_COTURN_URL'…"
    sed -i "s|<SIGNALING_COTURN_URL>|$SIGNALING_COTURN_URL|g" "$TMP_DIR_PATH"/signaling/*

    log "Replacing '<SSL_CERT_PATH>' with '$SSL_CERT_PATH'…"
    sed -i "s|<SSL_CERT_PATH>|$SSL_CERT_PATH|g" "$TMP_DIR_PATH"/signaling/*

    log "Replacing '<SSL_CERT_KEY_PATH>' with '$SSL_CERT_KEY_PATH'…"
    sed -i "s|<SSL_CERT_KEY_PATH>|$SSL_CERT_KEY_PATH|g" "$TMP_DIR_PATH"/signaling/*

    EXTERN_IPv4=$(wget -4 ident.me -O - -o /dev/null || true)
    log "Replacing '<SIGNALING_COTURN_EXTERN_IPV4>' with '$EXTERN_IPv4'…"
    sed -i "s|<SIGNALING_COTURN_EXTERN_IPV4>|$EXTERN_IPv4|g" "$TMP_DIR_PATH"/signaling/*

    EXTERN_IPv6=$(wget -6 ident.me -O - -o /dev/null || true)
    log "Replacing '<SIGNALING_COTURN_EXTERN_IPV6>' with '$EXTERN_IPv6'…"
    sed -i "s|<SIGNALING_COTURN_EXTERN_IPV6>|$EXTERN_IPv6|g" "$TMP_DIR_PATH"/signaling/*
}

function signaling_step5() {
    log "\nStep 5: Deploy configuration"

    deploy_file "$TMP_DIR_PATH"/signaling/nginx-signaling-upstream-servers.conf /etc/nginx/snippets/signaling-upstream-servers.conf || true
    deploy_file "$TMP_DIR_PATH"/signaling/nginx-signaling-forwarding.conf /etc/nginx/snippets/signaling-forwarding.conf || true

    deploy_file "$TMP_DIR_PATH"/signaling/janus.jcfg /etc/janus/janus.jcfg || true
    deploy_file "$TMP_DIR_PATH"/signaling/janus.transport.http.jcfg /etc/janus/janus.transport.http.jcfg || true
    deploy_file "$TMP_DIR_PATH"/signaling/janus.transport.websockets.jcfg /etc/janus/janus.transport.websockets.jcfg || true

    deploy_file "$TMP_DIR_PATH"/signaling/signaling-server.conf /etc/nextcloud-spreed-signaling/server.conf || true

    deploy_file "$TMP_DIR_PATH"/signaling/turnserver.conf /etc/turnserver.conf || true

    is_dry_run || systemctl enable --now janus || true
    is_dry_run || systemctl enable --now nats-server || true
    is_dry_run || systemctl enable --now nextcloud-spreed-signaling || true
    is_dry_run || systemctl enable --now coturn || true

    is_dry_run || service janus restart || true
    is_dry_run || service nats-server restart || true
    is_dry_run || service nextcloud-spreed-signaling restart || true
    is_dry_run || service coturn restart || true
}

# arg: $1 is secret file path
function signaling_write_secrets_to_file() {
    if is_dry_run; then
        return 0
    fi

    echo -e "=== SIGNALING ===" >>$1
    echo -e "Janus API key: $SIGNALING_JANUS_API_KEY" >>$1
    echo -e "Hash key:      $SIGNALING_HASH_KEY" >>$1
    echo -e "Block key:     $SIGNALING_BLOCK_KEY" >>$1
    echo -e "" >>$1
    echo -e "Allowed Nextcloud Server: $NEXTCLOUD_SERVER_FQDN" >>$1
    echo -e "STUN server              = $SERVER_FQDN:1271" >>$1
    echo -e "TURN server              = 'turn and turns' + $SERVER_FQDN:1271 + $SIGNALING_TURN_STATIC_AUTH_SECRET + udp & tcp" >>$1
    echo -e "High-performance backend = wss://$SERVER_FQDN/standalone-signaling + $SIGNALING_NEXTCLOUD_SECRET_KEY" >>$1
}

function signaling_print_info() {
    if [ "$SHOULD_INSTALL_SIGNALING" != true ] ||
        [ "$SHOULD_INSTALL_NGINX" != true ]; then
        # Don't print any info…
        return 1
    fi

    log "The services coturn janus nats-server and nextcloud-signaling-spreed" \
        "got installed.\nTo set it up, log into your Nextcloud instance" \
        "(https://$NEXTCLOUD_SERVER_FQDN) with an adminstrator account\nand install the Talk app." \
        "Then navigate to\nSettings -> Administration -> Talk and put in the following:"

    # Don't actually *log* passwords!
    echo -e "STUN server              = $SERVER_FQDN:1271"
    echo -e "TURN server              = 'turn and turns' + $SERVER_FQDN:1271 + $SIGNALING_TURN_STATIC_AUTH_SECRET + udp & tcp"
    echo -e "High-performance backend = wss://$SERVER_FQDN/standalone-signaling $SIGNALING_NEXTCLOUD_SECRET_KEY"
}
