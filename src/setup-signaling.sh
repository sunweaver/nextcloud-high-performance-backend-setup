#!/bin/bash

# Signaling server
# https://github.com/strukturag/nextcloud-spreed-signaling

function install_signaling() {
    if [ "$SHOULD_INSTALL_SIGNALING" != true ]; then
        log "Won't install Signaling, since" \
            "\$SHOULD_INSTALL_SIGNALING is *not* true."
        return 0
    fi

    log "Installing Signaling…"
}
