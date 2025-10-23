#!/bin/bash

# Collabora Online server
# https://github.com/CollaboraOnline/online
# https://www.collaboraoffice.com/code/linux-packages/

COLLABORA_KEYRING_URL="https://collaboraoffice.com/downloads/gpg/collaboraonline-release-keyring.gpg"
COLLABORA_KEYRING_DIR="/usr/share/keyrings"
COLLABORA_KEYRING_FILE="$COLLABORA_KEYRING_DIR/collaboraonline-release-keyring.gpg"

COLLABORA_SOURCES_FILE="/etc/apt/sources.list.d/collaboraonline.sources"

function install_collabora() {
	announce_installation "Installing Collabora"
	log "Installing Collabora…"

	collabora_step1
	collabora_step2
	collabora_step3
	collabora_step4
	collabora_step5

	log "Collabora install completed."
}

function collabora_step1() {
	# 1. Import the signing key
	log "\n${green}Step 1: Import the signing key"

	cd $COLLABORA_KEYRING_DIR
	is_dry_run || wget "$COLLABORA_KEYRING_URL" || exit 1
	cd -
}

function collabora_step2() {
	# 2. Add CODE package repositories
	log "\n${green}Step 2: Add CODE package repositories"

	COLLABORA_REPO_URL="https://www.collaboraoffice.com/repos/CollaboraOnline/CODE-deb"

	log "Installing Collabora APT-Repo URL: '$COLLABORA_REPO_URL'…"
	is_dry_run || cat <<EOF >$COLLABORA_SOURCES_FILE
Types: deb
URIs: $COLLABORA_REPO_URL
Suites: ./
Signed-By: $COLLABORA_KEYRING_FILE
EOF
}

function collabora_step3() {
	# 3. Install packages
	log "\n${green}Step 3: Install packages"

	# Installing:
	#   - coolwsd
	#   - code-brand
	#   - some dictionaries, German, English, French, Spanish, Dutch
	#   - Microsoft fonts (contrib)
	if [ "$UNATTENDED_INSTALL" == true ]; then
		log "Trying unattended install for Collabora."
		export DEBIAN_FRONTEND=noninteractive
		args_apt="-qqy"
	else
		args_apt="-y"
	fi

	# Make 'contrib' available. Needed to install 'ttf-mscorefonts-installer' for Collabora.
	#
	# BUG: software-properties has issues migrating from sid to testing for about a year currently.
	#      See https://github.com/sunweaver/nextcloud-high-performance-backend-setup/issues/190
	if ! apt-cache policy software-properties-common 2>/dev/null | grep "Candidate:" | grep -qv "(none)"; then
		is_dry_run || {
			# For deb822 sources (default in Debian 13)
			sed -i 's/^Components: main$/& contrib/' /etc/apt/sources.list.d/debian.sources || true

			# For the classic sources.list
			sed -r -i 's/^deb(.*main)$/deb\1 contrib/' /etc/apt/sources.list || true
		} 2>&1 | tee -a $LOGFILE_PATH
	else
		is_dry_run || {
			apt-get install "$args_apt" software-properties-common
			apt-add-repository -y contrib
		} 2>&1 | tee -a $LOGFILE_PATH
	fi

	# Update before trying to install from 'contrib'.
	is_dry_run || {
		apt update 2>&1 | tee -a $LOGFILE_PATH
	}

	# Install Microsoft Fonts.
	is_dry_run || {
		apt-get install "$args_apt" \
		ttf-mscorefonts-installer \
		2>&1 | tee -a $LOGFILE_PATH
	}

	# Install collabora packages.
	is_dry_run || {
		apt-get install "$args_apt" \
		coolwsd code-brand collaboraoffice-dict-en \
		collaboraofficebasis-de collaboraoffice-dict-de \
		collaboraofficebasis-fr collaboraoffice-dict-fr \
		collaboraofficebasis-nl collaboraoffice-dict-nl \
		collaboraofficebasis-es collaboraoffice-dict-es \
		2>&1 | tee -a $LOGFILE_PATH
	}
}

function collabora_step4() {
	# 4. Prepare configuration
	log "\n${green}Step 4: Prepare configuration"

	for NC_SERVER in "${NEXTCLOUD_SERVER_FQDNS[@]}"; do
		IFS= read -r -d '' COLLABORA_HOST_DEFINITION <<EOF || true
				<group>
					<host desc="hostname to allow or deny." allow="true">https://$NC_SERVER:443</host>
				</group>
EOF

		# Escape newlines for sed later on.
		COLLABORA_HOST_DEFINITION=$(echo "$COLLABORA_HOST_DEFINITION" | sed -z 's|\n|\\n|g')
		COLLABORA_HOST_DEFINITIONS+=("$COLLABORA_HOST_DEFINITION")
	done

	IFS= # Avoid whitespace between definitions.
	log "Replacing '<COLLABORA_HOST_DEFINITIONS>' with:\n${COLLABORA_HOST_DEFINITIONS[*]}"
	sed -ri "s|<COLLABORA_HOST_DEFINITIONS>|${COLLABORA_HOST_DEFINITIONS[*]}|g" "$TMP_DIR_PATH"/collabora/*
	unset IFS

	for NC_SERVER in "${NEXTCLOUD_SERVER_FQDNS[@]}"; do
		IFS= read -r -d '' COLLABORA_REMOTE_FONT_CONFIG <<EOF || true
				<url desc="URL of optional JSON file that lists fonts to be included in Online" type="string" default="">https://$NC_SERVER/apps/richdocuments/settings/fonts.json</url>
EOF

		# Escape newlines for sed later on.
		COLLABORA_REMOTE_FONT_CONFIG=$(echo "$COLLABORA_REMOTE_FONT_CONFIG" | sed -z 's|\n|\\n|g')
		COLLABORA_REMOTE_FONT_CONFIGS+=("$COLLABORA_REMOTE_FONT_CONFIG")
	done

	IFS= # Avoid whitespace between definitions.
	log "Replacing '<COLLABORA_REMOTE_FONT_CONFIGS>' with:\n${COLLABORA_REMOTE_FONT_CONFIGS[*]}"
	sed -ri "s|<COLLABORA_REMOTE_FONT_CONFIGS>|${COLLABORA_REMOTE_FONT_CONFIGS[*]}|g" "$TMP_DIR_PATH"/collabora/*
	unset IFS
}

function collabora_step5() {
	# 5. Deploy configuration
	log "\n${green}Step 5: Deploy configuration"

	deploy_file "$TMP_DIR_PATH"/collabora/snippet-coolwsd.conf /etc/nginx/snippets/coolwsd.conf || true
	deploy_file "$TMP_DIR_PATH"/collabora/coolwsd.xml /etc/coolwsd/coolwsd.xml || true
}

# arg: $1 is secret file path
function collabora_write_secrets_to_file() {
	if is_dry_run; then
		return 0
	fi

	conf_path="/etc/coolwsd/coolwsd.xml"
	echo -e "=== Collabora ===" >>$1
	echo -e "Coolwsd.xml configuration file: $conf_path" >>$1
}

function collabora_print_info() {
	collabora_address="https://$SERVER_FQDN/collabora"

	log "The Collabora Online service got installed. To set it up," \
		"\nlog into all of your Nextcloud instances with an adminstrator" \
		"account.\n$(for fqdn in "${NEXTCLOUD_SERVER_FQDNS[@]}"; do printf '\t- %shttps://%s%s\n' "${cyan}" "$fqdn" "${blue}"; done)" \
		"\n${blue}Then install the Nextcloud Office app and navigate to" \
		"\nSettings -> Administration -> Nextcloud Office." \
		"\nNow select 'Use your own server' and type in '${cyan}$collabora_address${blue}'." \
		"\nPlease note that you need to have a working HTTPS setup on your" \
		"\nNextcloud server in order to get Nextcloud Office working."
}
