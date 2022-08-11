#!/bin/bash

# Signaling server
# https://github.com/strukturag/nextcloud-spreed-signaling

SIGNALING_SUNWEAVER_SOURCE_FILE="/etc/apt/sources.list.d/sunweaver.list"

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

	if [ "$SIGNALING_BUILD_FROM_SOURCES" = true ]; then
		is_dry_run || apt update 2>&1 | tee -a $LOGFILE_PATH

		# Installing: golang-go make build-essential
		if ! is_dry_run; then
			if [ "$UNATTENTED_INSTALL" == true ]; then
				log "Trying unattended install for Signaling."
				export DEBIAN_FRONTEND=noninteractive
				apt-get install -qqy golang-go protobuf-compiler build-essential make 2>&1 | tee -a $LOGFILE_PATH
			else
				apt-get install -y golang-go protobuf-compiler build-essential make 2>&1 | tee -a $LOGFILE_PATH
			fi
		fi

		if ! is_dry_run; then
			log "Removing old packages…"
			if [ "$UNATTENTED_INSTALL" == true ]; then
				export DEBIAN_FRONTEND=noninteractive
				apt-get remove -qqy coturn nats-server \
					nextcloud-spreed-signaling 2>&1 | tee -a $LOGFILE_PATH
			else
				apt-get remove -y coturn nats-server \
					nextcloud-spreed-signaling 2>&1 | tee -a $LOGFILE_PATH
			fi
		fi

		signaling_build_nextcloud-spreed-signaling
		signaling_build_coturn
		signaling_build_nats-server

		log "Reloading systemd."
		systemctl daemon-reload | tee -a $LOGFILE_PATH
	else
		signaling_step1
		signaling_step2
		signaling_step3
	fi

	signaling_step4
	signaling_step5

	log "Signaling install completed."
}

function signaling_build_nats-server() {
	log "Building nats-server…"

	log "Downloading sources…"
	rm nats-server-v*-linux-amd64.tar.gz | tee -a $LOGFILE_PATH || true
	wget $(curl -s https://api.github.com/repos/nats-io/nats-server/releases/latest |
		grep 'linux-amd64.tar.gz' | grep 'browser_download_url' | cut -d\" -f4) |
		tee -a $LOGFILE_PATH

	log "Extracting sources…"
	tar -xvf nats-server-v*-linux-amd64.tar.gz | tee -a $LOGFILE_PATH

	log "Copying built binary into /usr/local/bin/nats-server…"
	cp nats-server-v*-linux-amd64/nats-server /usr/local/bin | tee -a $LOGFILE_PATH

	deploy_file "$TMP_DIR_PATH"/signaling/nats-server.service /lib/systemd/system/nats-server.service || true
}

function signaling_build_coturn() {
	log "Building coturn…"

	log "Installing necessary packages…"
	is_dry_run || apt update 2>&1 | tee -a $LOGFILE_PATH

	# Installing: golang-go make build-essential
	if ! is_dry_run; then
		if [ "$UNATTENTED_INSTALL" == true ]; then
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

	# FIXME: Use here-doc rather than base64 strings…
	log "Creating patch files…"
	echo "RnJvbTogTmljaG9sYXMgR3VyaWV2IDxndXJpZXYtbnNAeWEucnU+CkRhdGU6IFRodSwgMDIgSnVuIDIwMjIgMTI6MzQ6MTcgKzAzMDAKU3ViamVjdDogRG8gbm90IGNoZWNrIEZJUFMgMTQwIG1vZGUKIEl0IGlzIG5vdCBhdmFpbGFibGUgaW4gT3BlblNTTCBhcyBwYWNrYWdlZCBpbiBEZWJpYW4uIFRoZSBPUEVOU1NMX0ZJUFMgbWFjcm8KIGFwcGVhcmVkIGluIGFuY2llbnQgT3BlblNTTCBzb3VyY2VzIGJ1dCB3YXMgbmV2ZXIgZGVmaW5lZC4KIGh0dHBzOi8vc291cmNlcy5kZWJpYW4ub3JnL3NyYy9vcGVuc3NsLzEuMS4xbi0wJTJCZGViMTF1Mi9jcnlwdG8vb19maXBzLmMvCgotLS0KIHNyYy9jbGllbnQvbnNfdHVybl9tc2cuYyB8ICAgIDQgKystLQogMSBmaWxlIGNoYW5nZWQsIDIgaW5zZXJ0aW9ucygrKSwgMiBkZWxldGlvbnMoLSkKCi0tLSBhL3NyYy9jbGllbnQvbnNfdHVybl9tc2cuYworKysgYi9zcmMvY2xpZW50L25zX3R1cm5fbXNnLmMKQEAgLTI0NCw3ICsyNDQsNyBAQCBpbnQgc3R1bl9wcm9kdWNlX2ludGVncml0eV9rZXlfc3RyKGNvbnN0CiAJCXVuc2lnbmVkIGludCBrZXlsZW4gPSAwOwogCQlFVlBfTURfQ1RYIGN0eDsKIAkJRVZQX01EX0NUWF9pbml0KCZjdHgpOwotI2lmIGRlZmluZWQgRVZQX01EX0NUWF9GTEFHX05PTl9GSVBTX0FMTE9XICYmICFkZWZpbmVkKExJQlJFU1NMX1ZFUlNJT05fTlVNQkVSKQorI2lmZGVmIE9QRU5TU0xfRklQUwogCQlpZiAoRklQU19tb2RlKCkpIHsKIAkJCUVWUF9NRF9DVFhfc2V0X2ZsYWdzKCZjdHgsRVZQX01EX0NUWF9GTEFHX05PTl9GSVBTX0FMTE9XKTsKIAkJfQpAQCAtMjU2LDcgKzI1Niw3IEBAIGludCBzdHVuX3Byb2R1Y2VfaW50ZWdyaXR5X2tleV9zdHIoY29uc3QKICNlbHNlCiAJCXVuc2lnbmVkIGludCBrZXlsZW4gPSAwOwogCQlFVlBfTURfQ1RYICpjdHggPSBFVlBfTURfQ1RYX25ldygpOwotI2lmIGRlZmluZWQgRVZQX01EX0NUWF9GTEFHX05PTl9GSVBTX0FMTE9XICYmICEgZGVmaW5lZChMSUJSRVNTTF9WRVJTSU9OX05VTUJFUikKKyNpZmRlZiBPUEVOU1NMX0ZJUFMKIAkJaWYgKEZJUFNfbW9kZSgpKSB7CiAJCQlFVlBfTURfQ1RYX3NldF9mbGFncyhjdHgsIEVWUF9NRF9DVFhfRkxBR19OT05fRklQU19BTExPVyk7CiAJCX0K" | base64 -d - >No-FIPS-140-mode.patch

	log "Applying patches…"
	git apply --directory=coturn-master No-FIPS-140-mode.patch | tee -a $LOGFILE_PATH

	log "Creating build directory…"
	mkdir coturn-master/build | tee -a $LOGFILE_PATH || true

	log "Run configure script which will make a Makefile for this system…"
	cmake -S coturn-master -B coturn-master/build | tee -a $LOGFILE_PATH

	log "Build & install coturn."
	cmake --build coturn-master/build --target install | tee -a $LOGFILE_PATH

	deploy_file "$TMP_DIR_PATH"/signaling/coturn.service /lib/systemd/system/coturn.service || true

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

	log "Creating '_signaling' account"
	adduser --system --group --home /var/lib/nextcloud-spreed-signaling \
		--force-badname _signaling || true

	# In some mysterious update they changed --allow-badname to --force-badname…
	adduser --system --group --home /var/lib/nextcloud-spreed-signaling \
		--allow-badname _signaling || true
}

function signaling_step1() {
	log "\nStep 1: Import sunweaver's gpg key."
	is_dry_run || wget http://packages.sunweavers.net/archive.key \
		-O /etc/apt/trusted.gpg.d/sunweaver-archive-keyring.asc
}

function signaling_step2() {
	log "\nStep 2: Add sunweaver package repository"

	is_dry_run || cat <<EOF >$SIGNALING_SUNWEAVER_SOURCE_FILE
# Added by nextcloud-high-performance-backend setup-script.
deb http://packages.sunweavers.net/debian bookworm main
EOF
}

function signaling_step3() {
	log "\nStep 3: Install packages"

	is_dry_run || apt update 2>&1 | tee -a $LOGFILE_PATH

	# Installing:
	# - janus
	# - nats Server
	# - nextcloud-spreed-signaling
	# - coturn
	if ! is_dry_run; then
		if [ "$UNATTENTED_INSTALL" == true ]; then
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

	# Jump through extra hoops for coturn.
	if [ "$SHOULD_INSTALL_CERTBOT" = true ]; then
		COTURN_SSL_CERT_PATH="$COTURN_DIR/certs/$SERVER_FQDN.crt"
		COTURN_SSL_CERT_KEY_PATH="$COTURN_DIR/certs/$SERVER_FQDN.key"
		is_dry_run || mkdir -p "$COTURN_DIR/certs"
		is_dry_run || mkdir -p "/etc/letsencrypt/renewal-hooks/deploy/"
	else
		COTURN_SSL_CERT_PATH="$SSL_CERT_PATH"
		COTURN_SSL_CERT_KEY_PATH="$SSL_CERT_KEY_PATH"
		is_dry_run || mkdir -p "$COTURN_DIR"
	fi

	is_dry_run || touch "$COTURN_DIR/dhp.pem"
	is_dry_run || openssl dhparam -dsaparam -out "$COTURN_DIR/dhp.pem" 4096
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

	log "Replacing '<SSL_CERT_PATH>' with '$SSL_CERT_PATH'…"
	sed -i "s|<SSL_CERT_PATH>|$SSL_CERT_PATH|g" "$TMP_DIR_PATH"/signaling/*

	log "Replacing '<SSL_CERT_KEY_PATH>' with '$SSL_CERT_KEY_PATH'…"
	sed -i "s|<SSL_CERT_KEY_PATH>|$SSL_CERT_KEY_PATH|g" "$TMP_DIR_PATH"/signaling/*

	log "Replacing '<COTURN_SSL_CERT_PATH>' with '$COTURN_SSL_CERT_PATH'…"
	sed -i "s|<COTURN_SSL_CERT_PATH>|$COTURN_SSL_CERT_PATH|g" "$TMP_DIR_PATH"/signaling/*

	log "Replacing '<COTURN_SSL_CERT_KEY_PATH>' with '$COTURN_SSL_CERT_KEY_PATH'…"
	sed -i "s|<COTURN_SSL_CERT_KEY_PATH>|$COTURN_SSL_CERT_KEY_PATH|g" "$TMP_DIR_PATH"/signaling/*

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

	deploy_file "$TMP_DIR_PATH"/signaling/janus.jcfg /etc/janus/janus.jcfg || true
	deploy_file "$TMP_DIR_PATH"/signaling/janus.transport.http.jcfg /etc/janus/janus.transport.http.jcfg || true
	deploy_file "$TMP_DIR_PATH"/signaling/janus.transport.websockets.jcfg /etc/janus/janus.transport.websockets.jcfg || true

	deploy_file "$TMP_DIR_PATH"/signaling/signaling-server.conf /etc/nextcloud-spreed-signaling/server.conf || true

	deploy_file "$TMP_DIR_PATH"/signaling/turnserver.conf /etc/turnserver.conf || true

	if [ "$SHOULD_INSTALL_CERTBOT" = true ]; then
		deploy_file "$TMP_DIR_PATH"/signaling/coturn-certbot-deploy.sh /etc/letsencrypt/renewal-hooks/deploy/coturn-certbot-deploy.sh || true
		is_dry_run || chmod 700 /etc/letsencrypt/renewal-hooks/deploy/coturn-certbot-deploy.sh
	fi
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
	echo -e "$(printf '\t↳ https://%s\n' "${NEXTCLOUD_SERVER_FQDNS[@]}")" >>$1
	echo -e "STUN server = $SERVER_FQDN:1271" >>$1
	echo -e "TURN server:" >>$1
	echo -e " ↳ 'turn and turns'" >>$1
	echo -e " ↳ $SERVER_FQDN:1271" >>$1
	echo -e " ↳ $SIGNALING_TURN_STATIC_AUTH_SECRET" >>$1
	echo -e " ↳ 'udp & tcp'" >>$1
	echo -e "High-performance backend:" >>$1
	echo -e " ↳ wss://$SERVER_FQDN/standalone-signaling" >>$1

	for NC_SERVER in "${NEXTCLOUD_SERVER_FQDNS[@]}"; do
		NC_SERVER_UNDERSCORE=$(echo "$NC_SERVER" | sed "s/\./_/g")
		echo -e " ↳ $NC_SERVER\t-> ${SIGNALING_NC_SERVER_SECRETS["$NC_SERVER_UNDERSCORE"]}" >>$1
	done
}

function signaling_print_info() {
	log "The services coturn janus nats-server and nextcloud-signaling-spreed" \
		"\ngot installed. To set it up, log into all of your Nextcloud" \
		"\ninstances with an adminstrator account and install the Talk app." \
		"\nThen navigate to Settings -> Administration -> Talk and put in the" \
		"\nsettings down below.\n" \
		"$(printf '\t↳ https://%s\n' "${NEXTCLOUD_SERVER_FQDNS[@]}")\n"

	# Don't actually *log* passwords!
	log "STUN server = $SERVER_FQDN:1271"
	log "TURN server:"
	log " ↳ 'turn and turns'"
	log " ↳ turnserver+port: $SERVER_FQDN:1271"
	echo -e " ↳ secret: $SIGNALING_TURN_STATIC_AUTH_SECRET"
	log " ↳ 'udp & tcp'"
	log "High-performance backend:"
	log " ↳ wss://$SERVER_FQDN/standalone-signaling"

	for NC_SERVER in "${NEXTCLOUD_SERVER_FQDNS[@]}"; do
		NC_SERVER_UNDERSCORE=$(echo "$NC_SERVER" | sed "s/\./_/g")
		echo -e " ↳ $NC_SERVER\t-> ${SIGNALING_NC_SERVER_SECRETS["$NC_SERVER_UNDERSCORE"]}"
	done
}
