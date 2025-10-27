#!/bin/bash

# Signaling server
# https://github.com/strukturag/nextcloud-spreed-signaling

#SIGNALING_SUNWEAVER_SOURCE_FILE="/etc/apt/sources.list.d/sunweaver.list"

SIGNALING_BACKPORTS_SOURCE_FILE="/etc/apt/sources.list.d/debian-backports.list"

SIGNALING_TURN_STATIC_AUTH_SECRET="$(openssl rand -hex 32)"
SIGNALING_JANUS_API_KEY="$(openssl rand -base64 16)"
SIGNALING_HASH_KEY="$(openssl rand -hex 16)"
SIGNALING_BLOCK_KEY="$(openssl rand -hex 16)"

SIGNALING_COTURN_URL="$SERVER_FQDN"

COTURN_DIR="/etc/coturn"

declare -a SIGNALING_BACKENDS                   # Normal array
declare -a SIGNALING_BACKEND_DEFINITIONS        # Normal Array
declare -A SIGNALING_NC_SERVER_SECRETS          # Associative array
declare -A SIGNALING_NC_SERVER_SESSIONLIMIT     # Associative array
declare -A SIGNALING_NC_SERVER_MAXSTREAMBITRATE # Associative array
declare -A SIGNALING_NC_SERVER_MAXSCREENBITRATE # Associative array

function install_signaling() {
	announce_installation "Installing Signaling"
	log "Installing Signaling…"

	if [ "$DEBIAN_VERSION_MAJOR" = "12" ] ; then
		log "Enabling bookworm-backports..."
		is_dry_run || cat <<-EOL >$SIGNALING_BACKPORTS_SOURCE_FILE
			# Added by nextcloud-high-performance-backend setup-script.
			deb http://deb.debian.org/debian bookworm-backports main
		EOL
	fi
	if [ "$DEBIAN_VERSION_MAJOR" = "11" ]; then
		log "Enabling bullseye-backports..."
		is_dry_run || cat <<-EOL >$SIGNALING_BACKPORTS_SOURCE_FILE
			# Added by nextcloud-high-performance-backend setup-script.
			deb http://deb.debian.org/debian bullseye-backports main
		EOL
	fi
	is_dry_run || apt update 2>&1 | tee -a $LOGFILE_PATH

	APT_PARAMS="-y"
	if [ "$UNATTENDED_INSTALL" == true ]; then
		log "Trying unattended install for Signaling."
		export DEBIAN_FRONTEND=noninteractive
		APT_PARAMS="-qqy"
	fi

	if [ "$SIGNALING_BUILD_FROM_SOURCES" = true ]; then

		# Remove old packages.
		log "Purging old Signaling packages..."
		APT_PACKAGES="nextcloud-spreed-signaling janus"
		if [ "${DEBIAN_VERSION_MAJOR}" = "11" ]; then
			APT_PACKAGES="${APT_PACKAGES} nats-server coturn"
		fi

		for pkg in $APT_PACKAGES; do
			if is_dry_run; then
				log "Would purge package: $pkg now…"
				continue
			fi

			log "Purging package: $pkg"
			apt purge $APT_PARAMS "$pkg" 2>&1 | tee -a "$LOGFILE_PATH" || true
		done

		# Installing:
		#   - build-essential
		#   - curl
		#   - golang-go
		#   - make
		#   - protobuf-compiler
		#   - wget
		log "Installing Signaling build dependencies…"
		if [ "$DEBIAN_VERSION_MAJOR" = "11" ]; then
			is_dry_run || apt-get install $APT_PARAMS -t bullseye-backports golang-go 2>&1 | tee -a $LOGFILE_PATH
			is_dry_run || apt-get install $APT_PARAMS wget curl protobuf-compiler build-essential make 2>&1 | tee -a $LOGFILE_PATH
		elif [ "$DEBIAN_VERSION_MAJOR" = "12" ]; then
			is_dry_run || apt-get install $APT_PARAMS -t bookworm-backports golang-go 2>&1 | tee -a $LOGFILE_PATH
			is_dry_run || apt-get install $APT_PARAMS wget curl protobuf-compiler build-essential make 2>&1 | tee -a $LOGFILE_PATH
		else
			is_dry_run || apt-get install $APT_PARAMS wget curl protobuf-compiler build-essential make golang-go 2>&1 | tee -a $LOGFILE_PATH
		fi

		is_dry_run "Would have built nextcloud-spreed-signaling now…" || signaling_build_nextcloud-spreed-signaling

		# Only if Debian 11
		if [ "$DEBIAN_VERSION_MAJOR" = "11" ]; then
			is_dry_run "Would have built coturn now…" || signaling_build_coturn
			is_dry_run "Would have built nats-server now…" || signaling_build_nats-server
		fi

		# Check if Janus package is available, if not build it from sources
		JANUS_POLICY_OUTPUT="$(apt-cache policy janus 2>/dev/null)"
		if echo "$JANUS_POLICY_OUTPUT" | grep "Candidate:" | grep -q "(none)"; then
			log "Janus package not available, building from sources…"
			is_dry_run "Would have built janus now…" || signaling_build_janus
		else
			log "Janus package available, skipping build."
		fi

		# Installing:
		# - janus (if available, otherwise already built)
		# - ssl-cert
		# - nats-server (Always built from sources for Debian 11)
		# - coturn      (Always built from sources for Debian 11)
		if [ "$DEBIAN_VERSION_MAJOR" = "11" ]; then
			is_dry_run || apt-get install $APT_PARAMS ssl-cert 2>&1 | tee -a $LOGFILE_PATH
			is_dry_run || apt-get install $APT_PARAMS -t bullseye-backports janus 2>&1 | tee -a $LOGFILE_PATH
		else
			is_dry_run || apt-get install $APT_PARAMS ssl-cert nats-server coturn 2>&1 | tee -a $LOGFILE_PATH
			if ! apt-cache policy janus 2>/dev/null | grep "Candidate:" | grep -q "(none)"; then
				is_dry_run || apt-get install $APT_PARAMS janus 2>&1 | tee -a $LOGFILE_PATH
			fi
		fi

		log "Reloading systemd."
		systemctl daemon-reload | tee -a $LOGFILE_PATH
	else
		# Skipped because, we don't need sunweaver's packages anymore.
		# The packages arived in official Debian repositories.
		# TODO: This code should be removed soon IMHO.
		#signaling_step1
		#signaling_step2
		signaling_step3
	fi

	signaling_step4
	signaling_step5

	# Make sure janus is restartet 15 sec after system reboot, so that Coturn service has time to get up.
	# Otherwise, janus will silently crash if Coturn is not available.
	set +eo pipefail
	crontab -l >cron_backup
	echo "@reboot sleep 15 && systemctl restart janus > /dev/null 2>&1" >>cron_backup
	crontab cron_backup
	rm cron_backup
	set -eo pipefail

	log "Signaling install completed."
}

function signaling_build_janus() {
	log "[Building Janus] Building janus…"

	# Check if janus is already installed
	JANUS_BUILD_MARKER="/var/lib/nextcloud-hpb-setup/janus-built-version"

	log "[Building Janus] Fetching latest Janus version from Debian sources API…"
	JANUS_API_RESPONSE=$(curl -s "https://sources.debian.org/api/src/janus/")

	# Parse the JSON to get the latest version (first in the versions array)
	JANUS_VERSION=$(echo "$JANUS_API_RESPONSE" | grep -oP '"version":"[^"]*"' | head -n 1 | cut -d'"' -f4)
	log "[Building Janus] Latest Janus version: $JANUS_VERSION"

	if [ -z "$JANUS_VERSION" ]; then
		log_err "[Building Janus] ERROR: Could not determine Janus version from API!"
		exit 1
	fi

	# Check if already built with this version
	if [ -f "$JANUS_BUILD_MARKER" ] && [ "$(cat "$JANUS_BUILD_MARKER")" = "$JANUS_VERSION" ] && dpkg -l | grep -q "^ii.*janus"; then
		log "[Building Janus] Janus $JANUS_VERSION is already built and installed. Skipping build."
		return 0
	fi

	# Create temporary build directory
	JANUS_BUILD_DIR=$(mktemp -d)
	log "[Building Janus] Using temporary build directory: $JANUS_BUILD_DIR"

	# Store original directory
	ORIGINAL_DIR=$(pwd)

	log "[Building Janus] Installing necessary packages…"
	APT_PARAMS="-y"
	if [ "$UNATTENDED_INSTALL" == true ]; then
		export DEBIAN_FRONTEND=noninteractive
		APT_PARAMS="-qqy"
	fi
	is_dry_run || apt-get install $APT_PARAMS build-essential fakeroot devscripts equivs 2>&1 | tee -a $LOGFILE_PATH

	# Change to temporary build directory
	cd "$JANUS_BUILD_DIR"

	log "[Building Janus] Downloading Janus source package…"
	JANUS_DSC_URL="http://deb.debian.org/debian/pool/main/j/janus/janus_${JANUS_VERSION}.dsc"
	log "[Building Janus] DSC URL: $JANUS_DSC_URL"
	is_dry_run "Would've downloaded $JANUS_DSC_URL." || \
		dget --allow-unauthenticated "$JANUS_DSC_URL" 2>&1 | tee -a $LOGFILE_PATH

	# Extract base version without debian revision
	JANUS_BASE_VERSION=$(echo "$JANUS_VERSION" | cut -d'-' -f1)
	JANUS_SOURCE_DIR="janus-${JANUS_BASE_VERSION}"
	log "[Building Janus] Source directory: $JANUS_SOURCE_DIR"

	if [ ! -d "$JANUS_SOURCE_DIR" ]; then
		log_err "[Building Janus] ERROR: Source directory $JANUS_SOURCE_DIR not found!"
		exit 1
	fi

	log "[Building Janus] Installing build dependencies…"
	is_dry_run || (cd "$JANUS_SOURCE_DIR" && mk-build-deps -i -r -t "apt-get -y" 2>&1 | tee -a "$LOGFILE_PATH" && cd ..)

	log "[Building Janus] Building Janus…"
	is_dry_run || (cd "$JANUS_SOURCE_DIR" && debian/rules build 2>&1 | tee -a "$LOGFILE_PATH" && cd ..)

	log "[Building Janus] Creating Janus package…"
	is_dry_run || (cd "$JANUS_SOURCE_DIR" && debian/rules binary 2>&1 | tee -a "$LOGFILE_PATH" && cd ..)

	log "[Building Janus] Installing Janus package…"
	JANUS_DEB_FILE="janus_${JANUS_VERSION}_$(dpkg --print-architecture).deb"
	log "Package file: $JANUS_DEB_FILE"
	is_dry_run || dpkg -i "$JANUS_DEB_FILE" 2>&1 | tee -a $LOGFILE_PATH

	log "[Building Janus] Installing any missing dependencies…"
	is_dry_run || apt-get install $APT_PARAMS -f 2>&1 | tee -a $LOGFILE_PATH

	# Return to original directory
	cd "$ORIGINAL_DIR"

	# Clean up temporary build directory
	log "[Building Janus] Cleaning up temporary build directory…"
	rm -rf "$JANUS_BUILD_DIR"

	# Mark this version as built
	if ! is_dry_run; then
		mkdir -p "$(dirname "$JANUS_BUILD_MARKER")"
		echo "$JANUS_VERSION" > "$JANUS_BUILD_MARKER"
		log "[Building Janus] Marked version $JANUS_VERSION as built in $JANUS_BUILD_MARKER"
	fi
}

function signaling_build_nats-server() {
	log "[Building nats-server] Building nats-server…"

	# Check if nats-server is already installed
	NATS_BUILD_MARKER="/var/lib/nextcloud-hpb-setup/nats-server-built-version"

	LATEST_RELEASE="https://api.github.com/repos/nats-io/nats-server/releases/latest"
	log "[Building nats-server] Latest nats-server release URL: '$LATEST_RELEASE'"

	LATEST_RELEASE_TAG="$(curl -s "$LATEST_RELEASE" | grep 'tag_name' | cut -d\" -f4)"
	log "[Building nats-server] Latest nats-server version is: '$LATEST_RELEASE_TAG'"

	# Check if already built with this version
	if [ -f "$NATS_BUILD_MARKER" ] && [ "$(cat "$NATS_BUILD_MARKER")" = "$LATEST_RELEASE_TAG" ] && [ -x /usr/local/bin/nats-server ]; then
		log "[Building nats-server] nats-server $LATEST_RELEASE_TAG is already built and installed. Skipping build."
		return 0
	fi

	log "[Building nats-server] Removing old sources…"
	rm -v nats-server-v*-linux-*.tar.gz | tee -a $LOGFILE_PATH || true

	log "[Building nats-server] Downloading sources…"
	if [ "$(dpkg --print-architecture)" = "arm64" ]; then
		wget $(curl -s "$LATEST_RELEASE" | grep 'linux-arm64.tar.gz' |
			grep 'browser_download_url' | cut -d\" -f4) |
			tee -a $LOGFILE_PATH
	else
		wget $(curl -s "$LATEST_RELEASE" | grep 'linux-amd64.tar.gz' |
			grep 'browser_download_url' | cut -d\" -f4) |
			tee -a $LOGFILE_PATH
	fi

	log "[Building nats-server] Extracting sources…"
	tar -xvf "nats-server-$LATEST_RELEASE_TAG-linux-*.tar.gz" | tee -a $LOGFILE_PATH

	log "[Building nats-server] Copying binary into /usr/local/bin/nats-server…"
	cp --backup=numbered -v "nats-server-$LATEST_RELEASE_TAG-linux-*/nats-server" /usr/local/bin/nats-server | tee -a $LOGFILE_PATH

	deploy_file "$TMP_DIR_PATH"/signaling/nats-server.service /lib/systemd/system/nats-server.service || true
	deploy_file "$TMP_DIR_PATH"/signaling/nats-server.conf /etc/nats-server.conf || true

	log "[Building nats-server] Creating 'nats' system account…"
	adduser --system --group nats || true

	# Mark this version as built
	if ! is_dry_run; then
		mkdir -p "$(dirname "$NATS_BUILD_MARKER")"
		echo "$LATEST_RELEASE_TAG" > "$NATS_BUILD_MARKER"
		log "[Building nats-server] Marked version $LATEST_RELEASE_TAG as built in $NATS_BUILD_MARKER"
	fi
}

function signaling_build_coturn() {
	log "[Building coturn] Building coturn…"

	# Check if coturn is already installed
	COTURN_BUILD_MARKER="/var/lib/nextcloud-hpb-setup/coturn-built-version"
	COTURN_VERSION="master-$(date +%Y%m%d-%H%M%S)"  # Use timestamp-based version for master branch

	# Check if already built recently (within last hour) and binary exists
	if [ -f "$COTURN_BUILD_MARKER" ] && [ -x /usr/local/bin/turnserver ]; then
		BUILT_TIMESTAMP="$(cat "$COTURN_BUILD_MARKER")"
		BUILT_TIMESTAMP="${BUILT_TIMESTAMP#master-}"
		CURRENT_TIMESTAMP="$(date +%s)"
		BUILT_SECONDS="$(date -d "${BUILT_TIMESTAMP:0:8} ${BUILT_TIMESTAMP:9:2}:${BUILT_TIMESTAMP:11:2}:${BUILT_TIMESTAMP:13:2}" +%s 2>/dev/null || echo 0)"
		HOURS_DIFF=$(( ($CURRENT_TIMESTAMP - $BUILT_SECONDS) / 3600 ))

		if [ $HOURS_DIFF -lt 1 ]; then
			log "[Building coturn] coturn built less than 1 hour ago and is installed. Skipping build."
			return 0
		fi
	fi

	log "[Building coturn] Installing necessary packages…"
	APT_PARAMS="-y"
	if [ "$UNATTENDED_INSTALL" == true ]; then
		export DEBIAN_FRONTEND=noninteractive
		APT_PARAMS="-qqy"
	fi
	is_dry_run || apt-get install $APT_PARAMS cmake libssl-dev libevent-dev git 2>&1 | tee -a $LOGFILE_PATH

	log "[Building coturn] Downloading sources…"
	rm coturn-master.tar.gz | tee -a $LOGFILE_PATH || true
	wget https://github.com/coturn/coturn/archive/refs/heads/master.tar.gz -O coturn-master.tar.gz | tee -a $LOGFILE_PATH

	log "[Building coturn] Extracting sources…"
	tar -xvf coturn-master.tar.gz | tee -a $LOGFILE_PATH

	log "[Building coturn] Creating build directory…"
	mkdir coturn-master/build | tee -a $LOGFILE_PATH || true

	log "[Building coturn] Run configure script which will make a Makefile for this system…"
	cmake -S coturn-master -B coturn-master/build | tee -a $LOGFILE_PATH

	log "[Building coturn] Build & install coturn."
	cmake --build coturn-master/build --target install | tee -a $LOGFILE_PATH

	deploy_file "$TMP_DIR_PATH"/signaling/coturn.service /lib/systemd/system/coturn.service || true

	chmod 755 /usr/local/bin/turnserver

	log "[Building coturn] Creating 'turnserver' account"
	adduser --system --group --home /var/lib/turnserver turnserver || true

	# Mark this version as built
	if ! is_dry_run; then
		mkdir -p "$(dirname "$COTURN_BUILD_MARKER")"
		echo "$COTURN_VERSION" > "$COTURN_BUILD_MARKER"
		log "[Building coturn] Marked version $COTURN_VERSION as built in $COTURN_BUILD_MARKER"
	fi
}

function signaling_build_nextcloud-spreed-signaling() {
	log "[Building n-s-s] Building nextcloud-spreed-signaling…"

	# Check if nextcloud-spreed-signaling is already installed
	NSS_BUILD_MARKER="/var/lib/nextcloud-hpb-setup/nextcloud-spreed-signaling-built-version"
	NSS_VERSION="master-$(date +%Y%m%d-%H%M%S)"  # Use timestamp-based version for master branch

	# Check if already built recently (within last hour) and binary exists
	if [ -f "$NSS_BUILD_MARKER" ] && [ -x /usr/local/bin/nextcloud-spreed-signaling-server ]; then
		BUILT_TIMESTAMP="$(cat "$NSS_BUILD_MARKER")"
		BUILT_TIMESTAMP="${BUILT_TIMESTAMP#master-}"
		CURRENT_TIMESTAMP="$(date +%s)"
		BUILT_SECONDS="$(date -d "${BUILT_TIMESTAMP:0:8} ${BUILT_TIMESTAMP:9:2}:${BUILT_TIMESTAMP:11:2}:${BUILT_TIMESTAMP:13:2}" +%s 2>/dev/null || echo 0)"
		HOURS_DIFF=$(( ($CURRENT_TIMESTAMP - $BUILT_SECONDS) / 3600 ))

		if [ $HOURS_DIFF -lt 1 ]; then
			log "[Building n-s-s] nextcloud-spreed-signaling built less than 1 hour ago and is installed. Skipping build."
			return 0
		fi
	fi

	log "[Building n-s-s] Downloading sources…"
	rm n-s-s-master.tar.gz | tee -a $LOGFILE_PATH || true
	wget https://github.com/strukturag/nextcloud-spreed-signaling/archive/refs/heads/master.tar.gz -O n-s-s-master.tar.gz | tee -a $LOGFILE_PATH

	log "[Building n-s-s] Extracting sources…"
	tar -xvf n-s-s-master.tar.gz | tee -a $LOGFILE_PATH

	log "[Building n-s-s] Building sources…"
	make -C nextcloud-spreed-signaling-master | tee -a $LOGFILE_PATH

	log "[Building n-s-s] Stopping potentially running service…"
	systemctl stop nextcloud-spreed-signaling | tee -a $LOGFILE_PATH || true

	log "[Building n-s-s] Copying built binary into /usr/local/bin/nextcloud-spreed-signaling-server…"
	cp -v nextcloud-spreed-signaling-master/bin/signaling \
		/usr/local/bin/nextcloud-spreed-signaling-server | tee -a $LOGFILE_PATH

	deploy_file "$TMP_DIR_PATH"/signaling/nextcloud-spreed-signaling.service \
		/lib/systemd/system/nextcloud-spreed-signaling.service || true

	if [ ! -d /etc/nextcloud-spreed-signaling ]; then
		log "[Building n-s-s] Creating '/etc/nextcloud-spreed-signaling' directory"
		mkdir /etc/nextcloud-spreed-signaling | tee -a $LOGFILE_PATH
	fi

	log "[Building n-s-s] Creating '_signaling' account"
	# TODO: If bullseye support is dropped sometime then this fix can be dropped too.
	# if adduser >= 3.122; then use --allow-bad-names
	# if not; then use --force-badname
	badname_option="--allow-bad-names"
	version=$(dpkg-query --show --showformat='${Version}' adduser)
	if dpkg --compare-versions "$version" "lt" "3.122"; then
		badname_option="--force-badname"
	fi
	adduser --system --group --home /var/lib/nextcloud-spreed-signaling \
		"$badname_option" _signaling || true

	# Mark this version as built
	if ! is_dry_run; then
		mkdir -p "$(dirname "$NSS_BUILD_MARKER")"
		echo "$NSS_VERSION" > "$NSS_BUILD_MARKER"
		log "[Building n-s-s] Marked version $NSS_VERSION as built in $NSS_BUILD_MARKER"
	fi
}

#function signaling_step1() {
#	log "\n${green}Step 1: Import sunweaver's gpg key."
#	is_dry_run || wget http://packages.sunweavers.net/archive.key \
#		-O /etc/apt/trusted.gpg.d/sunweaver-archive-keyring.asc
#}

#function signaling_step2() {
#	log "\n${green}Step 2: Add sunweaver package repository"
#
#	is_dry_run || cat <<EOF >$SIGNALING_SUNWEAVER_SOURCE_FILE
## Added by nextcloud-high-performance-backend setup-script.
#deb http://packages.sunweavers.net/debian bookworm main
#EOF
#}

function signaling_step3() {
	log "\n${green}Step 3: Install packages"

	# Installing:
	# - janus
	# - nats-server
	# - nextcloud-spreed-signaling
	# - coturn
	APT_PARAMS="-y"
	if [ "$UNATTENDED_INSTALL" == true ]; then
		export DEBIAN_FRONTEND=noninteractive
		APT_PARAMS="-qqy"
	fi

	if [ "$DEBIAN_VERSION_MAJOR" = "11" ]; then
		# Nope, always build from sources. This function should never be called in the first place.
		exit 1;
	elif [ "$DEBIAN_VERSION_MAJOR" = "12" ]; then
		# Special case, please install 'nextcloud-spreed-signaling' from bookworm-backports.
		is_dry_run || apt-get install $APT_PARAMS janus nats-server coturn ssl-cert 2>&1 | tee -a $LOGFILE_PATH
		is_dry_run || apt-get install $APT_PARAMS -t bookworm-backports nextcloud-spreed-signaling nextcloud-spreed-signaling-client 2>&1 | tee -a $LOGFILE_PATH
	else
		is_dry_run || apt-get install $APT_PARAMS janus nats-server coturn ssl-cert nextcloud-spreed-signaling nextcloud-spreed-signaling-client 2>&1 | tee -a $LOGFILE_PATH
	fi
}

function signaling_step4() {
	log "\n${green}Step 4: Prepare configuration"

	# Make sure /etc/nginx/snippets/ is created
	is_dry_run || mkdir -p /etc/nginx/snippets || true

	# Make SSL certificates available for coturn
	if [ "$SHOULD_INSTALL_CERTBOT" = true ] && ! is_dry_run; then
		mkdir -p "$COTURN_DIR/certs"
		adduser turnserver ssl-cert
	else
		is_dry_run || mkdir -p "$COTURN_DIR"
	fi

	generate_dhparam_file

	is_dry_run || chown -R turnserver:turnserver "$COTURN_DIR"
	is_dry_run || chmod -R 740 "$COTURN_DIR"

	i=0
	for NC_SERVER in "${NEXTCLOUD_SERVER_FQDNS[@]}"; do
		NC_SERVER_UNDERSCORE=$(echo "$NC_SERVER" | sed "s/\./_/g")
		SIGNALING_NC_SERVER_SECRETS[$NC_SERVER_UNDERSCORE]="$(openssl rand -hex 16)"
		SIGNALING_NC_SERVER_SESSIONLIMIT[$NC_SERVER_UNDERSCORE]=0
		SIGNALING_NC_SERVER_MAXSTREAMBITRATE[$NC_SERVER_UNDERSCORE]=0
		SIGNALING_NC_SERVER_MAXSCREENBITRATE[$NC_SERVER_UNDERSCORE]=0

		SIGNALING_BACKENDS+=("nextcloud-backend-$i")

		IFS= read -r -d '' SIGNALING_BACKEND_DEFINITION <<-EOF || true
			[nextcloud-backend-$i]
			url = https://$NC_SERVER
			secret = ${SIGNALING_NC_SERVER_SECRETS["$NC_SERVER_UNDERSCORE"]}
			#sessionlimit = ${SIGNALING_NC_SERVER_SESSIONLIMIT["$NC_SERVER_UNDERSCORE"]}
			#maxstreambitrate = ${SIGNALING_NC_SERVER_MAXSTREAMBITRATE["$NC_SERVER_UNDERSCORE"]}
			#maxscreenbitrate = ${SIGNALING_NC_SERVER_MAXSCREENBITRATE["$NC_SERVER_UNDERSCORE"]}
		EOF

		# Escape newlines for sed later on.
		SIGNALING_BACKEND_DEFINITION=$(echo "$SIGNALING_BACKEND_DEFINITION" | sed -z 's|\n|\\n|g')
		SIGNALING_BACKEND_DEFINITIONS+=("$SIGNALING_BACKEND_DEFINITION")

		i=$(($i + 1))
	done

	# Don't actually *log* passwords! (Or do for debugging…)

	# log "Replacing '<SIGNALING_TURN_STATIC_AUTH_SECRET>' with '$SIGNALING_TURN_STATIC_AUTH_SECRET'…"
	log "Replacing '<SIGNALING_TURN_STATIC_AUTH_SECRET>'…"
	sed -i "s|<SIGNALING_TURN_STATIC_AUTH_SECRET>|$SIGNALING_TURN_STATIC_AUTH_SECRET|g" "$TMP_DIR_PATH"/signaling/*

	# log "Replacing '<SIGNALING_JANUS_API_KEY>' with '$SIGNALING_JANUS_API_KEY'…"
	log "Replacing '<SIGNALING_JANUS_API_KEY>…'"
	sed -i "s|<SIGNALING_JANUS_API_KEY>|$SIGNALING_JANUS_API_KEY|g" "$TMP_DIR_PATH"/signaling/*

	# log "Replacing '<SIGNALING_HASH_KEY>' with '$SIGNALING_HASH_KEY'…"
	log "Replacing '<SIGNALING_HASH_KEY>…'"
	sed -i "s|<SIGNALING_HASH_KEY>|$SIGNALING_HASH_KEY|g" "$TMP_DIR_PATH"/signaling/*

	# log "Replacing '<SIGNALING_BLOCK_KEY>' with '$SIGNALING_BLOCK_KEY'…"
	log "Replacing '<SIGNALING_BLOCK_KEY>…'"
	sed -i "s|<SIGNALING_BLOCK_KEY>|$SIGNALING_BLOCK_KEY|g" "$TMP_DIR_PATH"/signaling/*

	IFS=,
	log "Replacing '<SIGNALING_BACKENDS>' with '""${SIGNALING_BACKENDS[*]}""'…"
	sed -i "s|<SIGNALING_BACKENDS>|""${SIGNALING_BACKENDS[*]}""|g" "$TMP_DIR_PATH"/signaling/*
	unset IFS

	IFS= # Avoid whitespace between definitions.
	#log "Replacing '<SIGNALING_BACKEND_DEFINITIONS>' with:\n${SIGNALING_BACKEND_DEFINITIONS[*]}"
	log "Replacing '<SIGNALING_BACKEND_DEFINITIONS>'…"
	sed -ri "s|<SIGNALING_BACKEND_DEFINITIONS>|${SIGNALING_BACKEND_DEFINITIONS[*]}|g" "$TMP_DIR_PATH"/signaling/*
	unset IFS

	log "Replacing '<SIGNALING_COTURN_URL>' with '$SIGNALING_COTURN_URL'…"
	sed -i "s|<SIGNALING_COTURN_URL>|$SIGNALING_COTURN_URL|g" "$TMP_DIR_PATH"/signaling/*

	log "Replacing '<SSL_CERT_PATH_RSA>' with '$SSL_CERT_PATH_RSA'…"
	sed -i "s|<SSL_CERT_PATH_RSA>|$SSL_CERT_PATH_RSA|g" "$TMP_DIR_PATH"/signaling/*

	log "Replacing '<SSL_CERT_KEY_PATH_RSA>' with '$SSL_CERT_KEY_PATH_RSA'…"
	sed -i "s|<SSL_CERT_KEY_PATH_RSA>|$SSL_CERT_KEY_PATH_RSA|g" "$TMP_DIR_PATH"/signaling/*

	log "Replacing '<SSL_CHAIN_PATH_RSA>' with '$SSL_CHAIN_PATH_RSA'…"
	sed -i "s|<SSL_CHAIN_PATH_RSA>|$SSL_CHAIN_PATH_RSA|g" "$TMP_DIR_PATH"/signaling/*

	log "Replacing '<SSL_CERT_PATH_ECDSA>' with '$SSL_CERT_PATH_ECDSA'…"
	sed -i "s|<SSL_CERT_PATH_ECDSA>|$SSL_CERT_PATH_ECDSA|g" "$TMP_DIR_PATH"/signaling/*

	log "Replacing '<SSL_CERT_KEY_PATH_ECDSA>' with '$SSL_CERT_KEY_PATH_ECDSA'…"
	sed -i "s|<SSL_CERT_KEY_PATH_ECDSA>|$SSL_CERT_KEY_PATH_ECDSA|g" "$TMP_DIR_PATH"/signaling/*

	log "Replacing '<SSL_CHAIN_PATH_ECDSA>' with '$SSL_CHAIN_PATH_ECDSA'…"
	sed -i "s|<SSL_CHAIN_PATH_ECDSA>|$SSL_CHAIN_PATH_ECDSA|g" "$TMP_DIR_PATH"/signaling/*

	log "Replacing '<DHPARAM_PATH>' with '$DHPARAM_PATH'…"
	sed -i "s|<DHPARAM_PATH>|$DHPARAM_PATH|g" "$TMP_DIR_PATH"/signaling/*

	EXTERN_IPv4=$(wget -4 https://ident.me -O - -o /dev/null || true)
	log "Replacing '<SIGNALING_COTURN_EXTERN_IPV4>' with '$EXTERN_IPv4'…"
	sed -i "s|<SIGNALING_COTURN_EXTERN_IPV4>|$EXTERN_IPv4|g" "$TMP_DIR_PATH"/signaling/*

	EXTERN_IPv6=$(wget -6 https://ident.me -O - -o /dev/null || true)
	log "Replacing '<SIGNALING_COTURN_EXTERN_IPV6>' with '$EXTERN_IPv6'…"
	sed -i "s|<SIGNALING_COTURN_EXTERN_IPV6>|$EXTERN_IPv6|g" "$TMP_DIR_PATH"/signaling/*
}

function signaling_step5() {
	log "\n${green}Step 5: Deploy configuration"

	deploy_file "$TMP_DIR_PATH"/signaling/nginx-signaling-upstream-servers.conf /etc/nginx/snippets/signaling-upstream-servers.conf || true
	deploy_file "$TMP_DIR_PATH"/signaling/nginx-signaling-forwarding.conf /etc/nginx/snippets/signaling-forwarding.conf || true

	# Ensure /etc/janus directory exists
	is_dry_run || mkdir -p /etc/janus

	if [ "$(dpkg --print-architecture)" = "arm64" ]; then
		deploy_file "$TMP_DIR_PATH"/signaling/janus_aarch64.jcfg /etc/janus/janus.jcfg || true
	elif [ "$(dpkg --print-architecture)" = "ppc64el" ]; then
		deploy_file "$TMP_DIR_PATH"/signaling/janus_powerpc64le.jcfg /etc/janus/janus.jcfg || true
	else
		deploy_file "$TMP_DIR_PATH"/signaling/janus.jcfg /etc/janus/janus.jcfg || true
	fi
	deploy_file "$TMP_DIR_PATH"/signaling/janus.transport.http.jcfg /etc/janus/janus.transport.http.jcfg || true
	deploy_file "$TMP_DIR_PATH"/signaling/janus.transport.websockets.jcfg /etc/janus/janus.transport.websockets.jcfg || true

	deploy_file "$TMP_DIR_PATH"/signaling/signaling-server.conf /etc/nextcloud-spreed-signaling/server.conf || true

	deploy_file "$TMP_DIR_PATH"/signaling/turnserver.conf /etc/turnserver.conf || true
}

# arg: $1 is secret file path
function signaling_write_secrets_to_file() {
	if is_dry_run; then
		return 0
	fi

	echo -e "=== Signaling / Nextcloud Talk ===" >>$1
	echo -e "Janus API key: $SIGNALING_JANUS_API_KEY" >>$1
	echo -e "Hash key:      $SIGNALING_HASH_KEY" >>$1
	echo -e "Block key:     $SIGNALING_BLOCK_KEY" >>$1
	echo -e "" >>$1
	echo -e "Allowed Nextcloud Servers:" >>$1
	echo -e "$(printf '\t- https://%s\n' "${NEXTCLOUD_SERVER_FQDNS[@]}")" >>$1
	echo -e "STUN server = $SERVER_FQDN:5349" >>$1
	echo -e "TURN server:" >>$1
	echo -e " - 'turn and turns'" >>$1
	echo -e " - $SERVER_FQDN:5349" >>$1
	echo -e " - $SIGNALING_TURN_STATIC_AUTH_SECRET" >>$1
	echo -e " - 'udp & tcp'" >>$1
	echo -e "High-performance backend:" >>$1
	echo -e " - https://$SERVER_FQDN/standalone-signaling" >>$1

	for NC_SERVER in "${NEXTCLOUD_SERVER_FQDNS[@]}"; do
		NC_SERVER_UNDERSCORE=$(echo "$NC_SERVER" | sed "s/\./_/g")
		echo -e " - $NC_SERVER\t-> ${SIGNALING_NC_SERVER_SECRETS["$NC_SERVER_UNDERSCORE"]}" >>$1
	done
}

function signaling_print_info() {
	log "The services coturn janus nats-server and nextcloud-signaling-spreed" \
		"\ngot installed. To set it up, log into all of your Nextcloud" \
		"\ninstances with an adminstrator account and install the Talk app." \
		"\nThen navigate to Settings -> Administration -> Talk and put in the" \
		"\nsettings down below.\n" \
		"$(for NC_SERVER in "${NEXTCLOUD_SERVER_FQDNS[@]}"; do printf '\t- %shttps://%s%s\n' "${cyan}" "$NC_SERVER" "${blue}"; done)\n"

	# Don't actually *log* passwords!
	log "STUN server = ${cyan}$SERVER_FQDN:5349"
	log "TURN server:"
	log " - '${cyan}turn and turns${blue}'"
	log " - ${cyan}turnserver+port${blue}: ${cyan}$SERVER_FQDN:5349"
	echo -e " - secret: ${cyan}$SIGNALING_TURN_STATIC_AUTH_SECRET"
	log " - '${cyan}udp & tcp${blue}'"
	log "High-performance backend:"
	log " - ${cyan}https://$SERVER_FQDN/standalone-signaling"

	for NC_SERVER in "${NEXTCLOUD_SERVER_FQDNS[@]}"; do
		NC_SERVER_UNDERSCORE=$(echo "$NC_SERVER" | sed "s/\./_/g")
		echo -e " - ${cyan}$NC_SERVER${blue}\t-> ${cyan}${SIGNALING_NC_SERVER_SECRETS["$NC_SERVER_UNDERSCORE"]}"
	done
}
