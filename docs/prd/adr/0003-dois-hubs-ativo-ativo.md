# ADR 0003 — Redundância: dois hubs ativo-ativo

- **Status**: Aceito
- **Data**: 2026-06-13

## Contexto

Um único hub é ponto único de falha. O operador quer que **mais de um equipamento possa ser
o ponto de conexão** dos demais (redundância e múltiplos pontos de entrada). O OpenVPN
community **não faz mesh automático**; as opções reais são:

- Hub único (sem redundância).
- **Dois hubs ativo-ativo**: ambos ativos, clientes distribuídos, com túnel entre eles.
- Mesh real com roteamento dinâmico (OSPF/BGP) entre vários gateways — bem mais complexo.

## Decisão

Adotar **dois hubs ativo-ativo** na v1:

- Cada hub tem uma **sub-rede distinta** (ex.: `10.8.0.0/24` e `10.8.1.0/24`).
- Um **túnel site-to-site** liga os dois hubs, com **troca de rotas estáticas**, para que um
  cliente do hub A alcance um cliente do hub B.
- **CA compartilhada** entre os hubs, distribuída via bundle verificável (`hub_sync`).
- Os perfis de cliente listam **os dois hubs como `remote`**, permitindo migração se um cair.

Mesh real com OSPF fica como **evolução futura** (fora do escopo da v1).

## Consequências

- ✅ Sem ponto único de falha; múltiplos pontos de entrada.
- ✅ Rotas estáticas são simples e suficientes para dois hubs.
- ⚠️ Sub-redes precisam ser não sobrepostas — validado pelo módulo `dualhub`.
- ⚠️ A CA compartilhada precisa de transporte seguro (bundle com checksum em `hub_sync`).
- ⚠️ Para 3+ hubs, rotas estáticas não escalam bem — daí a evolução futura para OSPF.
