#!/bin/bash

# Collabora Online server
# https://github.com/CollaboraOnline/online
# https://www.collaboraoffice.com/code/linux-packages/

COLLABORA_KEYRING_URL="https://collaboraoffice.com/downloads/gpg/collaboraonline-release-keyring.gpg"
COLLABORA_KEYRING_DIR="/usr/share/keyrings"
COLLABORA_KEYRING_FILE="$COLLABORA_KEYRING_DIR/collaboraonline-release-keyring.gpg"

COLLABORA_SOURCES_FILE="/etc/apt/sources.list.d/collaboraonline.sources"
COLLABORA_REPO_URL="https://www.collaboraoffice.com/repos/CollaboraOnline/CODE-debian$DEBIAN_MAJOR_VERSION"

function install_collabora() {
    log "Installing Collabora…"

    collabora_step1
    collabora_step2
    collabora_step3
    collabora_step4
    collabora_step5

    log "Collabora install completed."
}

function collabora_step1() {
    # 1. Import the signing key
    log "\nStep 1: Import the signing key"

    cd $COLLABORA_KEYRING_DIR
    is_dry_run || wget "$COLLABORA_KEYRING_URL" || exit 1
    cd -
}

function collabora_step2() {
    # 2. Add CODE package repositories
    log "\nStep 2: Add CODE package repositories"

    is_dry_run || cat <<EOF >$COLLABORA_SOURCES_FILE
Types: deb
URIs: $COLLABORA_REPO_URL
Suites: ./
Signed-By: $COLLABORA_KEYRING_FILE
EOF
}

function collabora_step3() {
    # 3. Install packages
    log "\nStep 3: Install packages"

    is_dry_run || apt update 2>&1 | tee -a $LOGFILE_PATH

    # Installing:
    #   - coolwsd
    #   - code-brand
    if ! is_dry_run; then
        if [ "$UNATTENTED_INSTALL" == true ]; then
            log "Trying unattented install for Collabora."
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -qqy coolwsd code-brand 2>&1 | tee -a $LOGFILE_PATH
        else
            apt-get install -y coolwsd code-brand 2>&1 | tee -a $LOGFILE_PATH
        fi
    fi
}

function collabora_step4() {
    # 4. Prepare configuration
    log "\nStep 4: Prepare configuration"
}

function collabora_step5() {
    # 5. Deploy configuration
    log "\nStep 5: Deploy configuration"

    deploy_file "$TMP_DIR_PATH"/collabora/snippet-coolwsd.conf /etc/nginx/snippets/coolwsd.conf || true
    is_dry_run || rm /var/www/html/index.nginx-debian.html || true
    deploy_file "$TMP_DIR_PATH"/collabora/index.html /var/www/html/index.html || true
    deploy_file "$TMP_DIR_PATH"/collabora/robots.txt /var/www/html/robots.txt || true

    deploy_file "$TMP_DIR_PATH"/collabora/coolwsd.xml /etc/coolwsd/coolwsd.xml || true
}

# arg: $1 is secret file path
function collabora_write_secrets_to_file() {
    # No secrets, passwords, keys or something to worry about.
    if is_dry_run; then
        return 0
    fi
}

function collabora_print_info() {
    collabora_address="https://$SERVER_FQDN/collabora"

    log "The Collabora Online service got installed. To set it up," \
        "\nlog into your Nextcloud instance with an adminstrator account" \
        "\n(https://$NEXTCLOUD_SERVER_FQDN), install the Nextcloud Office app" \
        "\nand navigate to Settings -> Administration -> Nextcloud Office." \
        "\nNow select 'Use your own server' and type in '$collabora_address'." \
        "\nPlease note that you need to have a working HTTPS setup on your" \
        "\nNextcloud server in order to get Nextcloud Office working."
}
