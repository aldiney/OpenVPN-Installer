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

Defina antes de ativar (persistidos em `installer.conf`):

- `OVPN_DOMAIN_ID` — rótulo do domínio (separa implantações isoladas; o sync recusa outro domínio).
- `OVPN_HUB_ID` — número do hub (vira o `router-id` OSPF; `1` é o primário/alocador).
- `OVPN_HUB_ROLE` — `core` (ponto de encontro do enlace) ou `spoke` (conecta no core).
- Espaço da VPN — o `/22` compartilhado (ex.: `OVPN_SUBNET_V4=10.80.0.0`, `OVPN_NETMASK_V4=255.255.252.0`).

## Passo a passo

Tudo pelo submenu **15 — Dois hubs**.

### 1. (Migrando um hub `/24` existente) Re-endereçar para o `/22`

Submenu **15 → 9**: detecta a rede atual, re-endereça os clientes **preservando o último octeto**
(`10.8.0.5` → `10.80.0.5`), com **backup** do `ccd` em `…/ccd.pre-readdress`. É **server-side**:
o IP não está no `.ovpn`, então os clientes **reconectam e pegam o IP novo** sem re-emitir nada.

### 2. Ativar o IP estável global (em cada hub)

Submenu **15 → 8 (Rede única — IP estável global)**. Sob confirmação, o instalador:
- instala o **FRR** (gate de dependências, regra dos 7 dias);
- re-renderiza o `server.conf` no modo dinâmico (status + hooks);
- gera o **FRR/OSPF** (redistribui só os `/32`) e instala o **reconciliador** (units systemd);
- sobe o **enlace dedicado** (`openvpn-server@link` no core; `openvpn-client@link` no spoke);
- habilita os serviços e reinicia o servidor.

No **spoke**, defina antes o host do core (`OVPN_REMOTE_HOST`, opção 13) — é o `remote` do enlace.

### 3. Sincronizar o mapa de clientes

O hub **primário** aloca os IPs; leve o mapa aos demais (bundle verificável, como a CA), para
todos atribuírem o mesmo IP ao mesmo cliente.

## Verificação

```
sudo systemctl status frr openvpn-server@link
sudo vtysh -c "show ip route ospf"        # deve mostrar SÓ os /32 dos clientes
ip route show proto static                 # os /32 mantidos pelo reconciliador
```

Conecte um cliente no core (ex.: `10.80.0.5`), migre-o para o spoke e confirme que **mantém
`10.80.0.5`** e segue alcançável por esse IP. Roteiro completo em `docs/validacao-hitl.md` (T10).

## Observações

- Sem autenticação OSPF na v1 (o enlace já é cifrado pelo túnel); confinado à `ovpn-link`.
- O modo dinâmico **substitui** a troca estática de rotas do dual-hub (ADR 0004) entre os hubs.
- Para implantações isoladas, use `OVPN_DOMAIN_ID` distinto por implantação — os mapas não se
  misturam (o import recusa bundle de outro domínio).
