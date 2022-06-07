#!/bin/bash

# !!! Be careful, this script will be executed by the root user. !!!

# -----------------------------------------------------------------------
# Try to install the high-performance-backend server without any user input.
UNATTENTED_INSTALL=false

SERVER_FQDN="nextcloud-hpb.example.invalid"

# Collabora
SHOULD_INSTALL_COLLABORA=true

# Signaling
SHOULD_INSTALL_SIGNALING=true
# -----------------------------------------------------------------------

LOGFILE_PATH="setup-nextcloud-hpb-$(date +%Y-%m-%dT%H:%M:%SZ).log"

# Dry run (Don't actually alter anything on the system.)
DRY_RUN=true

set -eo pipefail

function log() {
    if [ "$UNATTENTED_INSTALL" = true ]; then
        echo "$@" 2>&1 | tee -a $LOGFILE_PATH
    else
        echo "$@"
    fi
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

    scripts=('src/setup-collabora.sh' 'src/setup-signaling.sh')
    for script in "${scripts[@]}"; do
        log "Sourcing '$script'."
        source "$script"
    done

    install_collabora
    install_signaling
}

# Execute main function.
main

set +eo pipefail
