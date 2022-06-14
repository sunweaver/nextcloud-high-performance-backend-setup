#!/bin/bash

# !!! Be careful, this script will be executed by the root user. !!!

# -----------------------------------------------------------------------
# Try to install the high-performance-backend server without any user input.
UNATTENTED_INSTALL=false

NEXTCLOUD_SERVER_FQDN="nextcloud-server.example.invalid"
SERVER_FQDN="nextcloud-hpb.example.invalid"

# Collabora
SHOULD_INSTALL_COLLABORA=true

# Signaling
SHOULD_INSTALL_SIGNALING=true

# nginx (needed by Signaling & Collabora)
SHOULD_INSTALL_NGINX=true

SSL_CERT_PATH="/path/to/ssl/cert"
SSL_CERT_KEY_PATH="/path/to/ssl/cert.key"
# -----------------------------------------------------------------------

LOGFILE_PATH="setup-nextcloud-hpb-$(date +%Y-%m-%dT%H:%M:%SZ).log"

# Configuration gets copied and prepared here before copying them into place.
TMP_DIR_PATH="tmp"

# Dry run (Don't actually alter anything on the system. (except in $TMP_DIR_PATH))
DRY_RUN=true

set -eo pipefail

function log() {
    if [ "$UNATTENTED_INSTALL" = true ]; then
        echo -e "$@" 2>&1 | tee -a $LOGFILE_PATH
    else
        echo -e "$@"
    fi
}

# Deploys target_file_path to source_file_path while respecting
# potential custom user config. The user will be asked before overwriting files.
# param 1: source_file_path
# param 2: target_file_path
# returns: 1 if already deployed and 0 if not.
function deploy_file() {
    source_file_path="$1"
    target_file_path="$2"
    log "Deploying $target_file_path"
    if [[ -s "$target_file_path" ]]; then
        checksum_deployed=$(sha256sum "$target_file_path" | cut -d " " -f1)
        checksum_expected=$(sha256sum "$source_file_path" | cut -d " " -f1)
        if [ "${checksum_deployed}" = "${checksum_expected}" ]; then
            log "$target_file_path was already deployed."
            return 1
        else
            if [ "$UNATTENTED_INSTALL" = true ]; then
                cp "$source_file_path" "$target_file_path"
            else
                read -p "Overwrite file '$target_file_path'? [Yy] " -n 1 -r && echo
                if [[ $REPLY =~ ^[YyJj]$ ]]; then
                    log "$target_file_path to be updated deployed."
                    is_dry_run || cp "$source_file_path" "$target_file_path"
                else
                    log "$target_file_path won't be updated."
                fi
            fi
        fi
    else
        # Target file is empty or doesn't exist.
        is_dry_run || cp "$source_file_path" "$target_file_path"
    fi
    return 0
}

function check_root_perm() {
    if [[ $(id -u) -ne 0 ]]; then
        log "Please run the this (setup-nextcloud-hpb) script as root."
        exit 1
    fi
}

function check_debian_system() {
    # File exists and not empty
    if ! [ -s /etc/debian_version ]; then
        log "Couldn't read /etc/debian_version! Is this a debian system?"
        exit 1
    else
        DEBIAN_VERSION=$(cat /etc/debian_version)

        # Quick hack for debian testing (currently bookworm)
        if [[ "$DEBIAN_VERSION" = "bookworm/sid" ]]; then
            DEBIAN_VERSION="11.3"
        fi

        if ! [[ $DEBIAN_VERSION =~ [0-9] ]]; then
            log "Debian version '$DEBIAN_VERSION' not supported!"
            exit 1
        fi

        DEBIAN_MAJOR_VERSION=$(echo $DEBIAN_VERSION | grep -o -E "[0-9][0-9]")
    fi
}

function is_dry_run() {
    if [ "$DRY_RUN" == true ]; then
        return 0
    else
        return 1
    fi
}

function main() {
    check_root_perm

    check_debian_system

    if [ -s "$LOGFILE_PATH" ]; then
        rm $LOGFILE_PATH
    fi

    log "$(date)"

    is_dry_run &&
        log "Running in dry-mode. This script won't actually do anything on" \
            "your system!"

    if [ "$UNATTENTED_INSTALL" = true ]; then
        log "Trying unattented installation."
    fi

    if ! [ -e "$TMP_DIR_PATH" ]; then
        log "Creating '$TMP_DIR_PATH'."
        mkdir -p "$TMP_DIR_PATH" 2>&1 | tee -a $LOGFILE_PATH
    else
        REPLY=""
        while ! [[ $REPLY =~ ^[YyJj]$ ]]; do
            if [ "$UNATTENTED_INSTALL" = false ]; then
                read -p "Delete * in '$TMP_DIR_PATH'? [Yy] " -n 1 -r && echo
            else
                break
            fi
        done

        log "Deleted contents of '$TMP_DIR_PATH'."
        rm -vr "$TMP_DIR_PATH"/* 2>&1 | tee -a $LOGFILE_PATH || true
    fi

    log "Moving config files into '$TMP_DIR_PATH'."
    cp -rv data/* "$TMP_DIR_PATH" 2>&1 | tee -a $LOGFILE_PATH

    log "Deleting every '127.0.1.1' entry in /etc/hosts."
    is_dry_run || sed -i "/127.0.1.1/d" /etc/hosts

    entry="127.0.1.1 $SERVER_FQDN $(hostname)"
    log "Deploying '$entry' in /etc/hosts."
    is_dry_run || echo "$entry" >>/etc/hosts

    scripts=('src/setup-collabora.sh' 'src/setup-signaling.sh'
        'src/setup-nginx.sh')
    for script in "${scripts[@]}"; do
        log "Sourcing '$script'."
        source "$script"
    done

    install_nginx
    install_collabora
    install_signaling

    log "Every installation completed."

    log "======================================================================"
    nginx_print_info
    collabora_print_info
    signaling_print_info
    log "======================================================================"

    log "\nThank you for using this script.\n"
}

# Execute main function.
main

set +eo pipefail
