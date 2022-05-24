#!/bin/bash

# Collabora Online server
# https://github.com/CollaboraOnline/online
should_install_collabora=true
# Signaling server
# https://github.com/strukturag/nextcloud-spreed-signaling
should_install_signaling=true

# -----------------------------------------------------------------------
# Try to install high-performance-backend servers without any user input.
unattented_install=true
signaling_domain="signaling.example.org"
collabora_domain="collabora.example.org"
# -----------------------------------------------------------------------

# Be careful, this script will be executed by root.
logfile="setup-nextcloud-hpb.log"

# Not empty => Dry run (Don't actually alter anything on the system.)
DRY_RUN="yes"

set -x

function log() {
    if [ "$unattented_install" = true ]; then
        echo "$1" 2>&1 | tee -a $logfile
    else
        echo "$1"
    fi
}

function check_root_perm() {
    if [[ $(id -u) -ne 0 ]]; then
        log "Please run this script as root."
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
    fi
}

function is_dry_run() {
    if [ -n "$DRY_RUN" ]; then
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

    is_dry_run && log "Running in dry-mode."

    if [ "$unattented_install" = true ]; then
        log "Trying unattented installation."
    fi

    install_collabora
}

# Execute main
main
