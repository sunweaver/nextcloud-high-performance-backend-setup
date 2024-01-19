#!/bin/bash

set -eo pipefail

# Sane defaults (Don't override these settings here!)
# Can be overridden by specifying a settings file as first parameter.
# See settings.sh
DRY_RUN=false
UNATTENDED_INSTALL=false
NEXTCLOUD_SERVER_FQDNS=""  # Ask user
SERVER_FQDN=""             # Ask user
SSL_CERT_PATH_RSA=""       # Will be auto filled, if not overriden by settings file.
SSL_CERT_KEY_PATH_RSA=""   # Will be auto filled, if not overriden by settings file.
SSL_CHAIN_PATH_RSA=""      # Will be auto filled, if not overriden by settings file.
SSL_CERT_PATH_ECDSA=""     # Will be auto filled, if not overriden by settings file.
SSL_CERT_KEY_PATH_ECDSA="" # Will be auto filled, if not overriden by settings file.
SSL_CHAIN_PATH_ECDSA=""    # Will be auto filled, if not overriden by settings file.
DHPARAM_PATH=""            # Will be auto filled, if not overriden by settings file.
LOGFILE_PATH="setup-nextcloud-hpb-$(date +%Y-%m-%dT%H:%M:%SZ).log"
TMP_DIR_PATH="./tmp"
SECRETS_FILE_PATH=""   # Ask user
EMAIL_USER_ADDRESS=""  # Ask user
EMAIL_USER_PASSWORD="" # Ask user
EMAIL_USER_USERNAME="" # Ask user
EMAIL_SERVER_HOST=""   # Ask user
EMAIL_SERVER_PORT=""   # Ask user
DISABLE_SSH_SERVER=false
SIGNALING_BUILD_FROM_SOURCES="" # Ask user
DEBIAN_VERSION_ATLEAST="11"

SETUP_VERSION=$(cat VERSION | head -n 1 | tr '\n' ' ')

function show_dialogs() {
	if [ "$LOGFILE_PATH" = "" ]; then
		if [ "$UNATTENDED_INSTALL" = true ]; then
			log "Can't continue since this is a non-interactive installation and I'm" \
				"missing LOGFILE_PATH!"
			exit 1
		fi

		LOGFILE_PATH=$(
			whiptail --title "Logfile path" \
				--inputbox "Please enter a path to which this script can write $(
				)a log file.\n\nThe log directory and its parent directories will get $(
				)created automatically if they don't yet exist." 10 65 \
				"setup-nextcloud-hpb-$(date +%Y-%m-%dT%H:%M:%SZ).log" \
				3>&1 1>&2 2>&3
		)
	fi
	log "Using '$LOGFILE_PATH' for LOGFILE_PATH"

	if [ "$DRY_RUN" = "" ]; then
		if [ "$UNATTENDED_INSTALL" = true ]; then
			log "Can't continue since this is a non-interactive installation and I'm missing DRY_RUN!"
			exit 1
		fi

		if whiptail --title "Dry-Run Mode" --yesno "Do you want to run in dry $(
		)mode? This will ensure that no serious changes will get applied to your $(
		)system." 10 65 --defaultno; then
			DRY_RUN=true
		else
			DRY_RUN=true
		fi
	fi
	log "Using '$DRY_RUN' for DRY_RUN".

	if [ "$NEXTCLOUD_SERVER_FQDNS" = "" ]; then
		if [ "$UNATTENDED_INSTALL" = true ]; then
			log "Can't continue since this is a non-interactive installation and I'm" \
				"missing NEXTCLOUD_SERVER_FQDNS!"
			exit 1
		fi

		NEXTCLOUD_SERVER_FQDNS=$(
			whiptail --title "Nextcloud Server Domain" \
				--inputbox "Please enter your Nextcloud server's domain name here. $(
				)(Omit http(s)://, just put in the plain domain name!).\n\n$(
				)You can also specify multiple Nextcloud servers by separating $(
				)them using a comma." 12 65 \
				"nextcloud.example.org" 3>&1 1>&2 2>&3
		)
	fi
	# Filter out HTTPS:// or HTTP://
	NEXTCLOUD_SERVER_FQDNS=$(echo $NEXTCLOUD_SERVER_FQDNS | sed -r "s#https?\:\/\/##gi")
	log "Using '$NEXTCLOUD_SERVER_FQDNS' for NEXTCLOUD_SERVER_FQDNS".

	if [ "$SERVER_FQDN" = "" ]; then
		if [ "$UNATTENDED_INSTALL" = true ]; then
			log "Can't continue since this is a non-interactive installation and I'm" \
				"missing SERVER_FQDN!"
			exit 1
		fi

		SERVER_FQDN=$(
			whiptail --title "High-Performance Backend Server Domain" \
				--inputbox "Please enter your high performance backend $(
				)server's domain name here. (Omit http(s)://!).\n\n$(
				)Also please note that this domain should already exist in DNS $(
				)or else SSL certificate creation will fail!" \
				12 65 "nc-workhorse.example.org" 3>&1 1>&2 2>&3
		)
	fi
	# Filter out HTTPS:// or HTTP://
	SERVER_FQDN=$(echo $SERVER_FQDN | sed -r "s#https?\:\/\/##gi")
	log "Using '$SERVER_FQDN' for SERVER_FQDN".

	# - SSL Cert stuff below -
	if [ "$DHPARAM_PATH" = "" ]; then
		DHPARAM_PATH="/etc/certs/dhp/dhp.pem"
		log "Using default path '$DHPARAM_PATH' for DHPARAM_PATH".
	else
		log "Using '$DHPARAM_PATH' for DHPARAM_PATH".
	fi

	if [ "$SSL_CERT_PATH_RSA" = "" ]; then
		SSL_CERT_PATH_RSA="/etc/letsencrypt/live/$SERVER_FQDN-rsa/fullchain.pem"
		log "Using default path '$SSL_CERT_PATH_RSA' for SSL_CERT_PATH_RSA".
	else
		log "Using '$SSL_CERT_PATH_RSA' for SSL_CERT_PATH_RSA".
	fi

	if [ "$SSL_CERT_PATH_ECDSA" = "" ]; then
		SSL_CERT_PATH_ECDSA="/etc/letsencrypt/live/$SERVER_FQDN-ecdsa/fullchain.pem"
		log "Using default path '$SSL_CERT_PATH_ECDSA' for SSL_CERT_PATH_ECDSA".
	else
		log "Using '$SSL_CERT_PATH_ECDSA' for SSL_CERT_PATH_ECDSA".
	fi

	if [ "$SSL_CERT_KEY_PATH_RSA" = "" ]; then
		SSL_CERT_KEY_PATH_RSA="/etc/letsencrypt/live/$SERVER_FQDN-rsa/privkey.pem"
		log "Using default path '$SSL_CERT_KEY_PATH_RSA' for SSL_CERT_KEY_PATH_RSA".
	else
		log "Using '$SSL_CERT_KEY_PATH_RSA' for SSL_CERT_KEY_PATH_RSA".
	fi

	if [ "$SSL_CERT_KEY_PATH_ECDSA" = "" ]; then
		SSL_CERT_KEY_PATH_ECDSA="/etc/letsencrypt/live/$SERVER_FQDN-ecdsa/privkey.pem"
		log "Using default path '$SSL_CERT_KEY_PATH_ECDSA' for SSL_CERT_KEY_PATH_ECDSA".
	else
		log "Using '$SSL_CERT_KEY_PATH_ECDSA' for SSL_CERT_KEY_PATH_ECDSA".
	fi
	# -----

	if [ "$SSL_CHAIN_PATH_RSA" = "" ]; then
		SSL_CHAIN_PATH_RSA="/etc/letsencrypt/live/$SERVER_FQDN-rsa/chain.pem"
		log "Using default path '$SSL_CHAIN_PATH_RSA' for SSL_CHAIN_PATH_RSA".
	else
		log "Using '$SSL_CHAIN_PATH_RSA' for SSL_CHAIN_PATH_RSA".
	fi

	if [ "$SSL_CHAIN_PATH_ECDSA" = "" ]; then
		SSL_CHAIN_PATH_ECDSA="/etc/letsencrypt/live/$SERVER_FQDN-ecdsa/chain.pem"
		log "Using default path '$SSL_CHAIN_PATH_ECDSA' for SSL_CHAIN_PATH_ECDSA".
	else
		log "Using '$SSL_CHAIN_PATH_ECDSA' for SSL_CHAIN_PATH_ECDSA".
	fi

	if [ "$TMP_DIR_PATH" = "" ]; then
		if [ "$UNATTENDED_INSTALL" = true ]; then
			log "Can't continue since this is a non-interactive installation and I'm" \
				"missing TMP_DIR_PATH!"
			exit 1
		fi

		TMP_DIR_PATH=$(
			whiptail --title "Temporary directory for configuration" \
				--inputbox "Please enter a directory path in which this "$(
				)"script can put temporary configuration files.\n\n"$(
				)"The directory and its parents will get created automatically." \
				10 65 "./tmp" 3>&1 1>&2 2>&3
		)
	fi
	log "Using '$TMP_DIR_PATH' for TMP_DIR_PATH".

	if [ "$SECRETS_FILE_PATH" = "" ]; then
		if [ "$UNATTENDED_INSTALL" = true ]; then
			log "Can't continue since this is a non-interactive installation and I'm" \
				"missing SECRETS_FILE_PATH!"
			exit 1
		fi

		SECRETS_FILE_PATH=$(
			whiptail --title "Secrets, passwords and configuration file" \
				--inputbox "Please enter a path to a file where all "$(
				)"secrets, passwords and configuration shall be stored.\n\n"$(
				)"The directory and its parents get created automatically." \
				10 65 "./nextcloud-hpb.secrets" 3>&1 1>&2 2>&3
		)
	fi
	log "Using '$SECRETS_FILE_PATH' for SECRETS_FILE_PATH".

	# - E-Mail stuff below -
	if [ "$EMAIL_USER_ADDRESS" = "" ]; then
		if [ "$UNATTENDED_INSTALL" = true ]; then
			log "Can't continue since this is a non-interactive installation and I'm" \
				"missing EMAIL_USER_ADDRESS!"
			exit 1
		fi

		EMAIL_USER_ADDRESS=$(
			whiptail --title "E-Mail address" \
				--inputbox "Enter a valid email address which will be used for $(
				)notifications.$(
				)Please note that this email must be yours and you can send $(
				)emails with it using a SMTP server. If in doubt ask your $(
				)email provider for SMTP server settings and credentials." \
				10 65 "johndoe@example.com" 3>&1 1>&2 2>&3
		)
	fi
	log "Using '$EMAIL_USER_ADDRESS' for EMAIL_USER_ADDRESS".

	if [ "$EMAIL_USER_PASSWORD" = "" ]; then
		if [ "$UNATTENDED_INSTALL" = true ]; then
			log "Can't continue since this is a non-interactive installation and I'm" \
				"missing EMAIL_USER_PASSWORD!"
			exit 1
		fi

		EMAIL_USER_PASSWORD=$(
			whiptail --title "E-Mail SMTP password" \
				--inputbox "Enter the password which msmtp will use to $(
				)authenticate against the SMTP server." \
				10 65 "" 3>&1 1>&2 2>&3
		)
	fi
	log "Using '$EMAIL_USER_PASSWORD' for EMAIL_USER_PASSWORD".

	if [ "$EMAIL_USER_USERNAME" = "" ]; then
		if [ "$UNATTENDED_INSTALL" = true ]; then
			log "Can't continue since this is a non-interactive installation and I'm" \
				"missing EMAIL_USER_USERNAME!"
			exit 1
		fi

		EMAIL_USER_USERNAME=$(
			whiptail --title "E-Mail SMTP username" \
				--inputbox "Enter the username which msmtp will use to $(
				)authenticate against the SMTP server.$(
				)Often the username is equal to the email address." \
				10 65 "$EMAIL_USER_ADDRESS" 3>&1 1>&2 2>&3
		)
	fi
	log "Using '$EMAIL_USER_USERNAME' for EMAIL_USER_USERNAME".

	if [ "$EMAIL_SERVER_HOST" = "" ]; then
		if [ "$UNATTENDED_INSTALL" = true ]; then
			log "Can't continue since this is a non-interactive installation and I'm" \
				"missing EMAIL_SERVER_HOST!"
			exit 1
		fi

		EMAIL_SERVER_HOST=$(
			whiptail --title "E-Mail SMTP host" \
				--inputbox "Enter the host address on which the SMTP server is reachable." \
				10 65 "mail.example.org" 3>&1 1>&2 2>&3
		)
	fi
	log "Using '$EMAIL_SERVER_HOST' for EMAIL_SERVER_HOST".

	if [ "$EMAIL_SERVER_PORT" = "" ]; then
		if [ "$UNATTENDED_INSTALL" = true ]; then
			log "Can't continue since this is a non-interactive installation and I'm" \
				"missing EMAIL_SERVER_PORT!"
			exit 1
		fi

		EMAIL_SERVER_PORT=$(
			whiptail --title "E-Mail SMTP port" \
				--inputbox "Enter the port on which the SMTP server is reachable." \
				10 65 "587" 3>&1 1>&2 2>&3
		)
	fi
	log "Using '$EMAIL_SERVER_PORT' for EMAIL_SERVER_PORT".
	# -----

	CERTBOT_AGREE_TOS=""
	LETSENCRYPT_TOS_URL="https://letsencrypt.org/documents/LE-SA-v1.2-November-15-2017.pdf"
	if [ "$UNATTENDED_INSTALL" != true ]; then
		if whiptail --title "Letsencrypt - Terms of Service" \
			--yesno "Do you want to silently accept Letsencrypt's Terms of $(
			)Service here? If you select 'no' here, the Terms of Service $(
			)will be displayed during SSL certificate retrieval during the $(
			)installation process.\n\nYou can always read Letsencrypt's $(
			)Terms of Service here:\n$LETSENCRYPT_TOS_URL" \
			13 75 3>&1 1>&2 2>&3; then
			CERTBOT_AGREE_TOS="--agree-tos"
		fi
	fi
	log "Using '$CERTBOT_AGREE_TOS' for CERTBOT_AGREE_TOS."

	if [ "$DISABLE_SSH_SERVER" != true ]; then
		if [ "$UNATTENDED_INSTALL" != true ]; then
			if whiptail --title "Deactivate SSH server?" --defaultno \
				--yesno "Should the 'ssh' service be disabled?" \
				10 70 3>&1 1>&2 2>&3; then
				DISABLE_SSH_SERVER=true
			fi
		fi
	fi
	log "Using '$DISABLE_SSH_SERVER' for DISABLE_SSH_SERVER."

	if [ "$UNATTENDED_INSTALL" != true ] && [ "$SHOULD_INSTALL_SIGNALING" = true ]; then
		if [ "$SIGNALING_PACKAGES_AVAILABLE" = true ]; then
			if [ "$DEBIAN_VERSION_MAJOR" = "11" ]; then
				whiptail --title "Build from sources." --defaultno \
				    --msgbox "The packages 'nextcloud-spreed-signaling' and $(
				    )'nats-server' in Debian 11 are rather old and buggy. Also the $(
				    )Debian 11 version of 'coturn' does have some crashing issues. To $(
				    )avoid these problems the packages will be built and installed $(
				    )from sources." \
				    13 65 3>&1 1>&2 2>&3
				SIGNALING_BUILD_FROM_SOURCES=true
			else
				# A working version of nextcloud-spreed-signaling is available since
				# Debian 12 (backports) and Debian 13 (provided first in Debian testing
				# on 2023-10-22) and newer
				if whiptail --title "Build from sources?" --defaultno \
					--yesno "The package 'nextcloud-spreed-signaling' $(
					)is relatively new in Debian and therefore currently $(
					)only available in Debian testing. Do you $(
					)wish to build and install the package from sources?" \
					13 65 3>&1 1>&2 2>&3; then
					SIGNALING_BUILD_FROM_SOURCES=true
				fi
			fi
		else
			# Originally, this part was for running this script on Debian 10 which is not
			# supported anymore.
			#
			# Nowadays, most probable reason for landing here is if people try this script
			# on Debian testing and one of the required packages has been removed from
			# testing due to release critical bugs.
			whiptail --title "Build from sources?" \
				--msgbox "The packages 'nextcloud-spreed-signaling' and $(
				)'nats-server' are not available in the package archive. The $(
				)packages will get built and installed from sources." 13 65
			SIGNALING_BUILD_FROM_SOURCES=true
		fi
	fi
	log "Using '$SIGNALING_BUILD_FROM_SOURCES' for SIGNALING_BUILD_FROM_SOURCES".
}

function log() {
	echo -e "$@" 2>&1 | tee -a $LOGFILE_PATH
}

function generate_dhparam_file() {
	if [ "$BUILT_DHPARAM_FILE" == "true" ]; then
		# Skip if we already generated dhparam file.
		return 0
	fi

	if [ -s "$DHPARAM_PATH" ]; then
		# Rebuilding dhparam file.
		log "Removing old dhparam file at '$DHPARAM_PATH'."
		rm -fv "$DHPARAM_PATH" 2>&1 | tee -a "$LOGFILE_PATH"
	fi

	log "Generating new dhparam file…"
	is_dry_run || mkdir -p "$(dirname $DHPARAM_PATH)"
	is_dry_run || touch "$DHPARAM_PATH"
	is_dry_run || openssl dhparam -dsaparam -out "$DHPARAM_PATH" 4096
	is_dry_run || chmod 644 "$DHPARAM_PATH"

	BUILT_DHPARAM_FILE="true"
}

# Deploys target_file_path to source_file_path while respecting
# potential custom user config.
# param 1: source_file_path
# param 2: target_file_path
# returns: 1 if already deployed and 0 if not.
function deploy_file() {
	source_file_path="$1"
	target_file_path="$2"
	log "Deploying $target_file_path"
	if [[ -s "$target_file_path" ]]; then
		checksum_deployed=$(sha256sum "$target_file_path" | cut -d " " -f1)
		checksum_expected=$(sha256sum "$source_file_path" | cut -d " " -f1)
		if [ "${checksum_deployed}" = "${checksum_expected}" ]; then
			log "$target_file_path was already deployed."
			return 1
		else
			if [ "$UNATTENDED_INSTALL" = true ]; then
				cp "$source_file_path" "$target_file_path"
			else
				log "file '$target_file_path' exists and will be updated deployed."
				is_dry_run || cp "$source_file_path" "$target_file_path"
			fi
		fi
	else
		# Target file is empty or doesn't exist.
		is_dry_run || cp "$source_file_path" "$target_file_path"
	fi
	return 0
}

function check_root_perm() {
	if [[ $(id -u) -ne 0 ]]; then
		log "Please run the this (setup-nextcloud-hpb) script as root."
		exit 1
	fi
}

function check_debian_system() {
	# File exists and not empty
	if ! [ -s /etc/os-release ]; then
		log "Couldn't read /etc/os-release! What kind of OS is this?"
		exit 1
	else
		source /etc/os-release
		if [ "$ID" != "debian" ]; then
			log "This host does not run Debian. Wrong distribution!"
			exit 1
		fi
		if [ -z "$VERSION_ID" ] && [[ "$VERSION_CODENAME" =~ "sid" ]]; then
			# /etc/os-release lacks VERSION_ID in testing/unstable, so assume
			# a not-yet-released version of Debian
			VERSION_ID=999
		fi
		if dpkg --compare-versions $VERSION_ID lt $DEBIAN_VERSION_ATLEAST; then
			log "Debian version '$VERSION_ID' not supported (too old)!"
			exit 1
		fi

		DEBIAN_MAJOR_VERSION=$VERSION_ID
	fi
}

function check_available_signaling_packages() {
	log "Checking for packages availability…"

	if apt-cache show nextcloud-spreed-signaling >/dev/null; then
		log "Package 'nextcloud-spreed-signaling' is available."
	else
		log "Package 'nextcloud-spreed-signaling' is NOT available."
		return 1
	fi

	if apt-cache show nats-server >/dev/null; then
		log "Package 'nats-server' is available."
	else
		log "Package 'nats-server' is NOT available."
		return 1
	fi

	if apt-cache show coturn >/dev/null; then
		log "Package 'coturn' is available."
	else
		log "Package 'coturn' is NOT available."
		return 1
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
	log "Nextcloud HPB setup script version: $SETUP_VERSION"

	check_root_perm

	# Make sure PATH is correctly set.
	# There are VPS providers which alter the PATH env variable.
	export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

	check_debian_system

	# We need to test if nextcloud-signaling-spreed, coturn, nats-server and
	# janus are available in the apt sources configured on this system in order
	# to pre-select the right answer in the dialog later on.
	if check_available_signaling_packages; then
		SIGNALING_PACKAGES_AVAILABLE=true
	else
		SIGNALING_PACKAGES_AVAILABLE=false
	fi

	# Load Settings (hopefully vars above get overwritten!)
	SETTINGS_FILE="$1"
	if [ -s "$SETTINGS_FILE" ]; then
		log "Loading settings file '$SETTINGS_FILE'…"
		source "$SETTINGS_FILE"
	else
		log "No settings file specified using defaults or asking user for input."
	fi

	### INSTALL DEPENDENCIES
	# Check 'whiptail' dependency
	if ! command -v whiptail &>/dev/null; then
		log "whiptail could not be found! Trying to install it…"
		if ! is_dry_run; then
			if [ "$UNATTENDED_INSTALL" == true ]; then
				log "Trying unattended install for 'whiptail'."
				export DEBIAN_FRONTEND=noninteractive
				args_apt="-qqy"
			else
				args_apt="-y"
			fi

			apt-get install "$args_apt" whiptail 2>&1 | tee -a $LOGFILE_PATH
		fi
	fi

	# Check 'wget' dependency
	if ! command -v wget &>/dev/null; then
		log "wget could not be found! Trying to install it…"
		if ! is_dry_run; then
			if [ "$UNATTENDED_INSTALL" == true ]; then
				log "Trying unattended install for 'wget'."
				export DEBIAN_FRONTEND=noninteractive
				args_apt="-qqy"
			else
				args_apt="-y"
			fi

			apt-get install "$args_apt" wget 2>&1 | tee -a $LOGFILE_PATH
		fi
	fi
	###

	# Let's check if we should open dialogs.
	if [ "$UNATTENDED_INSTALL" != true ]; then
		# Override settings file!
		SHOULD_INSTALL_UFW=false
		SHOULD_INSTALL_COLLABORA=false
		SHOULD_INSTALL_SIGNALING=false
		SHOULD_INSTALL_CERTBOT=false
		SHOULD_INSTALL_NGINX=false
		SHOULD_INSTALL_UNATTENDEDUPGRADES=false
		SHOULD_INSTALL_MSMTP=false

		CHOICES=$(whiptail --title "Select services" --separate-output \
			--checklist "Use the space bar key to select/deselect the services $(
			)you want to install.\n\nThe following services/packages will also be $(
			)installed: Certbot Nginx ssl-cert ufw unattended-upgrades" 15 90 2 \
			"1" "Install Collabora (coolwsd, code-brand)" ON \
			"2" "Install Signaling (nats-server, coturn, janus, nextcloud-spreed-signaling)" ON \
			3>&1 1>&2 2>&3 || true)

		if [ -z "$CHOICES" ]; then
			log "No service was selected (user hit Cancel or unselected all options) Exiting…"
			exit 0
		else
			for CHOICE in $CHOICES; do
				case "$CHOICE" in
				"1")
					log "Collabora (certbot, nginx, ufw) will be installed."
					SHOULD_INSTALL_UFW=true
					SHOULD_INSTALL_COLLABORA=true
					SHOULD_INSTALL_NGINX=true
					SHOULD_INSTALL_CERTBOT=true
					SHOULD_INSTALL_UNATTENDEDUPGRADES=true
					SHOULD_INSTALL_MSMTP=true
					;;
				"2")
					log "Signaling (certbot, nginx, ufw) will be installed."
					SHOULD_INSTALL_UFW=true
					SHOULD_INSTALL_SIGNALING=true
					SHOULD_INSTALL_NGINX=true
					SHOULD_INSTALL_CERTBOT=true
					SHOULD_INSTALL_UNATTENDEDUPGRADES=true
					SHOULD_INSTALL_MSMTP=true
					;;
				*)
					log "Unsupported service $CHOICE!" >&2
					exit 1
					;;
				esac
			done
		fi
	fi

	show_dialogs

	# Transform Nextcloud server URLs into array.
	# Change comma (,) to whitespace
	NEXTCLOUD_SERVER_FQDNS=($(echo "$NEXTCLOUD_SERVER_FQDNS" | tr ',' ' '))
	log "Splitting Nextcloud server domains into:"
	log "$(printf '\t- %s\n' "${NEXTCLOUD_SERVER_FQDNS[@]}")"

	if [ -s "$LOGFILE_PATH" ]; then
		rm -v $LOGFILE_PATH |& tee -a $LOGFILE_PATH
	fi

	log "$(date)"

	is_dry_run &&
		log "Running in dry-mode. This script won't actually do anything on" \
			"your system!"

	if [ "$UNATTENDED_INSTALL" = true ]; then
		log "Trying unattented installation."
	fi

	if ! [ -e "$TMP_DIR_PATH" ]; then
		log "Creating '$TMP_DIR_PATH'."
		mkdir -p "$TMP_DIR_PATH" 2>&1 | tee -a $LOGFILE_PATH
	else
		log "Deleted contents of '$TMP_DIR_PATH'."
		rm -vr "$TMP_DIR_PATH"/* 2>&1 | tee -a $LOGFILE_PATH || true
	fi

	log "Moving config files into '$TMP_DIR_PATH'."
	cp -rv data/* "$TMP_DIR_PATH" 2>&1 | tee -a $LOGFILE_PATH

	log "Deleting every '127.0.1.1' entry in /etc/hosts."
	is_dry_run || sed -i "/127.0.1.1/d" /etc/hosts

	entry="127.0.1.1 $SERVER_FQDN $(hostname)"
	log "Deploying '$entry' in /etc/hosts."
	is_dry_run || echo "$entry" >>/etc/hosts

	scripts=('src/setup-ufw.sh' 'src/setup-collabora.sh'
		'src/setup-signaling.sh' 'src/setup-nginx.sh' 'src/setup-certbot.sh'
		'src/setup-unattendedupgrades.sh' 'src/setup-msmtp.sh')
	for script in "${scripts[@]}"; do
		log "Sourcing '$script'."
		source "$script"
	done

	if [ "$SHOULD_INSTALL_UFW" = true ]; then install_ufw; else
		log "Won't install UFW."
	fi
	if [ "$SHOULD_INSTALL_COLLABORA" = true ]; then install_collabora; else
		log "Won't install Collabora."
	fi
	if [ "$SHOULD_INSTALL_SIGNALING" = true ]; then install_signaling; else
		log "Won't install Signaling."
	fi
	if [ "$SHOULD_INSTALL_CERTBOT" = true ]; then install_certbot; else
		log "Won't install Certbot."
	fi
	if [ "$SHOULD_INSTALL_NGINX" = true ]; then install_nginx; else
		log "Won't install Nginx."
	fi
	if [ "$SHOULD_INSTALL_UNATTENDEDUPGRADES" = true ]; then install_unattendedupgrades; else
		log "Won't install unattended upgrades."
	fi
	if [ "$SHOULD_INSTALL_MSMTP" = true ]; then install_msmtp; else
		log "Won't install msmtp email setup."
	fi

	log "Every installation completed."

	if [ "DISABLE_SSH_SERVER" = true ]; then
		log "Disabling 'ssh' service…"
		is_dry_run || systemctl disable ssh
	fi

	log "Enabling and restarting services…"
	SERVICES_TO_ENABLE=()
	if [ "$SHOULD_INSTALL_UFW" = true ]; then
		SERVICES_TO_ENABLE+=("ufw")
	fi
	if [ "$SHOULD_INSTALL_COLLABORA" = true ]; then
		SERVICES_TO_ENABLE+=("coolwsd")
	fi
	if [ "$SHOULD_INSTALL_SIGNALING" = true ]; then
		SERVICES_TO_ENABLE+=("coturn" "nats-server" "nextcloud-spreed-signaling" "janus")
	fi
	#if [ "$SHOULD_INSTALL_CERTBOT" = true ]; then fi
	if [ "$SHOULD_INSTALL_NGINX" = true ]; then
		SERVICES_TO_ENABLE+=("nginx")
	fi
	#if [ "$SHOULD_INSTALL_UNATTENDEDUPGRADES" = true ]; then fi
	#if [ "$SHOULD_INSTALL_MSMTP" = true ]; then fi

	if ! is_dry_run; then
		for i in "${SERVICES_TO_ENABLE[@]}"; do
			log "Enabling and restarting service '$i'…"
			if ! systemctl unmask "$i" | tee -a $LOGFILE_PATH; then
				log "Something went wrong while unmasking service '$i'…"
			fi

			if ! service "$i" stop | tee -a $LOGFILE_PATH; then
				log "Something went wrong while stopping service '$i'…"
			fi

			if ! systemctl enable --now "$i" | tee -a $LOGFILE_PATH; then
				log "Something went wrong while enabling/starting service '$i'…"
			fi
			sleep 0.25s
		done
	fi

	log "======================================================================"
	# if [ "$SHOULD_INSTALL_UFW" = true ]; then
	# 	ufw_print_info
	# 	log "======================================================================"
	# fi
	if [ "$SHOULD_INSTALL_COLLABORA" = true ]; then
		collabora_print_info
		log "======================================================================"
	fi
	if [ "$SHOULD_INSTALL_SIGNALING" = true ]; then
		signaling_print_info
		log "======================================================================"
	fi
	if [ "$SHOULD_INSTALL_CERTBOT" = true ]; then
		certbot_print_info
		log "======================================================================"
	fi
	if [ "$SHOULD_INSTALL_NGINX" = true ]; then
		nginx_print_info
		log "======================================================================"
	fi
	# if [ "$SHOULD_INSTALL_UNATTENDEDUPGRADES" = true ]; then
	# 	unattendedupgrades_print_info
	#	log "======================================================================"
	# fi
	if [ "$SHOULD_INSTALL_MSMTP" = true ]; then
		msmtp_print_info
		log "======================================================================"
	fi

	is_dry_run || mkdir -p "$(dirname "$SECRETS_FILE_PATH")"
	is_dry_run || touch "$SECRETS_FILE_PATH"
	is_dry_run || chmod 0640 "$SECRETS_FILE_PATH"

	echo -e "This file contains secrets, passwords and configuration" \
		"generated by the Nextcloud High-Performance backend setup." \
		>$SECRETS_FILE_PATH
	# if [ "$SHOULD_INSTALL_UFW" = true ]; then
	# 	ufw_write_secrets_to_file "$SECRETS_FILE_PATH"
	# fi
	if [ "$SHOULD_INSTALL_COLLABORA" = true ]; then
		collabora_write_secrets_to_file "$SECRETS_FILE_PATH"
	fi
	if [ "$SHOULD_INSTALL_SIGNALING" = true ]; then
		signaling_write_secrets_to_file "$SECRETS_FILE_PATH"
	fi
	if [ "$SHOULD_INSTALL_CERTBOT" = true ]; then
		certbot_write_secrets_to_file "$SECRETS_FILE_PATH"
	fi
	if [ "$SHOULD_INSTALL_NGINX" = true ]; then
		nginx_write_secrets_to_file "$SECRETS_FILE_PATH"
	fi
	# if [ "$SHOULD_INSTALL_UNATTENDEDUPGRADES" = true ]; then
	# 	unattendedupgrades_write_secrets_to_file "$SECRETS_FILE_PATH"
	# fi
	if [ "$SHOULD_INSTALL_MSMTP" = true ]; then
		msmtp_write_secrets_to_file "$SECRETS_FILE_PATH"
	fi

	log "\nThank you for using this script.\n"
}

# Execute main function.
main "$1"

set +eo pipefail
