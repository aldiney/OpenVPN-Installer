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

## Endereçar um hub ESPECÍFICO (IP de identidade)

Como o servidor de **todo** hub fica no `.1` do espaço compartilhado, o `.1` não serve para falar
com um hub em particular. Por isso, cada hub ganha um **IP de identidade próprio** — um `/32` fixo,
reservado no **topo do espaço** e derivado do `HUB_ID`:

| Hub | `HUB_ID` | IP de identidade (ex.: `10.80.0.0/22`) |
|-----|----------|-----------------------------------------|
| A   | 1        | `10.80.3.241`                            |
| B   | 2        | `10.80.3.242`                            |
| N   | `id`     | `<broadcast> - 15 + id`                  |

Esse IP fica numa interface dummy (`ovpn-self`) e é anunciado pelo OSPF (`redistribute connected`,
filtrado para `/32`), então **de qualquer cliente**, em **qualquer hub**, ele cai sempre no hub
certo. Os **15 endereços do topo** (`.240`–`.254` num `/22`) ficam reservados para isso — o
alocador de clientes para antes deles. Veja o IP deste hub no `sudo openvpn-installer status`
(linha "IP deste hub (VPN)").

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

### 4. Sincronizar o mapa de clientes (automático, com 1 autorização)

O mapa é **sincronizado sozinho**: o spoke puxa o mapa do primário pelo enlace (timer a cada
~2 min), e o primário **republica** a cada cliente criado/revogado. Só falta **autorizar a chave**
uma vez:

1. Ao ativar o spoke (passo 3), ele gera uma **chave SSH** e mostra a **pública** no terminal.
2. No **primário**: menu **15 → 13** (Autorizar spoke) → cole essa chave pública. Pronto — a
   chave fica restrita (forced-command: só LÊ o mapa, sem shell), e o spoke passa a puxar o mapa
   automaticamente pelo enlace já cifrado.

Assim cada hub atribui o **mesmo IP** ao mesmo cliente, sem passo manual a cada cliente novo.

> **Fallback manual**: se preferir (ou para o bootstrap inicial), dá para sincronizar à mão —
> **15 → 11** exporta o bundle no primário e **15 → 12** importa no spoke.

## Verificação

A forma rápida — **um comando** que resume enlace, OSPF, reconciliador e mapsync:
```
sudo openvpn-installer status
```
(ou a opção **4 — Status do servidor** no menu, que inclui o resumo quando o modo dinâmico está
ativo). Para detalhes:
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
