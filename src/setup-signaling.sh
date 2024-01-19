#!/bin/bash

# Signaling server
# https://github.com/strukturag/nextcloud-spreed-signaling

#SIGNALING_SUNWEAVER_SOURCE_FILE="/etc/apt/sources.list.d/sunweaver.list"

SIGNALING_BACKPORTS_SOURCE_FILE="/etc/apt/sources.list.d/bullseye-backports.list"

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
	log "Installing Signaling…"

	if [ "$DEBIAN_VERSION_MAJOR" = "12" ] ; then
		log "Enable bookworm-backports"
		is_dry_run || cat <<-EOL >$SIGNALING_BACKPORTS_SOURCE_FILE
			# Added by nextcloud-high-performance-backend setup-script.
			deb http://deb.debian.org/debian bookworm-backports main
		EOL
		is_dry_run || apt-get update 2>&1 | tee -a $LOGFILE_PATH
	fi

	if [ "$DEBIAN_VERSION_MAJOR" = "11" ]; then
		log "Enable bullseye-backports"
		is_dry_run || cat <<-EOL >$SIGNALING_BACKPORTS_SOURCE_FILE
			# Added by nextcloud-high-performance-backend setup-script.
			deb http://deb.debian.org/debian bullseye-backports main
		EOL
		is_dry_run || apt-get update 2>&1 | tee -a $LOGFILE_PATH
	fi

	if [ "$SIGNALING_BUILD_FROM_SOURCES" = true ]; then
		is_dry_run || apt update 2>&1 | tee -a $LOGFILE_PATH

		# Installing: golang-go make build-essential wget curl
		if ! is_dry_run; then
			if [ "$UNATTENDED_INSTALL" == true ]; then
				log "Trying unattended install for Signaling."
				export DEBIAN_FRONTEND=noninteractive
				if [ "$DEBIAN_VERSION_MAJOR" = "11" ]; then
					apt-get install -qqy -t bullseye-backports golang-go 2>&1 | tee -a $LOGFILE_PATH
					apt-get install -qqy wget curl protobuf-compiler build-essential make 2>&1 | tee -a $LOGFILE_PATH
				else
					apt-get install -qqy wget curl golang-go protobuf-compiler build-essential make 2>&1 | tee -a $LOGFILE_PATH
				fi
			else
				if [ "$DEBIAN_VERSION_MAJOR" = "11" ]; then
					apt-get install -y -t bullseye-backports golang-go 2>&1 | tee -a $LOGFILE_PATH
					apt-get install -y wget curl protobuf-compiler build-essential make 2>&1 | tee -a $LOGFILE_PATH
				else
					apt-get install -y wget curl golang-go protobuf-compiler build-essential make 2>&1 | tee -a $LOGFILE_PATH
				fi
			fi
		fi

		if dpkg --compare-versions $DEBIAN_VERSION_MAJOR le 13; then
			is_dry_run || signaling_build_nextcloud-spreed-signaling && log "Would have built nextcloud-spreed-signaling now…"
		fi
		# Only if Debian 11
		if [ "$DEBIAN_VERSION_MAJOR" = "11" ]; then
			is_dry_run || signaling_build_coturn && log "Would have built coturn now…"
			is_dry_run || signaling_build_nats-server && log "Would have built nats-server now…"
		fi

		# Installing:
		# - janus
		# - ssl-cert
		# - nats-server (Debian 12+)
		# - coturn (Debian 12+)
		# - nextcloud-spreed-signaling (Debian 12~bpo+)
		if ! is_dry_run; then
			if [ "$UNATTENDED_INSTALL" == true ]; then
				export DEBIAN_FRONTEND=noninteractive
				if [ "$DEBIAN_VERSION_MAJOR" = "11" ]; then
					apt-get install -qqy ssl-cert 2>&1 | tee -a $LOGFILE_PATH
					apt-get install -qqy -t bullseye-backports janus 2>&1 | tee -a $LOGFILE_PATH
				elif [ "$DEBIAN_VERSION_MAJOR" = "12" ]; then
					apt-get install -qqy janus ssl-cert nats-server coturn 2>&1 | tee -a $LOGFILE_PATH
					apt-get install -qqy -t bookworm-backports nextcloud-spreed-signaling 2>&1 | tee -a $LOGFILE_PATH
				else
					apt-get install -qqy janus ssl-cert nats-server coturn nextcloud-spreed-signaling 2>&1 | tee -a $LOGFILE_PATH
				fi
			else
				if [ "$DEBIAN_VERSION_MAJOR" = "11" ]; then
					apt-get install -y ssl-cert 2>&1 | tee -a $LOGFILE_PATH
					apt-get install -y -t bullseye-backports janus 2>&1 | tee -a $LOGFILE_PATH
				elif [ "$DEBIAN_VERSION_MAJOR" = "12" ]; then
					apt-get install -y janus ssl-cert nats-server coturn 2>&1 | tee -a $LOGFILE_PATH
					apt-get install -y -t bookworm-backports nextcloud-spreed-signaling 2>&1 | tee -a $LOGFILE_PATH
				else
					apt-get install -y janus ssl-cert nats-server coturn nextcloud-spreed-signaling 2>&1 | tee -a $LOGFILE_PATH
				fi
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

	# Make sure janus is restartet 15 sec after system reboot, wo that coturn service is already up
	# Otherwise, janus will silently crash if coturn is not available.
	set +eo pipefail
	crontab -l >cron_backup
	echo "@reboot sleep 15 && systemctl restart janus > /dev/null 2>&1" >>cron_backup
	crontab cron_backup
	rm cron_backup
	set -eo pipefail

	log "Signaling install completed."
}

function signaling_build_nats-server() {
	log "Building nats-server…"

	LATEST_RELEASE="https://api.github.com/repos/nats-io/nats-server/releases/latest"
	log "Latest nats-server release URL: '$LATEST_RELEASE'"

	LATEST_RELEASE_TAG="$(curl -s "$LATEST_RELEASE" | grep 'tag_name' | cut -d\" -f4)"
	log "Latest nats-server version is: '$LATEST_RELEASE_TAG'"

	log "Removing old sources…"
	rm -v nats-server-v*-linux-*.tar.gz | tee -a $LOGFILE_PATH || true

	log "Downloading sources…"
	if [ "$(dpkg --print-architecture)" = "arm64" ]; then
		wget $(curl -s "$LATEST_RELEASE" | grep 'linux-arm64.tar.gz' |
			grep 'browser_download_url' | cut -d\" -f4) |
			tee -a $LOGFILE_PATH
	else
		wget $(curl -s "$LATEST_RELEASE" | grep 'linux-amd64.tar.gz' |
			grep 'browser_download_url' | cut -d\" -f4) |
			tee -a $LOGFILE_PATH
   	fi

	log "Extracting sources…"
	tar -xvf "nats-server-$LATEST_RELEASE_TAG-linux-*.tar.gz" | tee -a $LOGFILE_PATH

	log "Copying binary into /usr/local/bin/nats-server…"
	cp --backup=numbered -v "nats-server-$LATEST_RELEASE_TAG-linux-*/nats-server" /usr/local/bin/nats-server | tee -a $LOGFILE_PATH

	deploy_file "$TMP_DIR_PATH"/signaling/nats-server.service /lib/systemd/system/nats-server.service || true
	deploy_file "$TMP_DIR_PATH"/signaling/nats-server.conf /etc/nats-server.conf || true

	log "Creating 'nats' system account…"
	adduser --system --group nats || true
}

function signaling_build_coturn() {
	log "Building coturn…"

	log "Installing necessary packages…"
	is_dry_run || apt update 2>&1 | tee -a $LOGFILE_PATH

	# Installing: golang-go make build-essential
	if ! is_dry_run; then
		if [ "$UNATTENDED_INSTALL" == true ]; then
			log "Trying unattended install for Signaling."
			export DEBIAN_FRONTEND=noninteractive
			apt-get install -qqy cmake libssl-dev libevent-dev git 2>&1 | tee -a $LOGFILE_PATH
		else
			apt-get install -y cmake libssl-dev libevent-dev git 2>&1 | tee -a $LOGFILE_PATH
		fi
	fi

	log "Downloading sources…"
	rm coturn-master.tar.gz | tee -a $LOGFILE_PATH || true
	wget https://github.com/coturn/coturn/archive/refs/heads/master.tar.gz -O coturn-master.tar.gz | tee -a $LOGFILE_PATH

	log "Extracting sources…"
	tar -xvf coturn-master.tar.gz | tee -a $LOGFILE_PATH

	log "Creating build directory…"
	mkdir coturn-master/build | tee -a $LOGFILE_PATH || true

	log "Run configure script which will make a Makefile for this system…"
	cmake -S coturn-master -B coturn-master/build | tee -a $LOGFILE_PATH

	log "Build & install coturn."
	cmake --build coturn-master/build --target install | tee -a $LOGFILE_PATH

	deploy_file "$TMP_DIR_PATH"/signaling/coturn.service /lib/systemd/system/coturn.service || true

	chmod 755 /usr/local/bin/turnserver

	log "Creating 'turnserver' account"
	adduser --system --group --home /var/lib/turnserver turnserver || true
}

function signaling_build_nextcloud-spreed-signaling() {
	log "Building nextcloud-spreed-signaling…"

	log "Downloading sources…"
	rm n-s-s-master.tar.gz | tee -a $LOGFILE_PATH || true
	wget https://github.com/strukturag/nextcloud-spreed-signaling/archive/refs/heads/master.tar.gz -O n-s-s-master.tar.gz | tee -a $LOGFILE_PATH

	log "Extracting sources…"
	tar -xvf n-s-s-master.tar.gz | tee -a $LOGFILE_PATH

	log "Building sources…"
	make -C nextcloud-spreed-signaling-master | tee -a $LOGFILE_PATH

	log "Stopping potential running service…"
	systemctl stop nextcloud-spreed-signaling | tee -a $LOGFILE_PATH || true

	log "Copying built binary into /usr/local/bin/nextcloud-spreed-signaling-server…"
	cp -v nextcloud-spreed-signaling-master/bin/signaling \
		/usr/local/bin/nextcloud-spreed-signaling-server | tee -a $LOGFILE_PATH

	deploy_file "$TMP_DIR_PATH"/signaling/nextcloud-spreed-signaling.service \
		/lib/systemd/system/nextcloud-spreed-signaling.service || true

	if [ ! -d /etc/nextcloud-spreed-signaling ]; then
		log "Create '/etc/nextcloud-spreed-signaling' directory"
		mkdir /etc/nextcloud-spreed-signaling | tee -a $LOGFILE_PATH
	fi

	log "Creating '_signaling' account"
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
}

#function signaling_step1() {
#	log "\nStep 1: Import sunweaver's gpg key."
#	is_dry_run || wget http://packages.sunweavers.net/archive.key \
#		-O /etc/apt/trusted.gpg.d/sunweaver-archive-keyring.asc
#}

#function signaling_step2() {
#	log "\nStep 2: Add sunweaver package repository"
#
#	is_dry_run || cat <<EOF >$SIGNALING_SUNWEAVER_SOURCE_FILE
## Added by nextcloud-high-performance-backend setup-script.
#deb http://packages.sunweavers.net/debian bookworm main
#EOF
#}

function signaling_step3() {
	log "\nStep 3: Install packages"

	is_dry_run || apt update 2>&1 | tee -a $LOGFILE_PATH

	# Installing:
	# - janus
	# - nats-server
	# - nextcloud-spreed-signaling
	# - coturn
	if ! is_dry_run; then
		if [ "$UNATTENDED_INSTALL" == true ]; then
			log "Trying unattended install for Signaling."
			export DEBIAN_FRONTEND=noninteractive
			apt-get install -qqy janus nats-server nextcloud-spreed-signaling \
				coturn ssl-cert 2>&1 | tee -a $LOGFILE_PATH
		else
			apt-get install -y janus nats-server nextcloud-spreed-signaling \
				coturn ssl-cert 2>&1 | tee -a $LOGFILE_PATH
		fi
	fi
}

function signaling_step4() {
	log "\nStep 4: Prepare configuration"

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

	EXTERN_IPv4=$(wget -4 ident.me -O - -o /dev/null || true)
	log "Replacing '<SIGNALING_COTURN_EXTERN_IPV4>' with '$EXTERN_IPv4'…"
	sed -i "s|<SIGNALING_COTURN_EXTERN_IPV4>|$EXTERN_IPv4|g" "$TMP_DIR_PATH"/signaling/*

	EXTERN_IPv6=$(wget -6 ident.me -O - -o /dev/null || true)
	log "Replacing '<SIGNALING_COTURN_EXTERN_IPV6>' with '$EXTERN_IPv6'…"
	sed -i "s|<SIGNALING_COTURN_EXTERN_IPV6>|$EXTERN_IPv6|g" "$TMP_DIR_PATH"/signaling/*
}

function signaling_step5() {
	log "\nStep 5: Deploy configuration"

	deploy_file "$TMP_DIR_PATH"/signaling/nginx-signaling-upstream-servers.conf /etc/nginx/snippets/signaling-upstream-servers.conf || true
	deploy_file "$TMP_DIR_PATH"/signaling/nginx-signaling-forwarding.conf /etc/nginx/snippets/signaling-forwarding.conf || true

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
		"$(printf '\t- https://%s\n' "${NEXTCLOUD_SERVER_FQDNS[@]}")\n"

	# Don't actually *log* passwords!
	log "STUN server = $SERVER_FQDN:5349"
	log "TURN server:"
	log " - 'turn and turns'"
	log " - turnserver+port: $SERVER_FQDN:5349"
	echo -e " - secret: $SIGNALING_TURN_STATIC_AUTH_SECRET"
	log " - 'udp & tcp'"
	log "High-performance backend:"
	log " - https://$SERVER_FQDN/standalone-signaling"

	for NC_SERVER in "${NEXTCLOUD_SERVER_FQDNS[@]}"; do
		NC_SERVER_UNDERSCORE=$(echo "$NC_SERVER" | sed "s/\./_/g")
		echo -e " - $NC_SERVER\t-> ${SIGNALING_NC_SERVER_SECRETS["$NC_SERVER_UNDERSCORE"]}"
	done
}
