# 4. Serviços de base: DHCP e DNS

Ambos rodam no `fw-gw` e são instalados pela role Ansible `gateway`.

## 4.1 DHCP com reservas

**Serviço:** `isc-dhcp-server`, atendendo somente a LAN (interface `enp0s9`, 10.0.2.1).

| Parâmetro | Valor |
|---|---|
| Sub-rede | 10.0.2.0/24 |
| Pool dinâmico | 10.0.2.100 a 10.0.2.200 |
| Gateway (`routers`) | 10.0.2.1 |
| DNS | 10.0.2.1 |
| Domínio | `empresa.local` |
| Reserva `file-lan` | MAC `08:00:27:5f:08:cc` → 10.0.2.10 |
| Reserva `admin-lan` | MAC `<MAC da admin-lan>` → 10.0.2.50 |

Arquivo: `configs/fw-gw/dhcpd.conf`.

**Prova da reserva:** a `file-lan` recebeu 10.0.2.10 pelo MAC `08:00:27:5f:08:cc`, fora do pool dinâmico. Evidência completa em `docs/evidencias/gateway/dhcp-reserva-file-lan.txt`.

## 4.2 DNS direto e reverso (Bind9)

**Zona direta:** `empresa.local`. **Zonas reversas:** `1.0.10.in-addr.arpa`, `2.0.10.in-addr.arpa`, `3.0.10.in-addr.arpa`. As zonas ficam em arquivos próprios (`db.empresa.local`, `db.10.0.1`, `db.10.0.2`, `db.10.0.3`) copiados de `configs/fw-gw/`.

| Nome | Endereço |
|---|---|
| `fw.empresa.local` | IP do `fw-gw` na zona |
| `web.empresa.local` | 10.0.1.10 |
| `db.empresa.local` | 10.0.3.10 |
| `arquivos.empresa.local` | 10.0.2.10 |
| `admin.empresa.local` | 10.0.2.50 |

Os servidores usam o `fw-gw` da própria zona como DNS. A configuração foi validada com `named-checkconf` e `named-checkzone` antes de recarregar o serviço (tarefa da role).

### Testes (executados no `fw-gw`, 13/11/2026)

```
== dig web
10.0.1.10
== dig db
10.0.3.10
== dig reverso
db.empresa.local.
```

Comandos: `dig @10.0.2.1 web.empresa.local +short`, `dig @10.0.2.1 db.empresa.local +short` e `dig @10.0.2.1 -x 10.0.3.10 +short`.

**O que provam:** o Bind9 resolve os nomes do domínio interno e a zona reversa devolve o nome correto para o IP 10.0.3.10. A resolução também foi comprovada a partir da `admin-lan` (`docs/evidencias/gateway/dns-cliente-admin-lan.txt`), o que mostra que clientes de outra zona alcançam o DNS.

## 4.3 Automação (role `gateway`)

A role `gateway` instala os pacotes, liga o encaminhamento, aplica o NAT, copia o Netplan, o `dhcpd.conf`, as opções e zonas do Bind9, valida a sintaxe e garante os serviços ligados no boot. Reinicia os serviços só quando algo muda (handlers).

**Prova de idempotência:** na segunda execução do playbook, a partir da `admin-lan`, o `fw-gw` terminou com:

```
fw-gw : ok=19  changed=0  unreachable=0  failed=0  skipped=0
```

Isso prova que rodar a automação novamente não altera nada (`changed=0`).

Código: `ansible/roles/gateway/`.
