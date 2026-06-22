# Handoff — OpenVPN-Installer

Estado do projeto para retomar de qualquer máquina. (Repo público — este documento
**não** contém dados do ambiente de teste; o acesso ao servidor é específico do operador.)

## Onde estamos

- **Rede única validada em host real:** hub-and-spoke com `client-to-client` + **saída para a
  internet pela VPN** (full-tunnel IPv4), persistente no reboot.
- **Dual-hub ativo-ativo + IP estável global (OSPF) — plano de dados VALIDADO fim-a-fim com
  cliente real.** Cada cliente tem o **mesmo IP em qualquer hub** (roam) e cada hub tem um **IP
  de identidade próprio** (`/32` no topo do espaço, derivado do `HUB_ID` — ex.: hub 1 → `.241`,
  hub 2 → `.242`). Um cliente conectado num hub alcança a identidade dos **dois** hubs.
- **Sincronização automática do mapa cliente→IP** entre hubs (pull pelo enlace, timer) e
  **status num comando** (`sudo openvpn-installer status`).
- **232 testes (bats) verdes, shellcheck limpo, CI verde.** Repo público.

> Modo dinâmico é **op-in** (`OVPN_DYNROUTING=off` por padrão preserva o dual-hub estático).
> Ativação e parâmetros pelo submenu **15 (Dois hubs)**. Guia: `docs/ip-estavel.md`, ADR 0005.

## Como rodar / desenvolver

- **Alvos:** Debian 12+ / Ubuntu 24.04+, com root.
- **Instalar no servidor:** `bootstrap.sh` (prepara a máquina + clona + instala o comando no
  PATH) **ou** clone + `sudo ./install.sh`. Depois, `sudo openvpn-installer` de qualquer lugar.
- **Testes locais:** `bats -r tests/` e `shellcheck` nos `*.sh` (instale `bats`/`shellcheck`
  via apt). O CI (GitHub Actions) roda os dois em cada push/PR.
- **Convenções:** TDD (vermelho→verde); pt-BR para o operador, identificadores em inglês;
  módulos profundos em `lib/`; cada mudança em branch `feat|fix/...` → PR → CI verde → merge.
  Commit a cada etapa concluída; push ao final ou sob pedido; reportar o hash.
- **Regras invioláveis:**
  - **Regra dos 7 dias** (nunca instalar pacote lançado há < 7 dias).
  - **Não citar projetos internos de inspiração** em nada (ver regra no `CLAUDE.md`).
  - Repo é **público** → **nunca** publicar IP/usuário/host/nome de cliente do ambiente de
    teste em código, commit, PR, issue ou doc.

## Arquitetura (módulos `lib/`)

Base: `core`, `log`, `ui`, `config`, `os_detect`, `deps` (regra dos 7 dias), `pki` (CA/cert
ECDSA, tls-crypt, reemissão do cert do servidor), `wizard_ipproto`, `server_config`,
`ccd` (IP fixo por cliente), `client_profile` (.ovpn + QR + roteamento), `mikrotik_profile`,
`firewall`, `gateway` (saída-internet/NAT), `hub_sync`, `dualhub`, `lifecycle`, `upgrade`,
`syscmd`, `controller` (menu).

IP estável global (modo dinâmico): `frr` (OSPF via FRR), `route_reconcile` (lê o `status` do
OpenVPN e mantém os `/32` dos clientes locais como rotas para o OSPF redistribuir),
`link` (2ª instância OpenVPN dedicada ao enlace inter-hub, `ovpn-link`), `route_sync`/`mapsync`
(bundle do mapa cliente→IP + pull automático), `hub_identity` (o `/32` de identidade do hub).

Entradas: `bootstrap.sh`, `install.sh`. Docs: `docs/{prd,howto,mikrotik-guide,dual-hub,
ip-estavel,troubleshooting,validacao-hitl}.md`. ADRs em `docs/prd/adr/` (0004 dual-hub, 0005 OSPF).

## Decisões travadas

- `tun` + `topology subnet` + `client-to-client` (única topologia que atende celular). IP
  fixo por cliente via `client-config-dir` + `ifconfig-push`.
- Cripto: `tls-crypt`; `data-ciphers AES-256-GCM:AES-128-GCM`; ECDSA prime256v1; cert com
  **Key Usage + Extended Key Usage** — exigido pelo `remote-cert-tls`.
- **IP estável global (ADR 0005):** espaço plano compartilhado por todos os hubs do domínio;
  IP estável = IP do túnel (sem endereço secundário no cliente → celular/MikroTik OK). Cada hub
  anuncia no OSPF **só os `/32`** dos seus clientes (o espaço conectado NÃO é redistribuído); o
  `/32` segue o cliente no roam. **Enlace inter-hub dedicado** (`ovpn-link`, 2ª instância
  OpenVPN); OSPF roda só nele. Mapa cliente→IP igual em todos via bundle marcado por `DOMAIN_ID`.
- **Identidade por hub:** `/32` reservado no topo do espaço (`OVPN_HUB_RESERVED`, default 15),
  numa dummy `ovpn-self`, anunciado por `redistribute connected` (route-map só `/32`).
- **Upgrade in-place idempotente** (`OVPN_SCHEMA_VERSION`) — nunca toca CA nem certs/.ovpn de
  cliente; só reemite o cert do servidor e acrescenta diretivas faltantes.

## Lições da validação real (gotchas — carregar para frente)

Rede mínima / saída-internet:
- Cliente recusa o servidor se o cert não tiver **Key Usage** (`VERIFY KU ERROR`).
- **UFW `FORWARD policy DROP`** descarta o encaminhado da VPN → `ufw route allow in on <tun> out on <wan>`.
- NAT e forwarding precisam ser **persistidos** (before.rules + sysctl.d), senão somem no reboot.
- `mtr` lento sem `-n` = DNS reverso do cliente (client-side), não o servidor.

IP estável global / dual-hub (data plane — todos pegos só em HITL, nenhum por bats):
- **OSPF correto ≠ dados fluindo.** Adjacência Full e `/32` na FIB podem coexistir com o data
  plane 100% quebrado — testar SEMPRE fim-a-fim com cliente real.
- **FRR no Debian/Ubuntu:** `service integrated-vtysh-config` (default) faz o FRR ignorar o
  `ospfd.conf` por-daemon → desligar (`no service ...`) e aplicar com `vtysh -f`. `frr` precisa
  de **restart** (não `enable --now`) p/ aplicar o `daemons`. Rotas `proto static` o zebra vê
  como **KERNEL** → `redistribute kernel` (não `static`). Sintaxe nova: `no ip ospf passive`.
- **UFW dropa os hellos OSPF no INPUT** (multicast 224.0.0.5, proto 89, vão ao host, não ao
  FORWARD) → liberar INPUT no enlace. `tcpdump` vê o pacote antes do INPUT e mascara o drop.
- **Enlace core→spoke precisa de `iroute`:** o OpenVPN-server só entrega a um cliente o que
  tiver iroute; sem ele os `/32` atrás do spoke são descartados. **E sem `client-to-client`** no
  enlace — com ele, o iroute do espaço mascara os endereços LOCAIS do core. (Vale p/ 1 core +
  1 spoke; multi-spoke exigiria redesenho.)
- **Reconciliador:** o `ip route` do IPv4 mostra rota de host **sem** o sufixo `/32` — a poda
  precisa tratar isso, senão o `/32` de um cliente que saiu (roam) vira órfão e o hub antigo faz
  **blackhole** (a rota local, distância 0, vence a do OSPF, 110).
- **Restart do enlace derruba o OSPF (~34s, dead timer)** — pingar antes de reconvergir dá
  falso-negativo.
- **Stub que não imita o formato REAL do comando esconde o bug** (foi o caso do `ip`).

## Pendências

- **HITL restante:** **celular + MikroTik** pegando o IP estável nos 2 hubs. (Cliente desktop
  já validado fim-a-fim: identidade dos dois hubs + roam com alcance.)
- **[#44] Full-tunnel IPv6** — aberta, adiada. Hoje o IPv6 do cliente sai pela rede dele.
- **[#87] Robustez do nome do `tun` dos clientes + paridade IPv6** — follow-up da revisão, adiada.
- Outras validações HITL não feitas: **bootstrap** em VM limpa.

## Como continuar (de outra máquina)

1. `gh repo clone aldiney/OpenVPN-Installer` (repo público).
2. Ler este handoff + `docs/howto.md` + `docs/ip-estavel.md` + `docs/validacao-hitl.md`.
3. `sudo apt install bats shellcheck` e rodar `bats -r tests/`.
4. Nos servidores de teste (acesso é do ambiente, não versionado): após `git pull`, o
   reconciliador passa a auto-podar `/32` órfãos de roam; o status sai em `sudo openvpn-installer status`.
5. Próximo trabalho natural: HITL celular/MikroTik, depois **#44 (IPv6)** ou **#87**.
