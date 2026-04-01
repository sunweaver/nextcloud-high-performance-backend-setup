#!/bin/bash

# This file was created by the Nextcloud High-performance setup script.
#
# This is a hook script for certbot, which gets executed after each certificate
# renewal.

# Fix permissions of the generated certificates, so that the services can read them.
chmod 2750 /etc/letsencrypt/archive
chmod 2750 /etc/letsencrypt/live
find /etc/letsencrypt/archive -type d -exec chmod 2750 {} +
find /etc/letsencrypt/live -type d -exec chmod 2750 {} +
chown -R :ssl-cert /etc/letsencrypt/archive
chown -R :ssl-cert /etc/letsencrypt/live
find /etc/letsencrypt/archive -name "privkey*.pem" -exec chmod 640 {} +

# Restart/reload services that need to read the certificates.
#   - nginx
#   - coturn
SERVICES_TO_RELOAD=(nginx coturn)
for service in "${SERVICES_TO_RELOAD[@]}"; do
	if systemctl is-active --quiet "$service"; then
		systemctl reload-or-restart "$service" || {
			echo "Failed to restart/reload $service after certificate renewal."
			echo "Please check the service status and logs for more details."
			echo "journalctl -u $service"
			exit 1
		}
	fi
done
