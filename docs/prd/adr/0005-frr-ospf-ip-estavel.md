# ADR 0005 — IP estável global por cliente (FRR + OSPF + reconciliador)

- **Status**: Aceito
- **Data**: 2026-06-16
- **Relacionado**: estende o ADR 0004 (dual-hub via cliente+iroute).

## Contexto

No dual-hub do ADR 0004 o IP fixo de um cliente vive só no `ccd` do hub de origem; ao
conectar no outro hub, ele pega IP dinâmico (não há `ccd-exclusive`; o roteamento entre hubs
é por sub-rede). O "IP fixo" não vale ao migrar de hub — e com `remote-random` isso acontece
até sem falha. Queremos que **cada cliente tenha o MESMO IP em qualquer hub**, de forma
escalável para (i) uma VPN única que cresce para N hubs e (ii) várias implantações isoladas.

## Decisão

### IP estável = IP do túnel, num espaço plano compartilhado
O IP estável é o **próprio IP do túnel** (entregue por `ccd`/`ifconfig-push`), tirado de um
**espaço plano compartilhado** por todos os hubs do domínio (padrão `/22`, ex.: `10.80.0.0/22`).
Não há endereço de identidade secundário no cliente — celular/MikroTik não rodam up-script. O
mesmo IP funciona em qualquer hub porque o **mapa cliente→IP é compartilhado** (alocação central
no hub primário + sync por bundle verificável marcado por `DOMAIN_ID` — ver `lib/route_sync.sh`).

### Cada hub anuncia só os /32 dos seus clientes (OSPF via FRR)
Cada hub anuncia no OSPF **apenas os `/32` dos clientes conectados a ele**; o `/22` conectado do
`tun` **não** é redistribuído (filtrado por prefix-list/route-map — ver `lib/frr.sh`). O `/32`
(mais específico) vence o `/22` nos outros hubs, então o tráfego segue o cliente que migrou.

### Reconciliador root resolve o priv-drop
O OpenVPN roda como `nobody`, então os hooks de connect **não** podem mexer em rota. Os hooks
(triviais, auditáveis) só **sinalizam** um **reconciliador root** (`lib/route_reconcile.sh` +
units systemd) que lê o `status` do OpenVPN e mantém as rotas `/32` de kernel (idempotente,
auto-corretivo). O FRR redistribui essas `/32`. Disparo: `systemd.path` (no spool) + `.timer`.

### Enlace inter-hub DEDICADO para o OSPF
O OSPF precisa de uma interface só entre hubs (clientes não falam OSPF). Por isso o transporte é
uma **2ª instância OpenVPN dedicada** (`lib/link.sh`), interface `ovpn-link`, porta e sub-rede de
transporte próprias, só para hubs (hub-and-spoke: spokes → core). O OSPF roda **só** na
`ovpn-link` (`passive-interface default`), em `point-to-multipoint`. Sem autenticação OSPF na v1
(o transporte já é cifrado pelo túnel `tls-crypt`); auth message-digest fica como evolução.

### Op-in, e relação com o modo estático
`OVPN_DYNROUTING=off` por padrão preserva o dual-hub **estático** (ADR 0004) intacto. No modo
**dinâmico**, o roteamento OSPF **substitui** a troca estática de rotas (`route`/`push`/`iroute`
de cliente). Ativar é uma ação explícita do operador (opção de menu, com confirmação) — nunca
migração silenciosa. Migrar um hub `/24` existente para o `/22` é **server-side** e preserva o
último octeto (`10.8.0.5` → `10.80.0.5`); como o IP não está no `.ovpn`, os clientes reconectam
e pegam o IP novo sem re-emitir nada (ver `ovpn_ccd_readdress`).

## Consequências

- ✅ Mesmo IP em qualquer hub; escala para N hubs e para implantações isoladas (por `DOMAIN_ID`).
- ✅ Sem atrito no cliente (o IP estável é o do túnel) — funciona em celular/MikroTik.
- ⚠️ Nova dependência: **FRR** (instalado pelo gate de deps, regra dos 7 dias).
- ⚠️ `script-security 2` + hooks — mitigado: hooks só sinalizam; o reconciliador root tem
  superfície mínima (lê o `status`, mexe só em rotas `proto static` que ele marca).
- ⚠️ Vários pontos exigem **validação HITL** (topologia `/22`, redistribuição só dos `/32`,
  convergência de roam, celular/MikroTik) — ver `docs/validacao-hitl.md`.
