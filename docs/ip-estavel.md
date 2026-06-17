# IP estável global (mesmo IP em qualquer hub)

Por padrão, no dual-hub o IP fixo de um cliente só vale no hub onde ele foi criado; ao conectar
no outro hub, ele pega um IP dinâmico. O **IP estável global** faz cada cliente ter **o mesmo
IP em qualquer hub** — usando roteamento dinâmico (OSPF via FRR). Ver **ADR 0005**.

> Recurso **op-in**: enquanto não ativado, o dual-hub estático (ADR 0004) continua igual.
> A ativação re-renderiza o servidor e instala o FRR — faça em janela de manutenção.

## Como funciona (resumo)

- Todos os hubs do **domínio** usam o **mesmo espaço plano** (padrão `/22`, ex.: `10.80.0.0/22`).
- O cliente recebe seu IP estável por `ccd` (mesmo IP em todo hub, porque o **mapa cliente→IP é
  sincronizado** entre os hubs).
- Cada hub anuncia no OSPF **só os `/32` dos clientes conectados a ele**; o `/32` segue o cliente
  quando ele migra de hub. Um **reconciliador root** transforma a lista de conectados em rotas
  `/32`, e o **FRR** as distribui pelo **enlace dedicado** entre os hubs (interface `ovpn-link`).

## Papéis e parâmetros (por hub)

Defina-os pela **opção 10** do submenu (não edite o arquivo na mão):

- `DOMAIN_ID` — rótulo do domínio (separa implantações isoladas; o sync recusa outro domínio).
- `HUB_ID` — número do hub `1..254`, **único no domínio** (vira o `router-id` OSPF `0.0.0.<id>`;
  dois hubs com o mesmo id quebram a adjacência).
- `HUB_ROLE` — `core` (ponto de encontro do enlace) ou `spoke` (conecta no core).
- Espaço da VPN — o `/22` compartilhado (ex.: `10.80.0.0` / `255.255.252.0`).
- (Só no **spoke**) host do hub **core** — é o `remote` do enlace (separado do host dos clientes
  da opção 13, que continua sendo o endereço deste hub para os seus próprios clientes).

## Passo a passo

Tudo pelo submenu **15 — Dois hubs**. Faça em **cada hub**.

### 1. Definir os parâmetros do domínio

Submenu **15 → 10**: informe domínio, **HUB_ID único**, papel (core/spoke), o espaço `/22` e —
no spoke — o host do core. Persistido e validado (o id fora de `1..254` é recusado).

### 2. (Migrando um hub `/24` existente) Re-endereçar para o `/22`

Submenu **15 → 9**: detecta a rede atual e re-endereça os clientes **preservando o último octeto**
(`10.8.0.5` → `10.80.0.5`), com **backup** do `ccd` em `…/ccd.pre-readdress`. Como o `/22` já foi
definido no passo 1, aceite o padrão oferecido. É **server-side**: o IP não está no `.ovpn`, então
os clientes **reconectam e pegam o IP novo** sem re-emitir nada.

### 3. Ativar o IP estável global

Submenu **15 → 8 (Rede única — IP estável global)**. Sob confirmação, o instalador: instala o
**FRR**; re-renderiza o `server.conf` no modo dinâmico (status + hooks); gera o **FRR/OSPF**
(redistribui só os `/32`) e o **reconciliador** (units systemd); sobe o **enlace dedicado**
(`openvpn-server@link` no core; `openvpn-client@link` no spoke); **habilita o encaminhamento**
inter-hub (ip_forward + FORWARD); habilita os serviços e reinicia o servidor.

### 4. Sincronizar o mapa de clientes (ANTES de conectar clientes no 2º hub)

No hub **primário** (que aloca os IPs): **15 → 11** exporta o mapa (bundle verificável). Leve ao
outro hub e **15 → 12** importa. Só assim cada hub atribui o **mesmo IP** ao mesmo cliente — faça
isto **antes** de o cliente conectar no 2º hub, senão ele pega um IP dinâmico lá.

## Verificação

```
sudo systemctl status frr                  # ativo nos dois hubs
sudo systemctl status openvpn-server@link  # no CORE
sudo systemctl status openvpn-client@link  # no SPOKE
sudo vtysh -c "show ip route ospf"         # deve mostrar SÓ os /32 dos clientes
ip route show proto static                 # os /32 mantidos pelo reconciliador
```

Conecte um cliente no core (ex.: `10.80.0.5`), migre-o para o spoke e confirme que **mantém
`10.80.0.5`** e segue alcançável por esse IP. Roteiro completo em `docs/validacao-hitl.md` (T10).

## Observações

- Sem autenticação OSPF na v1 (o enlace já é cifrado pelo túnel); confinado à `ovpn-link`.
- O modo dinâmico **substitui** a troca estática de rotas do dual-hub (ADR 0004) entre os hubs.
- Para implantações isoladas, use `OVPN_DOMAIN_ID` distinto por implantação — os mapas não se
  misturam (o import recusa bundle de outro domínio).
