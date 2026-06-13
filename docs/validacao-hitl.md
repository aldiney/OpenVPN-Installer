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

- [ ] Passos:
  1. Hub A instalado (`10.8.0.0/24`). Exportar a CA: `ovpn_hub_export /tmp/ca.tar.gz`.
  2. Hub B (outra máquina) com `OVPN_SUBNET_V4=10.8.1.0`; importar a CA antes de gerar o
     servidor: `ovpn_hub_import /tmp/ca.tar.gz`.
  3. Configurar rotas: no A `ovpn_dualhub_configure 10.8.1.0 255.255.255.0`; no B
     `OVPN_SUBNET_V4=10.8.1.0 ovpn_dualhub_configure 10.8.0.0 255.255.255.0`.
  4. Gerar perfis com `OVPN_REMOTE_HOST` e `OVPN_REMOTE_HOST_2` (os dois hubs).
  5. Conectar um cliente em cada hub; pingar de A para B.
  6. Derrubar o hub A (`systemctl stop openvpn-server@server`) e observar o cliente migrar.
- [ ] Esperado: cliente do hub A alcança cliente do hub B; ao cair o A, o cliente reconecta no B.
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

Anote no campo de observações qualquer erro (mensagem exata) para virar issue/correção.
