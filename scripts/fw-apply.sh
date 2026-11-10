#!/usr/bin/env bash
# fw-apply.sh - aplica um arquivo iptables-restore com desfazer automatico.
#
# COMO FUNCIONA:
#   1. valida a sintaxe (se estiver quebrado, nada e alterado);
#   2. salva as regras atuais em /root/fw-backup-DATA.rules;
#   3. arma um temporizador do systemd que restaura o backup sozinho;
#      ele roda FORA desta sessao, entao funciona mesmo se o SSH cair;
#   4. aplica o arquivo novo;
#   5. pede confirmacao: digitar SIM cancela o desfazer.
#
# Uso: sudo scripts/fw-apply.sh <arquivo.rules> [segundos, padrao 120]

set -euo pipefail

NOVO="${1:?Uso: $0 <arquivo.rules> [segundos]}"
ESPERA="${2:-120}"
BACKUP="/root/fw-backup-$(date +%Y%m%d-%H%M%S).rules"
UNIDADE="fw-rollback"

# exige root
[[ $EUID -eq 0 ]] || { echo 'Rode como root (sudo).'; exit 1; }

# o arquivo precisa existir
[[ -r "$NOVO" ]] || { echo "ERRO: nao consigo ler $NOVO"; exit 1; }

# o numero de segundos precisa ser inteiro
[[ "$ESPERA" =~ ^[0-9]+$ ]] || { echo 'ERRO: segundos deve ser um numero.'; exit 1; }

echo '[1/5] Validando sintaxe...'
iptables-restore --test < "$NOVO" || { echo 'ERRO: arquivo invalido. Nada foi alterado.'; exit 1; }

echo "[2/5] Salvando regras atuais em $BACKUP"
iptables-save > "$BACKUP"
if [[ ! -s "$BACKUP" ]]; then
  printf '*filter\n:INPUT ACCEPT [0:0]\n:FORWARD ACCEPT [0:0]\n:OUTPUT ACCEPT [0:0]\nCOMMIT\n' > "$BACKUP"
fi

echo "[3/5] Armando o desfazer automatico em ${ESPERA}s (independe da sua sessao)"
# limpa um temporizador antigo, se existir
systemctl stop "$UNIDADE.timer" "$UNIDADE.service" 2>/dev/null || true
systemd-run --quiet --unit="$UNIDADE" --on-active="${ESPERA}s" \
  /bin/sh -c "iptables-restore < $BACKUP"

echo "[4/5] Aplicando $NOVO"
if ! iptables-restore < "$NOVO"; then
  echo 'ERRO ao aplicar. Cancelando o desfazer; as regras anteriores continuam ativas.'
  systemctl stop "$UNIDADE.timer" 2>/dev/null || true
  exit 1
fi

echo "[5/5] Digite SIM em ate ${ESPERA} segundos para manter as regras"
if read -r -t "$ESPERA" RESP && [[ "$RESP" == "SIM" ]]; then
  systemctl stop "$UNIDADE.timer"
  echo "Regras mantidas. Backup em $BACKUP"
  echo 'Para sobreviver ao reboot: sudo netfilter-persistent save'
else
  echo 'Sem confirmacao: restaurando o backup...'
  iptables-restore < "$BACKUP"
  systemctl stop "$UNIDADE.timer" 2>/dev/null || true
fi
