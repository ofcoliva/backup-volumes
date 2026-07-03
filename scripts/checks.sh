#!/bin/bash
set -e
. /scripts/common.sh

LOG_MARK="BORGMATIC_CHECK_$(date '+%Y%m%dT%H%M%S')"
log "$LOG_MARK" "$BORGMATIC_LOG"
log "Iniciando verificações do repositório Borg..." "$BORGMATIC_LOG"

CHECKS_FAILED=0
CHECKS_REPORT=""

run_check() {
    local name="$1"
    local mark="CHECK_${name^^}_$(date '+%Y%m%dT%H%M%S')"
    log "$mark" "$BORGMATIC_LOG"
    log "Iniciando check: $name" "$BORGMATIC_LOG"

    borgmatic check \
        --only "$name" \
        --verbosity 1 \
        --no-color 2>&1 | tee -a "$BORGMATIC_LOG"

    local STATUS="${PIPESTATUS[0]}"
    BORGMATIC_TAIL="$(sed -n "/$mark/,\$p" "$BORGMATIC_LOG" | tail -6)"

    if [[ "$STATUS" -eq 0 ]]; then
        log "✔ check $name: OK" "$BORGMATIC_LOG"
        CHECKS_REPORT+="✔ $name"$'\n'"$BORGMATIC_TAIL"$'\n\n'
    else
        log "✘ check $name: FALHOU (status: $STATUS)" "$BORGMATIC_LOG"
        CHECKS_REPORT+="✘ $name"$'\n'"$BORGMATIC_TAIL"$'\n\n'
        (( CHECKS_FAILED++ )) || true
    fi
}

# Equivalente ao checks: do borgmatic
run_check "repository"
run_check "archives"
run_check "extract"
run_check "data"

# spot tem frequência de 2 semanas — só roda se for dia de semana par
WEEK_NUMBER="$(date '+%V')"
if (( WEEK_NUMBER % 2 == 0 )); then
    log "Semana $WEEK_NUMBER — executando check spot (frequência: 2 semanas)" "$BORGMATIC_LOG"
    run_check "spot"
else
    log "Semana $WEEK_NUMBER — check spot ignorado (frequência: 2 semanas)" "$BORGMATIC_LOG"
    CHECKS_REPORT+="— spot: ignorado esta semana"$'\n\n'
fi

# Resultado final
FULL_TAIL="$(sed -n "/$LOG_MARK/,\$p" "$BORGMATIC_LOG" | tail -10)"

if [[ "$CHECKS_FAILED" -eq 0 ]]; then
    log "Todas as verificações concluídas com sucesso." "$BORGMATIC_LOG"
    # notify "✔ Borg: Verificações concluídas" \
        # "$CHECKS_REPORT"$'\n'"— Resumo —"$'\n'"$FULL_TAIL"
else
    log "Verificações concluídas com $CHECKS_FAILED falha(s)." "$BORGMATIC_LOG"
    # notify "✘ Borg: $CHECKS_FAILED verificação(ões) falharam" \
        # "$CHECKS_REPORT"$'\n'"— Resumo —"$'\n'"$FULL_TAIL"
    exit 1
fi