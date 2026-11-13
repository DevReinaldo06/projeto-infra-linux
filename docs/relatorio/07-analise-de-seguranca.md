# 7. Análise de Segurança

## 7.1 Modelo de ameaça

| Quem ataca | O quê | Onde queremos barrar |
|---|---|---|
| Internet | Site (DMZ) e, a partir dele, o banco | Firewall de borda (fw-gw), apenas 80/443 entram |
| Servidor web comprometido | Banco de dados e LAN | R2 (só 5432), R5 (descarta o resto), DROP entre zonas |
| Usuário interno | Dados do file-lan e administração | Firewall de host, permissões do Samba, SSH só do admin-lan |

## 7.2 Defesa em camadas

1. **Rede (fw-gw):** iptables com política DROP em INPUT e FORWARD, firewall stateful (R0 primeiro).
2. **Host:** modelo `host-firewall.rules.j2`, política DROP em INPUT, SSH só de 10.0.2.50 (R4) e serviços por servidor. A R3 (LAN para file-lan) vive aqui, pois ambos estão na mesma sub-rede e o tráfego não passa pelo fw-gw.
3. **Serviço:** `pg_hba.conf` aceitando só o web-dmz; permissões POSIX no Samba.
4. **Acesso administrativo:** SSH só por chave ed25519 com passphrase, `PermitRootLogin no`, `PasswordAuthentication no`, `AllowUsers sysadmin`, `MaxAuthTries 3`, a partir de um único host (admin-lan).

## 7.3 Matriz de regras e justificativa

| Regra | Descrição | Justificativa de segurança |
|---|---|---|
| R0 | ESTABLISHED,RELATED aceitos | Firewall stateful: só respostas de conexões já autorizadas voltam |
| R1 | WAN para web-dmz 80/443 (DNAT) | Única porta pública do projeto |
| R2 | web-dmz para db-zone 5432 | Só o site grava no banco, e só nessa porta |
| R3 | LAN para file-lan 139/445 | Acesso ao Samba limitado à LAN (firewall de host) |
| R4 | admin-lan para todas as zonas, porta 22 | Administração centralizada; `-i` junto de `-s` impede forjar o IP de origem |
| R5 | DMZ e WAN para DB Zone: LOG e DROP | Protege o banco de acesso direto; DROP não confirma a existência da porta |
| R6 | db-zone para file-lan 445 | Backup diário, único fluxo db para LAN |
| R7 | DNS (53) das zonas; DHCP só na LAN | Serviços essenciais sem abrir mais que o necessário |
| R8 | DMZ e DB para internet só na janela de instalação | Servidores sensíveis ficam isolados fora de manutenção |
| R9 | LAN para internet 80/443/53 | Navegação e atualizações dos usuários internos |

## 7.4 Cenário: o servidor web foi comprometido

| O invasor tenta | Resultado | Barreira |
|---|---|---|
| Alcançar a LAN | Bloqueado | FORWARD DROP |
| SSH para qualquer máquina | Bloqueado | R4, firewall de host, AllowUsers |
| Falar com o banco | Só 5432, e só do IP do web | R2, `pg_hba.conf`, privilégio mínimo |
| Usar outro IP da DMZ | Bloqueado e registrado em log | R5 |
| Sair para a internet | Bloqueado fora da janela | chain PROVISION vazia |
| Consultar o DNS do fw-gw | Permitido | Risco residual (possível canal de exfiltração) |

## 7.5 Evidências e testes realizados

**Ambiente de validação:** os testes do firewall foram feitos em uma cópia do fw-gw rodando na máquina do autor, junto com a admin-lan. As regras aplicadas são exatamente as de `configs/fw-gw/iptables.rules` do repositório. As VMs das zonas DMZ, DB e LAN rodavam em outros computadores, e uma Rede Interna do VirtualBox só conecta VMs do mesmo computador. Por isso a matriz completa não pôde ser exercitada.

**Provado:**
- **SSH endurecido no fw-gw:** `sshd -T` confirmou `permitrootlogin no`, `passwordauthentication no`, `allowusers sysadmin`, `maxauthtries 3`. Tentativas com senha e como root foram recusadas (`Permission denied (publickey)`). Evidência em `docs/evidencias/ssh/`.
- **Modo observação:** aplicado com `fw-apply.sh`; regras R0 a R9 carregadas, NAT (DNAT e MASQUERADE) ativo. Evidência em `docs/evidencias/firewall/iptables-observacao-*.txt`.
- **Política DROP:** aplicada em INPUT e FORWARD. O SSH da admin-lan (R4) continuou funcionando. Evidência em `docs/evidencias/firewall/iptables-drop-*.txt`.
- **Contadores da R5:** regras LOG e DROP da R5 carregadas e zeradas, prontas para contar.
- **Modelo de firewall de host:** renderizado para web, db e file e validado com `iptables-restore --test`.
- **Roles Ansible `common` e `firewall`:** escritas, com `--syntax-check` e renderização do template validados (commit `a9f972f`). Não foram executadas contra uma VM real.
- **fw-apply.sh (rede de segurança):** os testes revelaram dois defeitos, corrigidos:
  1. Neste sistema (iptables 1.8.10, nf_tables) o `--test` valida só a sintaxe e não detecta chain inexistente. O script passou a cancelar o temporizador de desfazer se a aplicação falhar.
  2. Em máquina sem regras, o backup saía vazio e restaurá-lo não reabria o acesso. O script passou a gravar um backup padrão com políticas em ACCEPT.
  Lição: a proteção real é o desfazer automático com um backup válido, não a validação prévia.
- **R9 e NAT com DROP ligado:** `nc -zv -w3 8.8.8.8 443` da admin-lan, via fw-gw, retornou `succeeded`. Prova R9, MASQUERADE e R0. Evidência em `docs/evidencias/firewall/r9-nat-com-drop-*.txt`.
- **Janela R8 (mecanismo):** `fw-provisioning.sh on/status/off` cria e remove as regras ACCEPT na chain PROVISION, e o fechamento automático (`on 1`) esvaziou a chain sozinho. Evidência em `docs/evidencias/firewall/r8-*.txt`. O tráfego real do web-dmz e do db-zone fica para a integração.
- **matrix.sh (parcial, com DROP ligado):** com fw-gw e db-zone no ar, passaram R4 (SSH da admin-lan no fw-gw e no db-zone), R7 (DNS da DB no gateway) e o bloqueio db-zone → SSH no fw-gw. Os demais casos falharam por infraestrutura (web-dmz e file-lan ausentes), não por regra. Evidência em `docs/evidencias/firewall/matrix-parcial-*.txt`.
- **Roles Ansible `common` e `firewall` (idempotência):** `common` no db-zone (1ª `changed=5`, 2ª `changed=0`) e `firewall` no fw-gw (1ª `changed=4`, 2ª `changed=0`), ambas com `failed=0`. Evidência em `docs/evidencias/ansible/`. Executadas em cópias das VMs no ambiente do autor.
- **Revisão do iptables.rules:** o jump da R8 estava na interface errada (LAN em vez de DMZ), corrigido no commit `b0fe4d3` e confirmado na revisão do grupo.

**Não provado (pendente):**
- Janela R8 com tráfego real do web-dmz e do db-zone (só o mecanismo foi provado).
- Execução completa do matrix.sh com web-dmz e file-lan no ar (R2, R3, R5, R6, R9 e bloqueios da DMZ).
- Contador da R5 subindo com tráfego real da DMZ para o banco.
- Firewall de host aplicado em web, db e file.
- Roles Ansible executadas nas VMs da integração (PC do Reinaldo) e nas bases limpas.

## 7.6 Riscos residuais e limitações

- Certificado autoassinado.
- NAT único e ausência de monitoramento e logs centralizados.
- admin-lan como ponto único de administração (mitigado por passphrase e rede interna).
- `sudo` sem senha nas VMs, aceitável em laboratório.
- OUTPUT liberado nos firewalls de host.
- IPv6 sem regras (o arquivo cobre só IPv4).
- DNS como possível canal de exfiltração.
- Conflito de faixa de endereços: a NAT do VirtualBox usa 10.0.3.0/24, a mesma da DB Zone, tratado na admin-lan com rotas estáticas via fw-gw.
- ICMP entre zonas não é liberado pela matriz; testes usam `nc`, `curl` e `dig`.

## 7.7 Próximos passos

Let's Encrypt ou CA interna, rsyslog central com alertas, `fail2ban`, política IPv6, filtro de saída por host, bastion com 2FA.
