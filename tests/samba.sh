#!/usr/bin/env bash
# =====================================================================
# tests/samba.sh - teste do servidor de arquivos (file-lan)
#
# Roda no admin-lan e confere:
#   1) a matriz de permissões (usuário x compartilhamento);
#   2) a cota (ana grava 150 MB em publico e deve falhar por cota);
#   3) o repquota mostrando a ana no limite (via ssh);
#   4) que o web-dmz NÃO alcança a porta 445 do file-lan (via ssh).
#
# As senhas vêm de variáveis de ambiente, nunca deste arquivo:
#   SENHA_ANA, SENHA_BRUNO, SENHA_CARLA, SENHA_SVC
#
# Variáveis opcionais:
#   SERVIDOR  servidor Samba   (padrão: arquivos.empresa.local)
#   SSH_USER  usuário do ssh   (padrão: sysadmin)
#   HOST_SSH  host do file-lan para o ssh (padrão: o mesmo do SERVIDOR)
#   WEB_HOST  host do web-dmz  (padrão: web.empresa.local)
#
# Saída: PASSOU / FALHOU / PULOU por caso. Código de saída 1 se algo
# falhar. "PULOU" (ssh indisponível) não conta como falha.
# Entrega: tests/samba.sh
# =====================================================================

# -u: erro se usar variável não definida. Não usamos -e de propósito:
# um caso que falha não pode interromper os outros.
set -u

SERVIDOR="${SERVIDOR:-arquivos.empresa.local}"
SSH_USER="${SSH_USER:-sysadmin}"
HOST_SSH="${HOST_SSH:-$SERVIDOR}"
WEB_HOST="${WEB_HOST:-web.empresa.local}"
ARQ_TESTE="/tmp/teste.txt"
ARQ_GRANDE="/tmp/grande_150m.bin"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5)

# --- Cores e contadores ---------------------------------------------
VERDE=$'\033[32m'; VERMELHO=$'\033[31m'; AMARELO=$'\033[33m'; NORMAL=$'\033[0m'
OK=0; FALHA=0; PULOU=0

passou() { printf '%sPASSOU%s  %s\n' "$VERDE" "$NORMAL" "$1"; OK=$((OK + 1)); }
falhou() { printf '%sFALHOU%s  %s\n' "$VERMELHO" "$NORMAL" "$1"; FALHA=$((FALHA + 1)); }
pulou()  { printf '%sPULOU %s  %s\n' "$AMARELO" "$NORMAL" "$1"; PULOU=$((PULOU + 1)); }

# --- Pré-requisitos ---------------------------------------------------
if ! command -v smbclient >/dev/null 2>&1; then
    echo "smbclient não está instalado. Rode: sudo apt install -y smbclient" >&2
    exit 2
fi

for v in SENHA_ANA SENHA_BRUNO SENHA_CARLA SENHA_SVC; do
    if [[ -z "${!v:-}" ]]; then
        echo "Variável $v não definida. Exemplo: read -rs $v; export $v" >&2
        exit 2
    fi
done

declare -A SENHAS=(
    [ana]="$SENHA_ANA"
    [bruno]="$SENHA_BRUNO"
    [carla]="$SENHA_CARLA"
    [svc_backup]="$SENHA_SVC"
)

# Arquivos temporários locais são apagados ao sair.
trap 'rm -f "$ARQ_TESTE" "$ARQ_GRANDE"' EXIT
echo "teste" > "$ARQ_TESTE"

# Executa um comando do smbclient e devolve toda a saída (texto + erros).
smb() {
    local usuario="$1" share="$2" comando="$3"
    smbclient "//$SERVIDOR/$share" -U "${usuario}%${SENHAS[$usuario]}" -c "$comando" 2>&1
}

# Descobre o acesso real: none (sem acesso), ro (só ler), rw (ler e
# escrever), login (senha recusada) ou erro (resposta inesperada).
acesso_real() {
    local usuario="$1" share="$2" saida

    saida=$(smb "$usuario" "$share" "ls")
    if grep -q "NT_STATUS_LOGON_FAILURE" <<<"$saida"; then echo login; return; fi
    if grep -q "NT_STATUS_ACCESS_DENIED" <<<"$saida"; then echo none; return; fi
    if ! grep -q "blocks of size" <<<"$saida"; then echo erro; return; fi

    # Conseguiu listar: agora tenta gravar um arquivo pequeno.
    saida=$(smb "$usuario" "$share" "put $ARQ_TESTE teste_${usuario}.txt")
    if grep -q "putting file" <<<"$saida"; then
        # Gravou: apaga o arquivo de teste e conclui que pode escrever.
        smb "$usuario" "$share" "del teste_${usuario}.txt" >/dev/null
        echo rw
    elif grep -q "NT_STATUS_ACCESS_DENIED" <<<"$saida"; then
        echo ro
    else
        echo erro
    fi
}

descricao() {
    case "$1" in
        rw)    echo "ler e escrever" ;;
        ro)    echo "só ler" ;;
        none)  echo "sem acesso" ;;
        login) echo "login recusado" ;;
        *)     echo "resposta inesperada" ;;
    esac
}

# --- 1) Matriz de permissões -----------------------------------------
echo "== 1) Matriz de permissões em //$SERVIDOR =="

declare -A ESPERADO=(
    [ana:publico]=rw   [ana:projetos]=rw   [ana:backups]=none
    [bruno:publico]=rw [bruno:projetos]=none [bruno:backups]=none
    [carla:publico]=rw [carla:projetos]=ro [carla:backups]=ro
    [svc_backup:publico]=none [svc_backup:projetos]=none [svc_backup:backups]=rw
)

for usuario in ana bruno carla svc_backup; do
    for share in publico projetos backups; do
        esperado="${ESPERADO[$usuario:$share]}"
        real=$(acesso_real "$usuario" "$share")
        texto="$usuario em $share: esperado '$(descricao "$esperado")', obtido '$(descricao "$real")'"
        if [[ "$real" == "$esperado" ]]; then passou "$texto"; else falhou "$texto"; fi
    done
done

# --- 2) Cota: ana grava 150 MB em publico ----------------------------
echo
echo "== 2) Cota de disco =="
dd if=/dev/zero of="$ARQ_GRANDE" bs=1M count=150 status=none

saida=$(smb ana publico "put $ARQ_GRANDE grande_ana.bin")
if grep -qiE "NT_STATUS_DISK_FULL|NT_STATUS_QUOTA_EXCEEDED|quota" <<<"$saida"; then
    passou "ana não consegue gravar 150 MB em publico (cota de 100 MB)"
else
    falhou "a gravação de 150 MB não foi barrada pela cota"
fi

# --- 3) repquota via ssh (antes de apagar o arquivo parcial) --------
echo
echo "== 3) repquota no file-lan =="
if ssh "${SSH_OPTS[@]}" "$SSH_USER@$HOST_SSH" true >/dev/null 2>&1; then
    rep=$(ssh "${SSH_OPTS[@]}" "$SSH_USER@$HOST_SSH" "sudo -n repquota -us /compartilhado" 2>&1)
    linha_ana=$(grep -E '^ana[[:space:]]' <<<"$rep" | head -1)
    if [[ -n "$linha_ana" ]]; then
        passou "repquota mostra a ana no limite: $linha_ana"
    else
        falhou "repquota não mostrou a ana na tabela de usuários"
    fi
else
    pulou "ssh $SSH_USER@$HOST_SSH indisponível (chave SSH ou rede ainda não configuradas)"
fi

# Limpa o arquivo parcial que a cota deixou no servidor.
smb ana publico "del grande_ana.bin" >/dev/null

# --- 4) web-dmz NÃO pode alcançar a porta 445 ------------------------
echo
echo "== 4) web-dmz não alcança a porta 445 do file-lan =="
ssh "${SSH_OPTS[@]}" "$SSH_USER@$WEB_HOST" "nc -zw3 $SERVIDOR 445" >/dev/null 2>&1
rc=$?
case $rc in
    0) falhou "o web-dmz alcançou a porta 445 (o firewall deveria bloquear)" ;;
    1) passou "o web-dmz NÃO alcança a porta 445 (bloqueado)" ;;
    *) pulou "ssh para $WEB_HOST indisponível ou nc ausente (código $rc)" ;;
esac

# --- Resumo ----------------------------------------------------------
echo
printf 'Resumo: %s%d passaram%s, %s%d falharam%s, %s%d pulados%s\n' \
    "$VERDE" "$OK" "$NORMAL" "$VERMELHO" "$FALHA" "$NORMAL" "$AMARELO" "$PULOU" "$NORMAL"

if (( FALHA > 0 )); then
    exit 1
fi
exit 0
