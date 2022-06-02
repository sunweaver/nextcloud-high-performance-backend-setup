#!/bin/bash

# !!! Be careful, this script will be executed by the root user. !!!

# -----------------------------------------------------------------------
# Try to install the high-performance-backend server without any user input.
unattented_install=false

# Collabora
collabora_domain="collabora.example.org"
should_install_collabora=true

# Signaling
signaling_domain="signaling.example.org"
should_install_signaling=true
# -----------------------------------------------------------------------

logfile="setup-nextcloud-hpb-$(date +%Y-%m-%dT%H:%M:%SZ).log"

# Dry run (Don't actually alter anything on the system.)
DRY_RUN=true

set -eo pipefail

function log() {
    if [ "$unattented_install" = true ]; then
        echo "$@" 2>&1 | tee -a $logfile
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

    if [ -s "$logfile" ]; then
        rm $logfile
    fi

    log "$(date)"

    is_dry_run &&
        log "Running in dry-mode. This script won't actually do anything on" \
            "your system!"

    if [ "$unattented_install" = true ]; then
        log "Trying unattented installation."
    fi

    install_collabora
}

# Execute main function.
main

set +eo pipefail
