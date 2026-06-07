#!/bin/bash
set -e

STATUS_FILE="/var/log/logrotate.status"
CONFIG_FILE="/etc/logrotate.conf"
LOG_FILE="/var/log/borg/logrotate.log"

log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

log "Iniciando Logrotate"

# muda permissões para logrotate
chown root:root /etc/logrotate.conf
chmod 0644 /etc/logrotate.conf

/usr/sbin/logrotate -s "$STATUS_FILE" "$CONFIG_FILE"

log "Logrotate finalizado"
