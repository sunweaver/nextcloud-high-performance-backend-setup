#!/bin/sh

# This file was created be the Nextcloud High-performance setup script.
# Thanks to https://serverfault.com/a/984575.

set -e

for domain in $RENEWED_DOMAINS; do
        case $domain in
        <SIGNALING_COTURN_URL>)
                daemon_cert_root=/etc/coturn/certs

                # Make sure the certificate and private key files are
                # never world readable, even just for an instant while
                # we're copying them into daemon_cert_root.
                umask 077

                cp "$RENEWED_LINEAGE/fullchain.pem" "$daemon_cert_root/$domain.crt"
                cp "$RENEWED_LINEAGE/privkey.pem" "$daemon_cert_root/$domain.key"

                # Apply the proper file ownership and permissions for
                # the daemon to read its certificate and key.
                chown root:turnserver "$daemon_cert_root/$domain.crt" \
                        "$daemon_cert_root/$domain.key"
                chmod 640 "$daemon_cert_root/$domain.crt" \
                        "$daemon_cert_root/$domain.key"

                service coturn restart &> /dev/null
                ;;
        esac
done
