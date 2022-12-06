#!/bin/bash

# Collabora Online server
# https://github.com/CollaboraOnline/online
# https://www.collaboraoffice.com/code/linux-packages/

COLLABORA_KEYRING_URL="https://collaboraoffice.com/downloads/gpg/collaboraonline-release-keyring.gpg"
COLLABORA_KEYRING_DIR="/usr/share/keyrings"
COLLABORA_KEYRING_FILE="$COLLABORA_KEYRING_DIR/collaboraonline-release-keyring.gpg"

COLLABORA_SOURCES_FILE="/etc/apt/sources.list.d/collaboraonline.sources"

function install_collabora() {
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
	log "\nStep 1: Import the signing key"

	cd $COLLABORA_KEYRING_DIR
	is_dry_run || wget "$COLLABORA_KEYRING_URL" || exit 1
	cd -
}

function collabora_step2() {
	# 2. Add CODE package repositories
	log "\nStep 2: Add CODE package repositories"

	collabora_debian_major_version=$DEBIAN_MAJOR_VERSION
	# Collabora doesn't have a repo for bookworm yet.
	# FIXME: Remove this hack if Debian Bookworm is released! (or update to Debian 13…)
	if [ "$collabora_debian_major_version" = "12" ]; then
		collabora_debian_major_version="11"
	fi
	COLLABORA_REPO_URL="https://www.collaboraoffice.com/repos/CollaboraOnline/CODE-debian$collabora_debian_major_version"

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
	log "\nStep 3: Install packages"

	# Installing:
	#   - coolwsd
	#   - code-brand
	#   - some dictionaries, German, English, French, Spanish, Dutch
	#   - Microsoft fonts.
	if ! is_dry_run; then
		if [ "$UNATTENDED_INSTALL" == true ]; then
			log "Trying unattended install for Collabora."
			export DEBIAN_FRONTEND=noninteractive
			args_apt="-qqy"
		else
			args_apt="-y"
		fi

		apt-get install "$args_apt" \
			software-properties-common \
			2>&1 | tee -a $LOGFILE_PATH

		apt-add-repository contrib \
			2>&1 | tee -a $LOGFILE_PATH

		is_dry_run || apt update 2>&1 | tee -a $LOGFILE_PATH

		apt-get install "$args_apt" \
			ttf-mscorefonts-installer \
			2>&1 | tee -a $LOGFILE_PATH

		apt-get install "$args_apt" \
			coolwsd code-brand collaboraoffice-dict-en \
			collaboraofficebasis-de collaboraoffice-dict-de \
			collaboraofficebasis-fr collaboraoffice-dict-fr \
			collaboraofficebasis-nl collaboraoffice-dict-nl \
			collaboraofficebasis-es collaboraoffice-dict-es \
			2>&1 | tee -a $LOGFILE_PATH
	fi
}

function collabora_step4() {
	# 4. Prepare configuration
	log "\nStep 4: Prepare configuration"

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
		IFS= read -r -d '' COLLABORA_REMOTE_CONFIGS <<EOF || true
				<url desc="URL of optional JSON file that lists fonts to be included in Online" type="string" default="">https://$NC_SERVER/apps/richdocuments/settings/fonts.json</url>
EOF

		# Escape newlines for sed later on.
		COLLABORA_REMOTE_CONFIGS=$(echo "$COLLABORA_REMOTE_CONFIGS" | sed -z 's|\n|\\n|g')
		COLLABORA_REMOTE_CONFIGS+=("$COLLABORA_REMOTE_CONFIGS")
	done

	IFS= # Avoid whitespace between definitions.
	log "Replacing '<COLLABORA_REMOTE_CONFIGS>' with:\n${COLLABORA_REMOTE_CONFIGS[*]}"
	sed -ri "s|<COLLABORA_REMOTE_CONFIGS>|${COLLABORA_REMOTE_CONFIGS[*]}|g" "$TMP_DIR_PATH"/collabora/*
	unset IFS
}

function collabora_step5() {
	# 5. Deploy configuration
	log "\nStep 5: Deploy configuration"

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
		"account.\n$(printf '\t- https://%s\n' "${NEXTCLOUD_SERVER_FQDNS[@]}")" \
		"\nThen install the Nextcloud Office app and navigate to" \
		"\nSettings -> Administration -> Nextcloud Office." \
		"\nNow select 'Use your own server' and type in '$collabora_address'." \
		"\nPlease note that you need to have a working HTTPS setup on your" \
		"\nNextcloud server in order to get Nextcloud Office working."
}
