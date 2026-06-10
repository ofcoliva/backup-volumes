#!/bin/bash
set -e

# borg volume
REPO="/volumes/backup-local-borg"

# repository keys
KEYDIR="/volumes/borg-keys"

# todos os diretórios de log
LOG_DIR="/var/log/backup-volumes"
LOG_FILE="$LOG_DIR/default.log"
BOOTSTRAP_LOG="$LOG_DIR/boostrap.log"
BORG_LOG="$LOG_DIR/borg.log"
BORGMATIC_LOG="$LOG_DIR/borgmatic.log"
RCLONE_LOG="$LOG_DIR/rclone.log"
LOGROTATE_LOG="$LOG_DIR/logrotate.log"
APPRISE_LOG="$LOG_DIR/apprise.log"

# rclone
RCLONE_CONFIG="/root/.config/rclone/rclone.conf"
RCLONE_DEST="gcp-storage:BACKUP-VOLUMES"

# logrotate
LOGROTATE_CONFIG="/etc/logrotate.conf"
LOGROTATE_STATUS="/var/logrotate.status"

ensrue_dirs() {
    mkdir -p "$LOG_DIR" "$KEYDIR"
}

ensure_files() {
    touch "$BOOTSTRAP_LOG" \
    "$BORG_LOG" \
    "$BORGMATIC_LOG" \
    "$RCLONE_LOG" \
    "$LOGROTATE_LOG" \
    "$APPRISE_LOG" \
    "$LOG_FILE"

    touch "$LOGROTATE_STATUS"
}

log() {
    local message="$1"
    local target_log="${2:-$LOG_FILE}"
    echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $message" | tee -a "$target_log"
}

notify() {
    local title="$1"
    local body="$2"
    local safe_body
    local APPRISE_STATUS
    local APPRISE_URL="mailtos://${SMTP_USER}:${SMTP_PASS}@smtp.gmail.com:${SMTP_PORT}?to=${SMTP_TO}&name=Backup-Volumes&starttls=yes"
    
    safe_body=$(echo "$body" | tail -n 25)

    LOG_MARK="APPRISE_START_$(date '+%Y%m%dT%H%M%S')"
    log "$LOG_MARK" "$APPRISE_LOG"

    log "Enviando Notificação -> $title" "$APPRISE_LOG"

    apprise -v \
    -t "$title" \
    -b "$safe_body" \
    "$APPRISE_URL" 2>&1 | tee -a "$APPRISE_LOG"

    APPRISE_STATUS="${PIPESTATUS[0]}"

    APPRISE_TAIL="$(sed -n "/$LOG_MARK/,\$p" "$APPRISE_LOG" | tail -25)"

    if [[ $APPRISE_STATUS -eq 0 ]]; then
        log "Notificação enviada com sucesso." "$APPRISE_LOG"
    else
        log "ERRO: Falha ao enviar notificação. Status: $APPRISE_STATUS." "$APPRISE_LOG"
    fi
}
