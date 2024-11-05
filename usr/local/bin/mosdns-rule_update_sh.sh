#!/bin/sh
#
# Filename: mosdns-rule_update.sh
# Author: Cao Lei <caolei@mail.com>
# Version:  \  Date:
#   1.0.0   -    2024/11/04
#   1.0.2   -    2024/11/05
# Description: This script is used to initialize and update mosdns configuration and data
# Usage: Run this script as root: chmod +x mosdns-rule_update.sh && sh mosdns-rule_update.sh
# Note: Ensure that you understand every command's behaviour and be careful when identifying large files
#
# For crontab(root): 0 3 * * * /bin/sh /usr/local/bin/mosdns-rule_update.sh >> /var/log/mosdns-update.log 2>&1
#
# # !!! Necessary services or software: 'sh' 'systemd or openrc' 'dnslookup' 'tar'

LOG_FILE="/var/log/mosdns-rule_update.log"
MOSDNS_DIR="/etc/mosdns"
BACKUP_DIR="/var/backup/mosdns"

log() {
    status="$1"
    cmd="$2"
    message="$3"
    datetime=$(date '+%Y-%m-%dT%H:%M:%S.%6N%:z')
    script_name=$(basename "$0")
    user=$(whoami)

    echo "${datetime} ${status} ${script_name} (${user}) CMD (${cmd}) MSG (${message})" >>"${LOG_FILE}"
}

detect_service_manager() {
    if command -v systemctl >/dev/null 2>&1; then
        SERVICE_CMD="systemctl"
        STATUS_CMD="$SERVICE_CMD status mosdns"
        RESTART_CMD="$SERVICE_CMD restart mosdns"
    elif command -v rc-service >/dev/null 2>&1; then
        SERVICE_CMD="rc-service"
        STATUS_CMD="$SERVICE_CMD mosdns status"
        RESTART_CMD="$SERVICE_CMD mosdns restart"
    else
        log "ERROR" "Service check" "No compatible service manager found (systemctl or rc-service)"
        exit 1
    fi
}

check() {
    detect_service_manager

    if ! $STATUS_CMD >/dev/null 2>&1; then
        log "ERROR" "$STATUS_CMD" "Service check failed"
        exit 1
    fi

    if ! dnslookup baidu.com 127.0.0.1:5353 >/dev/null 2>&1; then
        log "ERROR" "dnslookup baidu.com 127.0.0.1:5353" "DNS check for baidu.com failed"
        exit 1
    fi

    if ! dnslookup example.org 127.0.0.1:5353 >/dev/null 2>&1; then
        log "ERROR" "dnslookup example.org 127.0.0.1:5353" "DNS check for example.org failed"
        exit 1
    fi
}

backup() {
    rule_files="config.yaml rule/blocklist.txt rule/cloudflare-cidr.txt rule/ddnslist.txt rule/disable-ads.txt rule/geoip-only-cn-private_cn.txt rule/geosite_apple.txt rule/geosite_category-ads-all.txt rule/geosite_cn.txt rule/geosite_geolocation-!cn.txt rule/greylist.txt rule/hosts.txt rule/local-ptr.txt rule/redirect.txt rule/whitelist.txt"
    date=$(date '+%Y%m%d')
    backup_file="mosdns_${date}.tar.gz"
    temp_backup_dir=$(mktemp -d)

    mkdir -p "${MOSDNS_DIR}"
    mkdir -p "${BACKUP_DIR}"

    for file in $rule_files; do
        dir_to_create=$(dirname "${temp_backup_dir}/mosdns/${file}")
        mkdir -p "${dir_to_create}"
        cp "${MOSDNS_DIR}/${file}" "${dir_to_create}/"
    done

    tar czf "${BACKUP_DIR}/${backup_file}" -C "${temp_backup_dir}/mosdns" .
    log "INFO" "tar czf ${BACKUP_DIR}/${backup_file}" "Backup successful"

    rm -rf "${temp_backup_dir}"

    # Keep only the latest 3 backups
    (cd "${BACKUP_DIR}" && ls -t | tail -n +4 | xargs -r rm --)
}

update() {
    TMP_DIR=$(mktemp -d)

    cd "${TMP_DIR}" || exit 1

    url=$(curl -s https://api.github.com/repos/caleee/mosdns/releases/latest | grep -o "https://github.com/caleee/mosdns/releases/download/v.*.tar.gz" | head -n 1)
    if [ -z "$url" ]; then
        log "ERROR" "curl -s https://api.github.com/repos/caleee/mosdns/releases/latest" "No download URL found"
        return 1
    fi

    if ! curl --connect-timeout 5 -m 60 --ipv4 -kfsSLO "$url"; then
        log "ERROR" "curl --connect-timeout 5 -m 60 --ipv4 -kfsSLO $url" "Download failed"
        return 1
    fi

    file=$(basename "$url")

    if ! tar xzf "$file" -C /; then
        log "ERROR" "tar xzf $file -C /" "Unpacking failed"
        return 1
    fi

    cd - >/dev/null || exit 1

    rm -rf "${TMP_DIR}"

    log "INFO" "update" "Mosdns update successfully"
}

restart() {
    if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
        log "INFO" "check" "Running inside a Docker container"
        log "INFO" "reboot" "The file update is complete, and the container is about to restart."
        reboot
    else
        log "INFO" "log" "Running on a normal Linux environment"
        detect_service_manager
        if ! $RESTART_CMD; then
            log "ERROR" "restart mosdns" "Restart service failed"
            return 1
        fi
        log "INFO" "restart mosdns" "Service restarted successfully"
    fi
}

restore() {
    backup_file=$(ls -t "${BACKUP_DIR}"/mosdns_*.tar.gz | head -1)

    if [ -z "$backup_file" ]; then
        log "ERROR" "ls -t ${BACKUP_DIR}/mosdns_*.tar.gz" "No backup file found to restore"
        return 1
    fi

    if ! tar xzf "$backup_file" -C "${MOSDNS_DIR}"; then
        log "ERROR" "tar xzf $backup_file -C ${MOSDNS_DIR}" "Restore failed"
        return 1
    fi

    log "INFO" "tar xzf $backup_file -C ${MOSDNS_DIR}" "Restore successful"
}

main() {
    check
    backup
    if ! update; then
        restore
    fi
    restart
}

if [ $# -eq 0 ]; then
    main
else
    case "$1" in
    check)
        check
        ;;
    backup)
        backup
        ;;
    update)
        update
        ;;
    restore)
        restore
        ;;
    restart)
        restart
        ;;
    *)
        echo "Usage: $0 {check|backup|update|restore|restart}"
        exit 1
        ;;
    esac
fi
