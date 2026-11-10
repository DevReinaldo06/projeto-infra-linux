#!/usr/bin/env bash
# fw-provisioning.sh - janela de instalacao (R8) do fw-gw.
#
# Abre ou fecha a saida da DMZ (10.0.1.10) e da DB Zone (10.0.3.10) para a
# internet (80/443/53), usando a chain PROVISION da tabela filter.
# O MASQUERADE ja existe fixo na tabela nat; aqui so se mexe no FORWARD.
#
# Uso: sudo fw-provisioning.sh on [minutos] | off | status
#   on [minutos]  abre a janela; se informar minutos, fecha sozinha depois
#   off           fecha a janela
#   status        mostra as regras e os contadores

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo 'Rode como root (sudo).'; exit 1; }

WAN=enp0s3                       # interface WAN do fw-gw
SERVIDORES="10.0.1.10 10.0.3.10" # web-dmz e db-zone
UNIDADE=fw-provisioning-off

case "${1:-}" in
  on)
    MIN="${2:-}"
    if [[ -n "$MIN" && ! "$MIN" =~ ^[0-9]+$ ]]; then
      echo 'ERRO: minutos deve ser um numero.'; exit 1
    fi
    # limpa antes: rodar "on" duas vezes nao duplica regras
    iptables -F PROVISION
    for ip in $SERVIDORES; do
      iptables -A PROVISION -s "$ip" -o "$WAN" -p tcp -m multiport --dports 80,443,53 \
        -m comment --comment R8 -j ACCEPT
      iptables -A PROVISION -s "$ip" -o "$WAN" -p udp --dport 53 \
        -m comment --comment R8 -j ACCEPT
    done
    echo 'Janela R8 ABERTA.'
    # cancela um fechamento automatico anterior
    systemctl stop "$UNIDADE.timer" 2>/dev/null || true
    if [[ -n "$MIN" ]]; then
      systemd-run --quiet --unit="$UNIDADE" --on-active="${MIN}m" "$(readlink -f "$0")" off
      echo "Fecha sozinha em ${MIN} minuto(s)."
    else
      echo 'Lembre de rodar: off'
    fi
    ;;
  off)
    iptables -F PROVISION
    systemctl stop "$UNIDADE.timer" 2>/dev/null || true
    echo 'Janela R8 FECHADA.'
    ;;
  status)
    iptables -L PROVISION -v -n --line-numbers
    ;;
  *)
    echo 'Uso: fw-provisioning.sh on [minutos] | off | status'; exit 1
    ;;
esac
