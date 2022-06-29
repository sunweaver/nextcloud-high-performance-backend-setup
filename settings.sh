# !!! Be careful, this script will be executed by the root user. !!!

# Dry run (Don't actually alter anything on the system. (except in $TMP_DIR_PATH))
# Leave empty, if you wish that the user will be asked about this.
DRY_RUN=false

# Should the script try to install the high-performance-backend server
# without any user input?
UNATTENTED_INSTALL=true

# General settings
# Leave empty, if you wish that the user will be asked about this.
# You can also specify multiple Nextcloud servers by separating them with commas.
#NEXTCLOUD_SERVER_FQDNS="nextcloud.example.org"
# Leave empty, if you wish that the user will be asked about this.
#SERVER_FQDN="nc-workhorse.example.org"

# Leave empty, if you wish that the user will be asked about this.
SSL_CERT_PATH=""
# Leave empty, if you wish that the user will be asked about this.
SSL_CERT_KEY_PATH=""

# Collabora (Gets asked anyway, except unattended install.)
SHOULD_INSTALL_COLLABORA=true

# Signaling (Gets asked anyway, except unattended install.)
SHOULD_INSTALL_SIGNALING=true

SHOULD_INSTALL_NGINX=true
SHOULD_INSTALL_CERTBOT=true

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

# This email address gets passed on to Certbot which will send notifications
# if a certificate is about to run out.
# You can specify multiple addresses by stringing them together with a comma.
# Leave empty, if you wish that the user will be asked about this.
EMAIL_ADDRESS=""
