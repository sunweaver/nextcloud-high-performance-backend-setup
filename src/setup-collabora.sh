#!/bin/bash

# Collabora Online server
# https://github.com/CollaboraOnline/online
# https://www.collaboraoffice.com/code/linux-packages/

KEYRING_URL="https://collaboraoffice.com/downloads/gpg/collaboraonline-release-keyring.gpg"
KEYRING_DIR="/usr/share/keyrings"
KEYRING_FILE="$KEYRING_DIR/collaboraonline-release-keyring.gpg"

SOURCES_FILE="/etc/apt/sources.list.d/collaboraonline.sources"
REPO_URL="https://www.collaboraoffice.com/repos/CollaboraOnline/CODE-debian$DEBIAN_MAJOR_VERSION"

function install_collabora() {
    if [ "$should_install_collabora" != true ]; then
        log "Won't install Collabora, since" \
            "\$should_install_collabora is *not* true."
        return 0
    fi

    log "Installing Collabora…"

    step1
    step2
    step3
    step4
}

function step1() {
    # 1. Import the signing key
    log "Step 1: Import the signing key"

    cd $KEYRING_DIR
    is_dry_run || wget "$KEYRING_URL" || exit 1
    cd -
}

function step2() {
    # 2. Add CODE package repositories
    log "Step 2: Add CODE package repositories"

    is_dry_run || cat <<EOF >$SOURCES_FILE
Types: deb
URIs: $REPO_URL
Suites: ./
Signed-By: $KEYRING_FILE
EOF
}

function step3() {
    # 3. Install packages
    log "Step 3: Install packages"

    is_dry_run || apt update 2>&1 | tee -a $logfile

    # Installing:
    #   - coolwsd
    #   - code-brand
    #   - nginx (for a secure ws reverse-proxy.)
    if [ ! is_dry_run ]; then
        if [ "$unattented_install" == true ]; then
            log "Trying unattented install for Collabora."
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -qqy coolwsd code-brand nginx 2>&1 | tee -a $logfile
        else
            apt-get install -y coolwsd code-brand nginx 2>&1 | tee -a $logfile
        fi
    fi
}

function step4() {
    # 4. Configuration
    log "Step 4: Configuration"

    # is_dry_run || Edit /etc/coolwsd/coolwsd.xml…

    is_dry_run || systemctl restart coolwsd
}
