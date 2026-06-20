#!/bin/bash
set -e
. /scripts/common.sh

LOG_MARK="BORGMATIC_START_$(date '+%Y%m%dT%H%M%S')"
log "$LOG_MARK" "$BORGMATIC_LOG"
log "Iniciando backup com Borgmatic..." "$BORGMATIC_LOG"

borgmatic create --verbosity 1 --stats --no-color 2>&1 | tee -a "$BORGMATIC_LOG"

BORGMATIC_EXIT="${PIPESTATUS[0]}"

BORGMATIC_TAIL="$(sed -n "/$LOG_MARK/,\$p" "$BORGMATIC_LOG" | tail -25)"

if [[ "$BORGMATIC_EXIT" -eq 0 ]]; then
  MSG="Borgmatic: Backup finalizado."
  log "$MSG" "$BORGMATIC_LOG"
  notify "$MSG" "$BORGMATIC_TAIL"
else
  MSG="Borgmatic: Backup falhou."
  log "$MSG" "$BORGMATIC_LOG"
  notify "$MSG" "$BORGMATIC_TAIL"
  exit 1
fi
