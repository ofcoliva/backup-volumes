#!/bin/bash
set -e

LOG_FILE="/var/log/borg/borg-backup.log"
REPO="/volumes/backup-local-borg"
KEYDIR="/volumes/borg-keys"

# Função auxiliar para log com timestamp
log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

mkdir -p "$KEYDIR" /var/log/borg

log "Verificando repositório Borg..."

if ! borg info -r "$REPO" >/dev/null 2>&1; then
  log "Repositório não existe. Inicializando..."
  borg repo-create -e repokey-blake3-aes-ocb -r "$REPO"
  log "Repositório inicializado."
  
  log "Exportando chaves..."
  borg key export -r "$REPO" "$KEYDIR/repository.key"
  borg key export -r "$REPO" --paper "$KEYDIR/repository-paper.txt"
  borg key export -r "$REPO" --qr-html "$KEYDIR/repository-qr.html"
  log "Chaves exportadas."
else
  log "Repositório já existe. Pulando init."
fi

log "Configuração concluída. Iniciando Supercronic..."

# O supercronic assume o controle, herdando todo o ambiente do container
exec supercronic /etc/cron.d/supercronic.conf
