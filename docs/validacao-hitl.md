# Plano de validação HITL (host de teste)

Roteiro para validar, num host real, os demos que os testes automatizados não cobrem
(conexão de equipamentos, tráfego real, failover). Cada teste tem **passos**, **resultado
esperado** e **critério de aprovação**. Marque `[x]` ao passar.

> Ambiente sugerido: 1 servidor (VPS ou VM Debian 12+/Ubuntu 24.04+ com IP público ou
> acessível) + pelo menos 2 equipamentos cliente (ex.: um notebook e um celular).
> Onde aparecer `HUB_ADDR`, use o IP público/domínio do servidor.

---

## Pré-teste — Hub no ar (issue #4)

- [ ] Passos:
  1. No servidor: `sudo ./install.sh` → opção **1** → instalar dependências (`s`) → modo **1 (IPv4)**.
  2. `sudo systemctl status openvpn-server@server`
  3. `ip addr show tun0`
- [ ] Esperado: serviço **active (running)**; interface `tun0` com `10.8.0.1`.
- [ ] Aprovação: o serviço sobe e permanece ativo após `systemctl restart`.

---

## T1 — Primeiro cliente conecta e há comunicação (issue #5) — **prova do objetivo**

- [ ] Passos:
  1. Menu opção **2** → nome `cliente1` → informar `HUB_ADDR`.
  2. Transferir `~/cliente1.ovpn` para o equipamento A e conectar (ver howto por plataforma).
  3. Menu opção **2** → nome `cliente2` → conectar no equipamento B.
  4. Do equipamento A: `ping 10.8.0.2` e `ping 10.8.0.3` (use os IPs da opção **3**).
- [ ] Esperado: ambos conectam; A pinga B **pelo IP da VPN** e vice-versa.
- [ ] Aprovação: ping responde nos dois sentidos; um serviço (ex.: SSH) de B é acessível de A.

---

## T2 — Celular via QR (issue #5)

- [ ] Passos:
  1. Menu opção **2** → nome `celular` (o QR aparece no terminal).
  2. No app **OpenVPN Connect**: Import → QR code → escanear → conectar.
  3. Do celular, acessar um equipamento da rede pelo IP `10.8.0.x`.
- [ ] Esperado: o celular entra na mesma rede e alcança os demais.
- [ ] Aprovação: ping/serviço de outro equipamento responde a partir do celular.

---

## T3 — IPv6 / dual-stack (issue #6)

- [ ] Passos:
  1. Desinstalar (opção **9**, pode preservar a PKI) e reinstalar (opção **1**) escolhendo
     modo **3 (dual-stack)** — ou validar num segundo hub de teste.
  2. Conectar um cliente e checar o endereço IPv6 recebido.
  3. `ping6` entre dois clientes pelos endereços IPv6 da VPN.
- [ ] Esperado: clientes recebem endereço IPv6 (`fd00:0:0:8::/64`) e se comunicam por IPv6.
- [ ] Aprovação: `ping6` responde entre dois equipamentos.

---

## T4 — Saída para a internet (issue #7)

- [ ] Passos:
  1. Menu opção **5** → informar a interface WAN do hub (ex.: `eth0`).
  2. Reconectar o cliente (o perfil recebe `redirect-gateway`).
  3. No cliente: `curl -s https://ifconfig.me` (deve mostrar o IP do hub).
  4. Menu opção **6** para desativar; reconectar e repetir o `curl`.
- [ ] Esperado: com a saída ativa, o IP público do cliente é o do hub; ao desativar, volta ao normal.
- [ ] Aprovação: o IP de saída muda conforme ativa/desativa.

---

## T5 — MikroTik (issue #8)

- [ ] Passos:
  1. Menu opção **7** → nome `mikrotik1` → informar `HUB_ADDR`.
  2. No RouterOS: importar os certificados e colar o `mikrotik1.rsc` (ver mikrotik-guide.md).
  3. `/interface ovpn-client print` e `ping` de/para outro equipamento da rede.
- [ ] Esperado: o MikroTik entra na rede plana e alcança os demais equipamentos.
- [ ] Aprovação: ping responde entre o MikroTik e outro equipamento da VPN.

---

## T6 — Dois hubs ativo-ativo + failover (issue #10)

Tudo pelo menu (opção **15 — Dois hubs**). Guia completo em `docs/dual-hub.md`.

- [ ] Passos:
  1. **Hub A**: opção **1** com a rede `10.8.0.0`; opção **13** define o host público.
  2. **Hub A**: menu **15 → 1** exporta a **CA mestra** (`/root/ca-mestra.tar.gz`);
     transferir o bundle para o hub B (canal seguro).
  3. **Hub B** (outra máquina): menu **15 → 3** importa a CA mestra; depois opção **1**
     com a rede **`10.8.1.0`** (distinta); opção **13** define o host público.
  4. **Hub A**: menu **15 → 4 (Registrar hub par)** — nome `hub-b`, sub-rede `10.8.1.0`;
     levar o `hub-b.ovpn` gerado para o hub B.
  5. **Hub B**: subir o enlace
     (`sudo cp hub-b.ovpn /etc/openvpn/client/hub-b.conf && sudo systemctl enable --now openvpn-client@hub-b`);
     confirmar a conexão (`systemctl is-active openvpn-client@hub-b` e
     `journalctl -u openvpn-client@hub-b | grep "Initialization Sequence Completed"`); a
     interface do enlace é fixa **`ovpn-link`**; menu **15 → 6** (encaminhamento, `ovpn-link`)
     e **15 → 5** (anunciar a sub-rede do hub A, `10.8.0.0`).
  6. Em um hub: menu **15 → 7** define o 2º hub; opção **2** gera clientes com os dois `remote`.
  7. Conectar um cliente em cada hub; pingar de `10.8.0.x` para `10.8.1.x`.
  8. Derrubar um hub (`sudo systemctl stop openvpn-server@server`) e observar o cliente migrar.
- [ ] Esperado: cliente do hub A alcança cliente do hub B; ao cair um hub, o cliente reconecta no outro.
- [ ] Aprovação: comunicação cruzada funciona e o cliente sobrevive à queda de um hub.

---

## T7 — Bootstrap em máquina limpa (issue #11)

- [ ] Passos:
  1. Numa VM limpa (sem git/gh): `bash bootstrap.sh`.
  2. Confirmar a instalação das ferramentas, autenticar no GitHub, deixar clonar.
  3. `cd ~/OpenVPN-Installer && sudo ./install.sh`.
- [ ] Esperado: de uma máquina limpa até o menu do instalador em um comando.
- [ ] Aprovação: o menu abre sem passos manuais extras além dos pedidos pelo bootstrap.

---

## T8 — Revogar e desinstalar (issue #12)

- [ ] Passos:
  1. Menu opção **8** → revogar `cliente1`; tentar reconectar com o perfil antigo.
  2. Menu opção **4** → conferir status e lista de clientes.
  3. Menu opção **9** → desinstalar (testar uma vez **preservando** e outra **removendo** a PKI).
- [ ] Esperado: cliente revogado não reconecta; status coerente; desinstalação limpa.
- [ ] Aprovação: o acesso revogado é bloqueado e a desinstalação remove config/serviço conforme a escolha.

---

## T9 — Upgrade/migração in-place (sem quebrar clientes)

- [ ] Pré-requisitos: uma instalação feita por uma versão anterior (ex.: cert do servidor
      sem Key Usage e/ou `server.conf` sem `mssfix`), com pelo menos um cliente conectado.
- [ ] Passos:
  1. No hub: `cd ~/OpenVPN-Installer && git pull`.
  2. `sudo ./install.sh` → aceitar a oferta de migrar (ou menu opção **11**).
  3. Conferir: `sudo openssl x509 -in /etc/openvpn/pki/issued/server.crt -noout -ext keyUsage,extendedKeyUsage`
     mostra KU + serverAuth; `grep -q '^mssfix' /etc/openvpn/server/server.conf`.
  4. O cliente já conectado deve **reconectar sozinho** após o restart (sem regerar `.ovpn`).
  5. Rodar a migração **de novo** → deve dizer "nada a corrigir" (idempotente).
- [ ] Esperado: correções aplicadas; CA e perfis de cliente **intactos**; clientes seguem
      conectando com o `.ovpn` antigo; 2ª execução é no-op.
- [ ] Aprovação: cliente antigo reconecta após a migração; reexecutar não muda nada.

---

## T10 — IP estável global (FRR + OSPF + reconciliador) (épico #66–#74, ADR 0005)

> Requer 2 hubs no mesmo domínio + 1 cliente móvel. Guia: `docs/ip-estavel.md`. Vários itens
> só se validam em máquina real (mecânica `topology subnet`, redistribuição FRR, convergência).

- [ ] Passos:
  1. Hub core e hub spoke instalados; CA mestra compartilhada (T6). Definir as chaves do
     domínio (`OVPN_DOMAIN_ID`, `OVPN_HUB_ID`, `OVPN_HUB_ROLE`, espaço `/22`).
  2. (Hub existente) Submenu **15 → 9** re-endereça `/24 → /22` (preserva o octeto; backup do ccd).
  3. Em cada hub: submenu **15 → 8** (Ativar IP estável global) — instala FRR, re-renderiza,
     sobe o enlace dedicado e o reconciliador.
  4. `sudo vtysh -c "show ip route ospf"` nos dois hubs: confirmar que aparecem **só os `/32`
     dos clientes** (o `/22` conectado **não** vaza).
  5. Conectar um cliente no core (recebe ex.: `10.80.0.5`); conferir que outro cliente o alcança
     por esse IP. Migrar o cliente para o spoke (failover) e confirmar que **mantém `10.80.0.5`**.
  6. Medir a **convergência** do roam (alvo a definir, ex.: < 30 s) e ajustar timers/metric.
  7. Repetir com **celular** e **MikroTik** — devem receber o IP estável sem up-script, em ambos.
- [ ] Esperado: o cliente tem o **mesmo IP em qualquer hub**; só os `/32` entram no OSPF;
      celular/MikroTik funcionam sem ajuste no cliente.
- [ ] Aprovação: IP idêntico antes e depois do roam; LSDB sem o `/22`; convergência aceitável.

## Registro

| Teste | Resultado | Observações |
|-------|-----------|-------------|
| Pré-teste (hub) | ☐ ok / ☐ falhou | |
| T1 (cliente+ping) | ☐ ok / ☐ falhou | |
| T2 (celular/QR) | ☐ ok / ☐ falhou | |
| T3 (IPv6) | ☐ ok / ☐ falhou | |
| T4 (saída internet) | ☐ ok / ☐ falhou | |
| T5 (MikroTik) | ☐ ok / ☐ falhou | |
| T6 (dual-hub) | ☐ ok / ☐ falhou | |
| T7 (bootstrap) | ☐ ok / ☐ falhou | |
| T8 (revogar/desinstalar) | ☐ ok / ☐ falhou | |
| T9 (upgrade in-place) | ☐ ok / ☐ falhou | |
| T10 (IP estável global) | ☐ ok / ☐ falhou | |

Anote no campo de observações qualquer erro (mensagem exata) para virar issue/correção.
