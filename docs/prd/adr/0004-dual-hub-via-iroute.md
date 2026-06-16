# ADR 0004 — Dual-hub: enlace via cliente+iroute e rede da VPN configurável

- **Status**: Aceito
- **Data**: 2026-06-15

## Contexto

A entrega original do dual-hub (ADR 0003) deixou o **túnel site-to-site** entre os hubs
sem mecanismo definido — o `ovpn_dualhub_configure` só anexa rotas, assumindo um enlace que
não existia. Uma auditoria confirmou que o recurso não era seguível de ponta a ponta.

## Decisão

### Enlace entre os hubs: hub B como **cliente** do hub A, com `iroute`

Em vez de um daemon p2p dedicado, o hub B conecta-se ao **servidor já existente** do hub A
(porta 1194) como um cliente comum, e a troca de rotas usa o mecanismo nativo do OpenVPN:

- No **hub A**: emite-se um certificado de cliente para o peer (ex.: `hub-b`), com IP fixo
  via `ccd`, e a entrada do `ccd` recebe `iroute <sub-rede-do-hub-B>` — assim o OpenVPN do
  hub A sabe que aquela sub-rede está atrás daquela conexão. No `server.conf` do hub A:
  `route <sub-rede-B>` (rota no kernel) + `push "route <sub-rede-B>"` (clientes de A aprendem).
- No **hub B**: roda um `openvpn-client@` apontando para o hub A (usando o perfil do peer).
  No `server.conf` do hub B: `route <sub-rede-A>` + `push "route <sub-rede-A>"`.

Vantagens: reaproveita PKI, `ccd`, perfis e a porta 1194 já aberta; o cert do peer é
`clientAuth` (que já geramos corretamente); o tráfego A↔B usa `client-to-client` interno do
OpenVPN. No hub B, o forward entre o tun dos clientes e o tun do enlace exige `ip_forward` +
liberação no UFW (reaproveitar `ovpn_sysctl_set` e a regra `ufw route allow`).

### Rede da VPN configurável na instalação

A sub-rede (`OVPN_SUBNET_V4`) passa a ser **perguntada e persistida** na instalação (com
padrão `10.8.0.0/24`), e o prefixo (`OVPN_VPN_PREFIX_V4`) é derivado dela. Isso permite o
hub B usar uma sub-rede distinta (ex.: `10.8.1.0/24`) sem `sudo OVPN_SUBNET_V4=... ./install.sh`,
e é validado contra sobreposição no fluxo de dual-hub (`ovpn_dualhub_validate_subnets`).

### CA compartilhada com `ca.key`

O `hub_sync` ganha um modo explícito de **bundle de CA mestra** que inclui a `ca.key`
(além de `ca.crt` + `tls-crypt`), com checksum, para o hub B emitir o próprio cert de
servidor sob a CA comum. O par antigo `ovpn_pki_export_ca/import_ca` (sem checksum) é
aposentado em favor do `hub_sync`.

## Consequências

- ✅ Dual-hub vira recurso seguível pelo menu (submenu "Dois hubs"), sem `source` manual.
- ✅ Menos peças novas que um daemon dedicado; sem porta extra no hub A.
- ⚠️ Transportar a `ca.key` é sensível — o modo de bundle mestre é explícito e verificável.
- ⚠️ No hub B há forward tun↔tun a liberar (ip_forward + UFW), mas sem NAT.
- ⚠️ Failover assimétrico: o ponto de encontro inter-hub é o hub A; clientes ainda migram
  entre hubs para a própria sub-rede. Mesh real (OSPF, N hubs) fica como evolução futura.
