# Ansible: provisionamento do projeto

Dono do esqueleto, do `site.yml` e da role `gateway`: Reinaldo.
Cada role pertence a um integrante (tabela abaixo).

## Como funciona

O Ansible roda a partir do **admin-lan (10.0.2.50)**, por SSH com chave, com o
usuário `sysadmin` e sudo sem senha. Cada role descreve o **estado final** de uma
máquina. Rodar duas vezes dá o mesmo resultado: na 2ª execução o resumo mostra
`changed=0` (idempotência).

## Ordem de execução (`site.yml`)

| Ordem | Hosts | Role | Dono |
|---|---|---|---|
| 1 | todos | `common` (pacotes, usuário, chave SSH, sudo, hardening do SSH) | Eduardo |
| 2 | gateway (fw-gw) | `gateway` (roteamento, NAT, DHCP, DNS) | Reinaldo |
| 3 | fileserver (file-lan) | `fileserver` (Samba, cotas, backups) | Marco |
| 4 | database (db-zone) | `database` (PostgreSQL 16) | Elton |
| 5 | web (web-dmz) | `web` (Nginx + FastAPI) | Guilherme |
| 6 | todos | `firewall` (**sempre por último**) | Eduardo |

O firewall fica por último porque fecha a saída das máquinas: as outras roles
precisam instalar pacotes antes. Para o fw-gw alcançar a internet antes disso, a
role `gateway` já cria a regra de NAT `R8_R9_masq` (a mesma do `iptables.rules`).

## Pré-requisitos

- admin-lan com o pacote `ansible` completo (inclui `ansible.posix` e `community.general`)
  e o repositório clonado.
- Chave SSH ed25519 do admin-lan autorizada nas VMs; `sysadmin` com sudo sem senha.
- Senha do cofre (`ansible-vault`) combinada **fora do repositório** (nunca no Git).

## Comandos

```bash
cd ~/projeto-infra-linux/ansible
ansible all -m ping                                   # cada máquina responde "pong"
ansible-playbook site.yml --syntax-check              # confere a sintaxe
ansible-playbook site.yml --check --ask-vault-pass    # simula, sem mudar nada
ansible-playbook site.yml --ask-vault-pass            # aplica
ansible-playbook site.yml --ask-vault-pass            # 2ª vez: changed=0
```

Uma role só: `ansible-playbook gateway.yml` (ou `fileserver.yml`).

## Janela de instalação do firewall

Com o firewall já aplicado (política DROP), quem for instalar pacotes precisa abrir
a chain `PROVISION` antes e fechá-la depois (`scripts/fw-provisioning.sh on` / `off`).

## Ensaio de destruição (marco M4, 18/11)

1. No VirtualBox, restaurar as VMs para o snapshot `base-limpa`.
2. No admin-lan: `ansible-playbook site.yml --ask-vault-pass`.
3. Rodar a suíte de testes: `bash tests/matrix.sh` e `bash tests/e2e.sh`. Tudo deve passar.
4. Rodar o playbook de novo e conferir `changed=0`.

## Organização

- `ansible.cfg`: inventário padrão, `remote_user = sysadmin`.
- `inventory/hosts.ini`: inventário oficial (IPs das 4 máquinas).
- `group_vars/all.yml`: domínio e plano de IPs (sem senhas). Senhas ficam em arquivos `vault.yml` cifrados.
- Os arquivos de configuração ficam em `configs/` (fonte única); as roles apontam para eles.
- Evidências das execuções: `docs/evidencias/ansible/`.

## Cuidados

- Nunca rodar o `site.yml` no fw-gw com inventário local: as roles `common` e `firewall`
  aplicariam o hardening do SSH e o firewall DROP na própria máquina.
- Para testar só a role `gateway` no fw-gw:
  `ansible-playbook -i inventory/local.ini gateway.yml --ask-become-pass`.
