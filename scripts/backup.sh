#!/bin/bash
set -e

LOG_FILE="/var/log/borg/borg-backup.log"
# Função para logar com timestamp
log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

log "Iniciando backup com Borgmatic..."

# O borgmatic detecta a variável BORG_PASSPHRASE automaticamente do ambiente
if /app/borg-env/bin/borgmatic create --verbosity 1 --stats | tee -a "$LOG_FILE"; then
  log "Backup concluído com sucesso."
else
  log "Erro: Backup falhou."
  exit 1
fi
