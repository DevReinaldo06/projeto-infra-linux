#!/usr/bin/env bash
# =====================================================================
# rotacao_backups.sh - rotação dos backups do banco no file-lan
#
# Regras:
#   - Pasta: /compartilhado/backups, arquivos appdb_*.tar.gz
#   - Mantém os arquivos modificados nos últimos 7 dias.
#   - NUNCA deixa menos de 3 arquivos (se o banco ficar parado alguns
#     dias, ainda sobram backups).
#   - Remove primeiro os mais antigos e registra cada remoção em
#     /var/log/rotacao_backups.log com data e hora.
#   - Opção --simular: só mostra o que seria removido, sem apagar.
#   - flock impede duas execuções ao mesmo tempo.
#
# Uso:  sudo rotacao_backups.sh [--simular]
# Entrega: scripts/rotacao_backups.sh
# =====================================================================

# -e: para no primeiro erro; -u: erro em variável não definida;
# pipefail: um erro no meio de um pipe também conta como erro.
set -euo pipefail

# --- Configuração ----------------------------------------------------
PASTA="/compartilhado/backups"
PADRAO="appdb_*.tar.gz"
DIAS=7
MINIMO=3
LOG="/var/log/rotacao_backups.log"
TRAVA="/var/lock/rotacao_backups.lock"

# --- Argumentos ------------------------------------------------------
SIMULAR=0
case "${1:-}" in
    --simular) SIMULAR=1 ;;
    "")        ;;
    *) echo "Uso: $0 [--simular]" >&2; exit 2 ;;
esac

# --- Trava contra execução dupla ------------------------------------
# Abre o arquivo de trava no descritor 9 e tenta travá-lo sem esperar.
exec 9>"$TRAVA"
if ! flock -n 9; then
    echo "Outra rotação já está em andamento. Saindo." >&2
    exit 0
fi

# --- Função de log (só grava de verdade fora do modo simulação) ------
log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

# --- Verificações ----------------------------------------------------
if [[ ! -d "$PASTA" ]]; then
    echo "Pasta $PASTA não existe." >&2
    exit 1
fi

# --- Lista os arquivos do MAIS ANTIGO para o mais novo ---------------
# %T@ = data de modificação em segundos; sort -n ordena do menor (antigo)
# para o maior (novo); cut tira a data e deixa só o caminho.
mapfile -t ARQUIVOS < <(
    find "$PASTA" -maxdepth 1 -type f -name "$PADRAO" -printf '%T@ %p\n' \
    | sort -n | cut -d' ' -f2-
)

TOTAL=${#ARQUIVOS[@]}
LIMITE=$(( $(date +%s) - DIAS * 86400 ))   # tudo antes disso é "antigo"
REMOVIDOS=0

# --- Percorre do mais antigo ao mais novo ----------------------------
for arq in "${ARQUIVOS[@]}"; do
    # Regra de segurança: nunca deixar menos de MINIMO arquivos.
    if (( TOTAL <= MINIMO )); then
        break
    fi

    # Como a lista está em ordem, no primeiro arquivo recente já paramos.
    data_arq=$(stat -c %Y "$arq")
    if (( data_arq >= LIMITE )); then
        break
    fi

    if (( SIMULAR == 1 )); then
        echo "[SIMULAÇÃO] seria removido: $arq"
    else
        rm -f -- "$arq"
        log "REMOVIDO: $arq"
        echo "Removido: $arq"
    fi
    TOTAL=$(( TOTAL - 1 ))
    REMOVIDOS=$(( REMOVIDOS + 1 ))
done

# --- Resumo ----------------------------------------------------------
if (( SIMULAR == 1 )); then
    echo "[SIMULAÇÃO] $REMOVIDOS arquivo(s) seriam removidos; sobrariam $TOTAL."
else
    log "Rotação concluída: $REMOVIDOS removido(s), $TOTAL restante(s)."
    echo "Rotação concluída: $REMOVIDOS removido(s), $TOTAL restante(s)."
fi
