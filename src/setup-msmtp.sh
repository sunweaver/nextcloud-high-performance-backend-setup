#!/bin/bash

function msmtp_do_preseed() {
    pkg="$1"
    template="$2"
    type="$3"
    value="$4"
    is_dry_run ||
        echo $pkg $template $type "$value" | debconf-set-selections ||
        log "Failed to load preseed '$template'"
}

function msmtp_do_reconfigure() {
    package="$1"
    log "Silently running dpkg-reconfigure on package $package…"
    is_dry_run || dpkg -l $package 1>/dev/null 2>/dev/null && {
        dpkg-reconfigure -fnoninteractive -pcritical $package &&
            log "Reconfigure DONE" || log "Reconfigure FAILED"
    }
}

function install_msmtp() {
    log "Installing msmtp…"

    msmtp_step1
    msmtp_step2
    msmtp_step3
    msmtp_step4
    msmtp_step5

    log "msmtp install completed."
}

function msmtp_step1() {
    log "\nStep 1: Installing msmtp package"

    is_dry_run || apt update 2>&1 | tee -a $LOGFILE_PATH

    # Installing:
    #   - msmtp
    #   - msmtp-mta
    #   - mailutils
    if ! is_dry_run; then
        if [ "$UNATTENTED_INSTALL" == true ]; then
            log "Trying unattended install for msmtp etup."
            export DEBIAN_FRONTEND=noninteractive
            args_apt="-qqy"
        else
            args_apt="-y"
        fi

        apt-get install "$args_apt" msmtp msmtp-mta mailutils 2>&1 | tee -a $LOGFILE_PATH
    fi
}

function msmtp_step2() {
    log "\nStep 2: Preseed and reconfigure msmtp package."
    if ! is_dry_run; then
        # preseed and reconfigure
        msmtp_do_preseed msmtp msmtp/apparmor boolean false 2>&1 | tee -a $LOGFILE_PATH
        msmtp_do_reconfigure msmtp 2>&1 | tee -a $LOGFILE_PATH
    fi
}

function msmtp_step3() {
    log "\nStep 3: Prepare msmtp configuration"

    # Don't actually *log* passwords! (Or do for debugging…)

    log "Replacing '<EMAIL_USER_ADDRESS>' with '$EMAIL_USER_ADDRESS'…"
    sed -i "s|<EMAIL_USER_ADDRESS>|$EMAIL_USER_ADDRESS|g" "$TMP_DIR_PATH"/msmtp/*

    log "Replacing '<EMAIL_USER_USERNAME>' with '$EMAIL_USER_USERNAME'…"
    sed -i "s|<EMAIL_USER_USERNAME>|$EMAIL_USER_USERNAME|g" "$TMP_DIR_PATH"/msmtp/*

    #log "Replacing '<EMAIL_USER_PASSWORD>' with '$EMAIL_USER_PASSWORD'…"
    log "Replacing '<EMAIL_USER_PASSWORD>…'"
    sed -i "s|<EMAIL_USER_PASSWORD>|$EMAIL_USER_PASSWORD|g" "$TMP_DIR_PATH"/msmtp/*

    log "Replacing '<EMAIL_SERVER_HOST>' with '$EMAIL_SERVER_HOST'…"
    sed -i "s|<EMAIL_SERVER_HOST>|$EMAIL_SERVER_HOST|g" "$TMP_DIR_PATH"/msmtp/*
}

function msmtp_step4() {
    log "\nStep 4: Deploy msmtp configuration"

    deploy_file "$TMP_DIR_PATH"/msmtp/aliases /etc/aliases || true
    deploy_file "$TMP_DIR_PATH"/msmtp/msmtprc /etc/msmtprc || true

    is_dry_run || chmod 600 /etc/msmtprc
}

function msmtp_step5() {
    cat "$TMP_DIR_PATH"/msmtp/test-email.html | msmtp root
}

# arg: $1 is secret file path
function msmtp_write_secrets_to_file() {
    # No secrets, passwords, keys or something to worry about.
    if is_dry_run; then
        return 0
    fi
}

function msmtp_print_info() {
    log ""
}
