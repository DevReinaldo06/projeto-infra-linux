# Projeto Infra Linux

## Objetivo
Infraestrutura de redes e servidores Linux com três zonas (DMZ, LAN e DB Zone), firewall com iptables, servidor web Nginx, banco PostgreSQL, servidor de arquivos Samba, DHCP e DNS, provisionada com Ansible.

## Plano de IPs
| Máquina | Zona | IP |
| --- | --- | --- |
| fw-gw | DMZ / LAN / DB | 10.0.1.1 / 10.0.2.1 / 10.0.3.1 |
| web-dmz | DMZ | 10.0.1.10 |
| file-lan | LAN | 10.0.2.10 (DHCP com reserva) |
| admin-lan | LAN | 10.0.2.50 (DHCP com reserva) |
| db-zone | DB Zone | 10.0.3.10 |

## Como subir o ambiente
(a preencher)

## Como testar
(a preencher)
