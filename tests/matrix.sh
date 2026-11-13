#!/usr/bin/env bash
# tests/matrix.sh - prova a matriz de firewall (R0 a R9).
#
# Uso:
#   bash tests/matrix.sh                  # roda no admin-lan (casos internos)
#   bash tests/matrix.sh --externo <IP>   # roda na maquina fisica (casos da WAN)
#
# Requisitos (modo normal):
#   - chave SSH carregada no agente:  eval "$(ssh-agent -s)"; ssh-add ~/.ssh/id_ed25519
#   - rotas do admin-lan para 10.0.1.0/24 e 10.0.3.0/24 via 10.0.2.1
#   - sudo sem senha no web-dmz (usado so para criar/remover o IP 10.0.1.99)
#
# Casos "abre" devem passar com o firewall ligado; casos "bloqueia" tambem.
# Com o firewall ainda liberado, os casos "bloqueia" FALHAM: isso e esperado.

set -u

# ---------- CONFIGURACAO ----------
SSH_USER=sysadmin
IFACE_WEB="enp0s3"
DOMINIO=empresa.local

IP_WEB=10.0.1.10
IP_DB=10.0.3.10
IP_FILE=10.0.2.10
GW_DMZ=10.0.1.1
GW_LAN=10.0.2.1
GW_DB=10.0.3.1
IP_EXTRA=10.0.1.99           # IP extra do web-dmz para provar a R5

VERDE=$'\e[32m'; VERM=$'\e[31m'; AMAR=$'\e[33m'; FIM=$'\e[0m'
TOTAL=0; FALHAS=0

# ---------- FUNCAO PRINCIPAL ----------
# caso <regra> <descricao> <abre|bloqueia> <local|web|db|arquivos> <comando>
caso() {
  local regra="$1" desc="$2" esperado="$3" onde="$4" cmd="$5" rc ip
  TOTAL=$((TOTAL+1))

  if [[ $onde == local ]]; then
    bash -c "$cmd" >/dev/null 2>&1; rc=$?
  else
    case $onde in
      web) ip=$IP_WEB ;; db) ip=$IP_DB ;; arquivos) ip=$IP_FILE ;;
      *) echo "${VERM}FALHOU${FIM} [$regra] $desc (destino invalido: $onde)"; FALHAS=$((FALHAS+1)); return ;;
    esac
    ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
        "$SSH_USER@$ip" "$cmd" >/dev/null 2>&1; rc=$?
    # 255 = falha do proprio SSH (VM fora do ar, chave, rota). Nao e resultado de firewall.
    if [[ $rc -eq 255 ]]; then
      echo "${VERM}FALHOU${FIM} [$regra] $desc (SSH para $onde falhou: infraestrutura, nao firewall)"
      FALHAS=$((FALHAS+1)); return
    fi
  fi

  if [[ $esperado == abre && $rc -eq 0 ]] || [[ $esperado == bloqueia && $rc -ne 0 ]]; then
    echo "${VERDE}PASSOU${FIM} [$regra] $desc"
  else
    echo "${VERM}FALHOU${FIM} [$regra] $desc (esperado: $esperado, codigo: $rc)"
    FALHAS=$((FALHAS+1))
  fi
}

resumo() {
  echo
  echo "Total: $TOTAL | Falhas: $FALHAS"
  [[ $FALHAS -eq 0 ]] || exit 1
}

# ---------- MODO EXTERNO (maquina fisica, fora da LAN) ----------
if [[ "${1:-}" == "--externo" ]]; then
  WAN="${2:?Uso: $0 --externo <IP-WAN-do-fw-gw>}"
  echo "== Casos vindos da WAN ($WAN) =="
  caso R1 "WAN -> web-dmz porta 80 (DNAT)"  abre local "nc -z -w3 $WAN 80"
  caso R1 "WAN -> web-dmz porta 443 (DNAT)" abre local "nc -z -w3 $WAN 443"
  # Para exercitar a R5 (FORWARD) pela WAN, a maquina fisica precisa de uma rota:
  #   Linux:   sudo ip route add 10.0.3.10/32 via $WAN
  #   Windows: route add 10.0.3.10 mask 255.255.255.255 $WAN
  # Sem a rota, o destino e o proprio fw-gw (INPUT) e a R5 nao conta pacotes.
  caso R5 "WAN -> db-zone 5432 (precisa da rota acima)" bloqueia local "nc -z -w3 $IP_DB 5432"
  resumo
  exit 0
fi

# ---------- PREPARO: IP extra no web-dmz (para a R5) ----------
PODE_R5=1
if [[ "$IFACE_WEB" == "PREENCHER" ]]; then
  echo "${AMAR}AVISO${FIM}: IFACE_WEB nao preenchido; o caso R5 sera marcado como FALHOU."
  PODE_R5=0
else
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$IP_WEB" \
    "sudo -n ip addr del $IP_EXTRA/24 dev $IFACE_WEB 2>/dev/null; sudo -n ip addr add $IP_EXTRA/24 dev $IFACE_WEB" \
    >/dev/null 2>&1 || { echo "${AMAR}AVISO${FIM}: nao consegui criar $IP_EXTRA no web-dmz (SSH, sudo sem senha ou interface errada)."; PODE_R5=0; }
  # remove o IP extra ao sair, mesmo com erro ou Ctrl+C
  trap 'ssh -o BatchMode=yes -o ConnectTimeout=5 '"$SSH_USER@$IP_WEB"' "sudo -n ip addr del '"$IP_EXTRA"'/24 dev '"$IFACE_WEB"'" >/dev/null 2>&1' EXIT
fi

# ---------- CASOS QUE DEVEM FUNCIONAR ----------
echo "== Devem ABRIR =="
caso R2 "web-dmz -> db-zone 5432"                 abre web      "nc -z -w3 $IP_DB 5432"
caso R3 "LAN (admin) -> file-lan 445"             abre local    "nc -z -w3 $IP_FILE 445"
caso R3 "LAN (admin) -> file-lan 139"             abre local    "nc -z -w3 $IP_FILE 139"
caso R4 "admin -> SSH no fw-gw"                   abre local    "nc -z -w3 $GW_LAN 22"
caso R4 "admin -> SSH no web-dmz"                 abre local    "nc -z -w3 $IP_WEB 22"
caso R4 "admin -> SSH no db-zone"                 abre local    "nc -z -w3 $IP_DB 22"
caso R4 "admin -> SSH no file-lan"                abre local    "nc -z -w3 $IP_FILE 22"
caso R6 "db-zone -> file-lan 445 (backup)"        abre db       "nc -z -w3 $IP_FILE 445"
caso R7 "DNS da DMZ no gateway"                   abre web      "dig @$GW_DMZ +short +time=2 +tries=1 web.$DOMINIO | grep -q ."
caso R7 "DNS da DB no gateway"                    abre db       "dig @$GW_DB +short +time=2 +tries=1 web.$DOMINIO | grep -q ."
caso R7 "DNS da LAN no gateway"                   abre arquivos "dig @$GW_LAN +short +time=2 +tries=1 web.$DOMINIO | grep -q ."
# R9 roda no file-lan porque o admin-lan sai pela NAT, nao pelo fw-gw
caso R9 "LAN (via file-lan) -> internet 443"      abre arquivos "curl --max-time 3 -sI https://example.com"

# ---------- CASOS QUE DEVEM FALHAR ----------
echo "== Devem BLOQUEAR =="
if [[ $PODE_R5 -eq 1 ]]; then
  caso R5 "web-dmz com IP $IP_EXTRA -> db 5432"   bloqueia web   "nc -z -w3 -s $IP_EXTRA $IP_DB 5432"
else
  TOTAL=$((TOTAL+1)); FALHAS=$((FALHAS+1))
  echo "${VERM}FALHOU${FIM} [R5] web-dmz com IP extra -> db 5432 (pre-requisito nao atendido)"
fi
caso matriz "web-dmz -> file-lan 445"             bloqueia web  "nc -z -w3 $IP_FILE 445"
caso matriz "DMZ -> LAN porta 22"                 bloqueia web  "nc -z -w3 $IP_FILE 22"
caso matriz "DMZ -> LAN porta 80"                 bloqueia web  "nc -z -w3 $IP_FILE 80"
caso matriz "DMZ -> LAN porta 443"                bloqueia web  "nc -z -w3 $IP_FILE 443"
caso matriz "web-dmz -> SSH no fw-gw (so admin)"  bloqueia web  "nc -z -w3 $GW_DMZ 22"
caso matriz "db-zone -> SSH no fw-gw (so admin)"  bloqueia db   "nc -z -w3 $GW_DB 22"
caso matriz "file-lan -> SSH no fw-gw (so admin)" bloqueia arquivos "nc -z -w3 $GW_LAN 22"

echo
echo "(Casos da WAN: rode na maquina fisica com --externo <IP-WAN>.)"
resumo
