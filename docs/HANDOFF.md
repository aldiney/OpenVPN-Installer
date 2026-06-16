# Handoff — OpenVPN-Installer

Estado do projeto para retomar de qualquer máquina. (Repo público — este documento
**não** contém dados do ambiente de teste; o acesso ao servidor é específico do operador.)

## Onde estamos

- **Objetivo entregue e validado em host real:** rede única (hub-and-spoke com
  `client-to-client`) + **saída para a internet pela VPN funcionando** (full-tunnel IPv4),
  **persistente no reboot**. Cliente Windows conecta, navega e o `mtr` completa pela VPN.
- **Operando com UM hub** em produção; o **dual-hub ativo-ativo foi reconstruído de verdade**
  (ADR 0004 — enlace "hub B conecta no hub A como cliente, via `iroute`"; submenu opção 15;
  rede da VPN configurável; CA mestra com `ca.key`; interface fixa `ovpn-link`). Falta a
  **validação HITL em 2 máquinas** (#54) — guia em `docs/dual-hub.md` e `validacao-hitl` T6.
- **169 testes (bats) verdes, shellcheck limpo, CI verde.** Repo público.

## Como rodar / desenvolver

- **Alvos:** Debian 12+ / Ubuntu 24.04+, com root.
- **Instalar no servidor:** `bootstrap.sh` (prepara a máquina + clona + instala o comando no
  PATH) **ou** clone + `sudo ./install.sh`. Depois, `sudo openvpn-installer` de qualquer lugar.
- **Testes locais:** `bats -r tests/` e `shellcheck` nos `*.sh` (instale `bats`/`shellcheck`
  via apt). O CI (GitHub Actions) roda os dois em cada push/PR.
- **Convenções:** TDD (vermelho→verde); pt-BR para o operador, identificadores em inglês;
  módulos profundos em `lib/`; cada mudança em branch `feat|fix/...` → PR `Closes #N` →
  CI verde → merge squash.
- **Regras invioláveis:**
  - **Regra dos 7 dias** (nunca instalar pacote lançado há < 7 dias).
  - **Não citar projetos internos de inspiração** em nada (ver regra no `CLAUDE.md`).
  - Repo é **público** → **nunca** publicar IP/usuário/host/nome de cliente do ambiente de
    teste em código, commit, PR, issue ou doc.

## Arquitetura (módulos `lib/`)

`core` (paths, die, require_root, `ovpn_sysctl_set`), `log`, `ui`, `config` (persiste
preferências em `/etc/openvpn/installer.conf`), `os_detect`, `deps` (regra dos 7 dias),
`pki` (CA/cert ECDSA, tls-crypt, reemissão do cert do servidor), `wizard_ipproto`,
`server_config`, `ccd` (IP fixo por cliente), `client_profile` (.ovpn + QR + roteamento),
`mikrotik_profile`, `firewall` (abre a porta), `gateway` (saída-internet/NAT),
`hub_sync`, `dualhub`, `lifecycle` (revogar/desinstalar), `upgrade` (migração in-place),
`syscmd` (comando no PATH), `controller` (menu).
Entradas: `bootstrap.sh`, `install.sh`. Ferramenta: `tools/diag-saida.sh`.
Docs: `docs/{prd,howto,mikrotik-guide,dual-hub,troubleshooting,validacao-hitl}.md`.

## Decisões travadas

- `tun` + `topology subnet` + `client-to-client` (única topologia que atende celular). IP
  fixo por cliente via `client-config-dir` + `ifconfig-push`.
- Cripto: `tls-crypt`; `data-ciphers AES-256-GCM:AES-128-GCM`; ECDSA prime256v1; cert com
  **Key Usage + Extended Key Usage** (serverAuth/clientAuth) — exigido pelo `remote-cert-tls`.
- IPv4 / IPv6 / dual-stack escolhido no wizard. `mssfix 1420` no server.conf (evita travas de MTU).
- **Saída para a internet opcional** (off por padrão): em host com **UFW**, usa
  `ufw route allow in on <tun> out on <wan>` + NAT no `/etc/ufw/before.rules` + `ip_forward`
  no `/etc/sysctl.d/` — **tudo persistente**. Em nft/iptables, runtime.
- **Full-tunnel/split POR CLIENTE no `.ovpn`** (client-side): full = `redirect-gateway` +
  DNS + `setenv opt block-outside-dns`; split = rotas específicas; padrão = só a rede VPN.
- **Upgrade in-place idempotente** (`OVPN_SCHEMA_VERSION` + carimbo `.installer-version`) —
  nunca toca na CA nem em certs/.ovpn de cliente; só reemite o cert do servidor e acrescenta
  diretivas faltantes. Mudanças de rota são só reportadas.

## Lições da validação real (gotchas — carregar para frente)

- Cliente recusa o servidor se o cert não tiver **Key Usage** (`VERIFY KU ERROR`).
- **UFW com `FORWARD policy DROP`** descarta TCP/UDP encaminhado da VPN (só passa
  ICMP/established) → precisa de `ufw route allow in on <tun> out on <wan>`.
- NAT e forwarding precisam ser **persistidos** (before.rules + sysctl.d), senão somem no reboot.
- **NAT duplicado** (nft legado + before.rules) bagunça o de-NAT de ICMP → `traceroute`/`mtr`
  oscilam embora a navegação funcione. O gateway agora limpa o legado.
- `mtr` lento sem `-n` é **resolução de DNS reverso do cliente** (no WSL costuma ser o
  resolver), não o servidor — `mtr -n` confirma que a conectividade está OK.
- Bug do IP fixo duplicado a partir do 3º cliente (corrigido no `ccd`).

## Pendências

- **[#54] Dual-hub HITL** — código pronto e revisado (revisão adversarial multi-agente);
  falta validar em **2 máquinas** seguindo `docs/dual-hub.md`.
- **[#44] Full-tunnel IPv6** — aberta, adiada. Hoje o IPv6 do cliente sai pela rede dele.
- Outras validações HITL ainda não feitas: **MikroTik** real, **bootstrap** em VM limpa,
  **mesh** entre 2 dispositivos.
- Fora do escopo do instalador: lentidão do DNS reverso no WSL (client-side).

## Como continuar (de outra máquina)

1. `gh repo clone aldiney/OpenVPN-Installer` (repo público).
2. Ler este handoff + `docs/howto.md` + `docs/validacao-hitl.md`.
3. `sudo apt install bats shellcheck` e rodar `bats -r tests/`.
4. No servidor de teste (acesso é do ambiente, não versionado): após `git pull`, rodar
   `sudo openvpn-installer`. Se reiniciou e a saída-internet parou, rode a opção
   **5 (Ativar saída para a internet)** de novo (idempotente; deixa tudo persistente).
5. Próximo trabalho natural: **#44 (IPv6)**.
