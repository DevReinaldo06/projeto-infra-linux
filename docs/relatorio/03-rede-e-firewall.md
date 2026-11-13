# 3. Rede e firewall

## 3.1 Tabelas de roteamento

Saídas reais, coletadas em 13/11/2026.

### fw-gw (`ip route`)

```
default via 192.168.15.1 dev enp0s3 proto dhcp src 192.168.15.15 metric 100
10.0.1.0/24 dev enp0s8 proto kernel scope link src 10.0.1.1
10.0.2.0/24 dev enp0s9 proto kernel scope link src 10.0.2.1
10.0.3.0/24 dev enp0s10 proto kernel scope link src 10.0.3.1
192.168.15.0/24 dev enp0s3 proto kernel scope link src 192.168.15.15 metric 100
192.168.15.1 dev enp0s3 proto dhcp scope link src 192.168.15.15 metric 100
```

O `fw-gw` tem uma rota direta para cada zona (rotas `kernel`, criadas pelos IPs das interfaces) e uma rota padrão pela WAN. O encaminhamento de pacotes está ativo:

```
net.ipv4.ip_forward = 1
```

### admin-lan (`ip route`)

```
default via 10.0.2.1 dev enp0s3
10.0.1.0/24 via 10.0.2.1 dev enp0s3 proto static
10.0.2.0/24 dev enp0s3 proto kernel scope link src 10.0.2.50
10.0.3.0/24 via 10.0.2.1 dev enp0s3 proto static
```

### web-dmz (`ip route`)

```
default via 10.0.1.1 dev enp0s3 proto static
10.0.1.0/24 dev enp0s3 proto kernel scope link src 10.0.1.10
```

### db-zone (`ip route`)

```
default via 10.0.3.1 dev enp0s8
10.0.3.0/24 dev enp0s8 proto kernel scope link src 10.0.3.10
```

Todos os servidores usam o `fw-gw` como gateway da própria zona. Na db-zone, a rota padrão foi adicionada manualmente na integração (`ip route add`); a versão permanente deve estar no Netplan da VM (ver limitações na seção 9).

## 3.2 NAT e encaminhamento

O `fw-gw` faz `MASQUERADE` na interface WAN (`enp0s3`) para que as zonas internas acessem a internet (instalação de pacotes). A tarefa correspondente está na role Ansible `gateway` e é idempotente.

## 3.3 Mapeamento de portas

| Porta | Protocolo | Serviço | Host | Zona | Quem acessa |
|---|---|---|---|---|---|
| 80 | TCP | HTTP (redireciona para HTTPS) | web-dmz | DMZ | WAN (via DNAT no fw-gw) |
| 443 | TCP | HTTPS (Nginx) | web-dmz | DMZ | WAN (via DNAT no fw-gw) |
| 8000 | TCP | API FastAPI | web-dmz | DMZ | Só `127.0.0.1` (Nginx local) |
| 5432 | TCP | PostgreSQL | db-zone | DB Zone | Só web-dmz (10.0.1.10) |
| 139, 445 | TCP | Samba | file-lan | LAN | LAN (10.0.2.0/24) e, na 445, db-zone (backup) |
| 22 | TCP | SSH | todas | todas | Só admin-lan (10.0.2.50) |
| 53 | UDP/TCP | DNS (Bind9) | fw-gw | todas | Todas as zonas |
| 67, 68 | UDP | DHCP | fw-gw | LAN | Clientes da LAN |

## 3.4 Matriz de firewall (R0 a R9)

O `fw-gw` foi projetado para aplicar política padrão `DROP` em `INPUT` e `FORWARD`, com `OUTPUT` liberado. A ordem importa: R2 vem antes de R5.

| # | Origem | Destino | Porta/protocolo | Ação | Justificativa |
|---|---|---|---|---|---|
| R0 | Qualquer | Qualquer | `ESTABLISHED,RELATED` | ACCEPT | Respostas de conexões já autorizadas (firewall stateful) |
| R1 | WAN | web-dmz 10.0.1.10 | 80/tcp, 443/tcp | ACCEPT (DNAT + FORWARD) | Acesso público ao site |
| R2 | web-dmz 10.0.1.10 | db-zone 10.0.3.10 | 5432/tcp | ACCEPT (antes de R5) | Única origem autorizada a falar com o banco |
| R3 | LAN 10.0.2.0/24 | file-lan 10.0.2.10 | 139/tcp, 445/tcp | ACCEPT (regra de host) | Acesso a pastas e backups; não passa pelo fw-gw (mesmo segmento) |
| R4 | admin-lan 10.0.2.50 | Todas as zonas e fw-gw | 22/tcp | ACCEPT | Administração restrita por chave SSH |
| R5 | DMZ e WAN | DB Zone 10.0.3.0/24 | Qualquer | DROP com LOG | Impede ataque direto ao banco; o LOG permite provar o bloqueio nos contadores |
| R6 | db-zone 10.0.3.10 | file-lan 10.0.2.10 | 445/tcp | ACCEPT | Envio do backup diário ao servidor de arquivos |
| R7 | DMZ, LAN e DB | fw-gw (IP da própria zona) | 53/udp e tcp; 67-68/udp só na LAN | ACCEPT | DNS interno para todos e DHCP para a LAN |
| R8 | DMZ e DB | WAN | 80/tcp, 443/tcp, 53 | ACCEPT com MASQUERADE (chain `PROVISION`) | `apt` precisa de internet; a chain só fica ligada na janela de instalação |
| R9 | LAN | WAN | 80/tcp, 443/tcp, 53 | ACCEPT com MASQUERADE | Atualizações e acesso da estação de administração |

**Como R5 é provado sem bloquear a aplicação:** o `web-dmz` ganha um IP secundário temporário (10.0.1.99). O teste `nc -s 10.0.1.99 10.0.3.10 5432` deve falhar, enquanto a aplicação, com origem 10.0.1.10, continua gravando no banco. A segunda camada é o `pg_hba.conf`, que também só aceita 10.0.1.10.

**Regras no repositório:** `configs/fw-gw/iptables.rules` (escrito pelo Eduardo). No `iptables.rules`, o SSH para o `fw-gw` só é aceito de 10.0.2.50/32 pela interface da LAN (R4).

**Estado na data deste relatório:** as regras estão escritas e o ambiente foi integrado com o firewall ainda liberado, como previsto no plano (o DROP só é ligado depois que tudo funciona sem ele). A aplicação do DROP e a execução de `tests/matrix.sh` ficam registradas em `docs/evidencias/firewall/`.
