#!/bin/bash

# Signaling server
# https://github.com/strukturag/nextcloud-spreed-signaling

function install_signaling() {
    if [ "$should_install_signaling" != true ]; then
        log "Won't install Signaling, since" \
            "\$should_install_signaling is *not* true."
        return 0
    fi

    log "Installing Signaling…"
}
