# 2. Topologia e plano de endereçamento

## 2.1 Objetivo

Descrever como as cinco máquinas virtuais do projeto estão organizadas em três zonas de rede isoladas (DMZ, LAN e DB Zone), todas ligadas a um único roteador/firewall (`fw-gw`), e documentar o endereçamento de cada host.

## 2.2 Descrição da topologia

A infraestrutura usa Ubuntu Server 24.04 LTS em todas as VMs, executadas no VirtualBox. Todo o tráfego entre zonas passa pelo `fw-gw`. As únicas ligações laterais autorizadas entre servidores são `web-dmz → db-zone` na porta 5432 (regra R2) e `db-zone → file-lan` na porta 445 (regra R6).

O `fw-gw` tem quatro adaptadores de rede:

| Adaptador | Interface (confirmada com `ip -br a`) | Rede do hipervisor | Função | Endereço |
|---|---|---|---|---|
| 1 | `enp0s3` | Bridge | WAN | 192.168.15.15/24 (DHCP do roteador doméstico) |
| 2 | `enp0s8` | `rede-dmz` (interna) | DMZ | 10.0.1.1/24 |
| 3 | `enp0s9` | `rede-lan` (interna) | LAN | 10.0.2.1/24 |
| 4 | `enp0s10` | `rede-db` (interna) | DB Zone | 10.0.3.1/24 |

A WAN usa o modo Bridge porque a rede NAT padrão do VirtualBox usa 10.0.2.0/24, a mesma faixa da LAN do projeto, o que criaria dois caminhos para a mesma rede.

![Topologia: 3 zonas, 1 firewall, 5 VMs](../topologia.png)

*Figura 2.1 – Topologia do projeto (arquivo `docs/topologia.png`).*

## 2.3 Tabela de endereçamento

| Host | Zona | IP | Gateway | Como recebe o IP | Serviços | Nome (`empresa.local`) |
|---|---|---|---|---|---|---|
| fw-gw | Borda | WAN 192.168.15.15; 10.0.1.1, 10.0.2.1, 10.0.3.1 | n/a | Netplan (WAN por DHCP, zonas estáticas) | iptables, NAT, DHCP, Bind9 | `fw` |
| web-dmz | DMZ | 10.0.1.10 | 10.0.1.1 | Estático (Netplan) | Nginx e API FastAPI | `web` |
| db-zone | DB Zone | 10.0.3.10 | 10.0.3.1 | Estático (Netplan) | PostgreSQL 16 | `db` |
| file-lan | LAN | 10.0.2.10 | 10.0.2.1 | DHCP com reserva por MAC | Samba 4 | `arquivos` |
| admin-lan | LAN | 10.0.2.50 | 10.0.2.1 | DHCP com reserva por MAC | Ansible e SSH | `admin` |

O DNS interno (Bind9 no `fw-gw`) atende pelo endereço do `fw-gw` de cada zona (10.0.1.1, 10.0.2.1 e 10.0.3.1).

## 2.4 Justificativa das zonas

- **DMZ (10.0.1.0/24):** abriga o único servidor exposto à internet (Nginx e API). Se for comprometido, o invasor fica em uma zona sem acesso direto à LAN nem ao banco.
- **LAN (10.0.2.0/24):** reúne a estação de administração (`admin-lan`) e o servidor de arquivos. Só a `admin-lan` administra as outras máquinas, por SSH com chave.
- **DB Zone (10.0.3.0/24):** isola o banco de dados. Só o `web-dmz` conecta na porta 5432 (R2) e o banco só fala com o servidor de arquivos para enviar o backup (R6).

## 2.5 Tabelas de roteamento

As tabelas de cada máquina estão na seção 3.1.
