# !!! Be careful, this script will be executed by the root user. !!!

# Dry run (Don't actually alter anything on the system. (except in $TMP_DIR_PATH))
# Leave empty, if you wish that the user will be asked about this.
DRY_RUN=false

# Should the script try to install the high-performance-backend server
# without any user input?
UNATTENTED_INSTALL=true

# General settings
# Leave empty, if you wish that the user will be asked about this.
#NEXTCLOUD_SERVER_FQDN="nextcloud-server.example.invalid"
# Leave empty, if you wish that the user will be asked about this.
#SERVER_FQDN="nextcloud-hpb.example.invalid"

# Leave empty, if you wish that the user will be asked about this.
SSL_CERT_PATH="/etc/ssl/certs/nextcloud-hpb.crt"
# Leave empty, if you wish that the user will be asked about this.
SSL_CERT_KEY_PATH="/etc/ssl/private/nextcloud-hpb.key"

# Collabora (Gets asked anyway, except unattended install.)
SHOULD_INSTALL_COLLABORA=true

# Signaling (Gets asked anyway, except unattended install.)
SHOULD_INSTALL_SIGNALING=true

# Nginx (Gets asked anyway, except unattended install.)
SHOULD_INSTALL_NGINX=true

# Logfile get created if UNATTENTED_INSTALL is true.
# Leave empty, if you wish that the user will be asked about this.
LOGFILE_PATH="./setup-nextcloud-hpb-$(date +%Y-%m-%dT%H:%M:%SZ).log"

# Configuration gets copied and prepared here before copying them into place.
# This prevents config being broken if something goes wrong.
# Leave empty, if you wish that the user will be asked about this.
TMP_DIR_PATH="./tmp"

# Secrets, passwords and configuration gets saved in this file.
# Leave empty, if you wish that the user will be asked about this.
SECRETS_FILE_PATH=""
