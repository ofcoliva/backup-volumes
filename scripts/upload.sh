#!/bin/bash
set -e
. /scripts/common.sh

LOG_MARK="RCLONE_START_$(date '+%Y%m%dT%H%M%S')"
log "$LOG_MARK" "$RCLONE_LOG"
log "Iniciando Upload dos backups criados" "$RCLONE_LOG"

# OTIMIZAÇÕES ADICIONADAS AQUI:
# --drive-chunk-size 64M (Padrão é 8M. Aumentar isso acelera muito os arquivos grandes)
# --transfers 8 (Padrão é 4. Faz upload de mais arquivos simultaneamente)
# --checkers 16 (Padrão é 8. Verifica mais arquivos simultaneamente)
# Removido: --checksum (Foi removido do sync porque você já faz um 'rclone check' logo depois. Fazer isso no sync apenas dobra o uso do seu disco à toa).

rclone sync "$REPO" "$RCLONE_DEST" \
    --config "$RCLONE_CONFIG" \
    --fast-list \
    --drive-chunk-size 64M \
    --transfers 8 \
    --checkers 16 \
    -v 2>&1 | tee -a "$RCLONE_LOG"

SYNC_STATUS="${PIPESTATUS[0]}"

if [[ "$SYNC_STATUS" -eq 0 ]]; then
    log "Rclone: Upload finalizado com sucesso" "$RCLONE_LOG"

    # tail do sync captura antes do check concatenar mais linhas
    RCLONE_SYNC_TAIL="$(sed -n "/$LOG_MARK/,\$p" "$RCLONE_LOG" | tail -6)"

    log "Iniciando verificação de integridade..." "$RCLONE_LOG"
    CHECK_MARK="RCLONE_CHECK_$(date '+%Y%m%dT%H%M%S')"
    log "$CHECK_MARK" "$RCLONE_LOG"

    rclone check "$REPO" "$RCLONE_DEST" \
        --config "$RCLONE_CONFIG" \
        --fast-list \
        --checksum \
        --transfers 8 \
        --checkers 16 \
        --one-way \
        -v 2>&1 | tee -a "$RCLONE_LOG"

    CHECK_STATUS="${PIPESTATUS[0]}"

    if [[ "$CHECK_STATUS" -eq 0 ]]; then
        log "Rclone: Verificação de integridade concluída com sucesso." "$RCLONE_LOG"
        
        # Tail do check — isolado pelo próprio mark
        RCLONE_CHECK_TAIL="$(sed -n "/$CHECK_MARK/,\$p" "$RCLONE_LOG" | tail -6)"

        notify "Rclone: Backup e verificação concluídos" \
            "— Sync —"$'\n'"$RCLONE_SYNC_TAIL"$'\n\n'"— Check —"$'\n'"$RCLONE_CHECK_TAIL"
    else
        log "Rclone: Falha na verificação de integridade. Status: $CHECK_STATUS." "$RCLONE_LOG"
        notify "Rclone: Falha na verificação de integridade" \
            "— Sync —"$'\n'"$RCLONE_SYNC_TAIL"$'\n\n'"— Check —"$'\n'"$RCLONE_CHECK_TAIL"
        exit 1
    fi

else
    RCLONE_SYNC_TAIL="$(sed -n "/$LOG_MARK/,\$p" "$RCLONE_LOG" | tail -6)"
    log "Rclone: Erro — o upload falhou. Status: $SYNC_STATUS." "$RCLONE_LOG"
    notify "Rclone: Upload falhou" \
        "— Sync —"$'\n'"$RCLONE_SYNC_TAIL"
    exit 1
fi
