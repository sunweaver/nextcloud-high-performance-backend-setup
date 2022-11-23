#!/bin/bash

# This file was created by the Nextcloud High-performance setup script.

chmod 2750 /etc/letsencrypt/archive
chmod 2750 /etc/letsencrypt/live
find /etc/letsencrypt/archive -type d -exec chmod 2750 {} +
find /etc/letsencrypt/live -type d -exec chmod 2750 {} +
chown -R :ssl-cert /etc/letsencrypt/archive
chown -R :ssl-cert /etc/letsencrypt/live
find /etc/letsencrypt/archive -name "privkey*.pem" -exec chmod 640 {} +
