#!/bin/bash
set -e
. /scripts/common.sh

log "Iniciando Logrotate" "$LOGROTATE_LOG"

# muda permissões para logrotate
chown root:root /etc/logrotate.conf
chmod 0644 /etc/logrotate.conf

logrotate -s "$STATUS_FILE" "$LOGROTATE_CONFIG" | tee -a "$LOGROTATE_LOG"

log "Logrotate finalizado" "$LOGROTATE_LOG"
