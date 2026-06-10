#!/bin/bash
set -e
. /scripts/common.sh

ensrue_dirs
ensure_files

log "Verificando repositório Borg..." "$BOOTSTRAP_LOG"

if ! borg info -r "$REPO" >/dev/null 2>&1; then
  log "Repositório não existe. Inicializando..." "$BOOTSTRAP_LOG"
  borg repo-create -e repokey-blake3-aes-ocb -r "$REPO"
  log "Repositório inicializado." "$BOOTSTRAP_LOG"
  
  log "Exportando chaves..." "$BOOTSTRAP_LOG"
  borg key export -r "$REPO" "$KEYDIR/repository.key"
  borg key export -r "$REPO" --paper "$KEYDIR/repository-paper.txt"
  borg key export -r "$REPO" --qr-html "$KEYDIR/repository-qr.html"
  log "Chaves exportadas." "$BOOTSTRAP_LOG"
else
  log "Repositório já existe. Pulando init." "$BOOTSTRAP_LOG"
fi

log "Configuração concluída. Iniciando Supercronic..." "$BOOTSTRAP_LOG"

# O supercronic assume o controle, herdando todo o ambiente do container
exec supercronic /etc/cron.d/supercronic.conf
