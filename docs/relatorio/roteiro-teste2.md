# Roteiro falado do Teste 2 (3 minutos)

**O que provamos:** "O banco não aceita conexão direta de quem não é o servidor web."

## Preparação
- fw-gw: `sudo iptables -Z FORWARD` e, em outra janela, `watch -n1 'sudo iptables -L FORWARD -v -n | grep R5'`.
- web-dmz: `sudo ip addr add 10.0.1.99/24 dev <IFACE_WEB>` (o `matrix.sh` faz isso sozinho).
- Windows (PowerShell como administrador): descobrir o IP da WAN com `ip -br a show enp0s3` no fw-gw.

## Roteiro
| Tempo | Ação | Fala |
|---|---|---|
| 0:00 | Abrir | "O banco não aceita conexão direta de quem não é o servidor web." |
| 0:20 | web-dmz: `nc -zv -w3 10.0.3.10 5432` | "Do IP oficial do web a conexão funciona: é a R2." (succeeded) |
| 0:50 | web-dmz: `nc -zv -w3 -s 10.0.1.99 10.0.3.10 5432` | "Com outro IP da DMZ a conexão não é recusada, ela trava até o tempo esgotar." (timed out) |
| 1:30 | fw-gw: `sudo iptables -L FORWARD -v -n \| grep R5` | "O contador da R5 subiu: o fw-gw registrou e descartou. A R2 vem antes da R5." |
| 2:00 | Windows: `route add 10.0.3.10 mask 255.255.255.255 <IP-WAN>`, `Test-NetConnection 10.0.3.10 -Port 5432`, `route delete 10.0.3.10` | "Da internet, mesmo resultado. Demora uns 20 s pelo timeout." |
| 2:30 | `bash tests/matrix.sh` | "A suíte prova o que deve abrir e o que deve bloquear." |
| 2:50 | Fechar | "O `pg_hba.conf` é uma segunda barreira, independente do firewall." |

## DROP x REJECT
O DROP descarta em silêncio, por isso o cliente espera o tempo esgotar. O REJECT responderia "recusado" na hora. Em borda usamos DROP para não confirmar que a porta existe e para atrasar varreduras. O custo é um diagnóstico legítimo mais lento.

## Perguntas prováveis
- **Por que R2 antes de R5?** O iptables para na primeira regra que casa; se a R5 viesse antes, o web oficial também seria barrado.
- **Por que ESTABLISHED,RELATED primeiro?** Firewall stateful: a maior parte do tráfego é resposta a algo já liberado.
- **DNAT x MASQUERADE?** DNAT troca o destino; MASQUERADE troca a origem.
- **DROP sem liberar o SSH?** A sessão cai; por isso o `fw-apply.sh` arma um desfazer automático fora da sessão.
- **Web invadido, o que o invasor alcança?** Só o que a matriz permite a partir de 10.0.1.10: o banco na 5432 (limitado pelo `pg_hba.conf`) e o DNS do fw-gw.
- **Janela de instalação (R8):** `fw-provisioning.sh on 15` antes das roles que instalam pacote; a role `firewall` roda por último e seu reload fecha a janela.

## Plano B
Gravar em vídeo um ensaio completo e mostrá-lo se a demonstração falhar ao vivo.
