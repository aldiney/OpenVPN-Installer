# ADR 0001 — Topologia: tun + topology subnet + client-to-client

- **Status**: Aceito
- **Data**: 2026-06-13

## Contexto

O objetivo é uma rede única onde qualquer equipamento (PC, servidor, **celular**, MikroTik)
alcança qualquer outro por IP. Existem duas abordagens no OpenVPN:

- `tap` (camada 2, bridge): coloca todos no mesmo domínio de broadcast, como um switch
  virtual. **Não é suportado por clientes móveis** (Android/iOS).
- `tun` (camada 3, roteado): rede roteada; com a diretiva `client-to-client`, o servidor
  encaminha pacotes entre clientes, e todos se enxergam.

## Decisão

Usar `dev tun` + `topology subnet` + `client-to-client`. Atribuir **IP fixo por cliente**
com `client-config-dir` + `ifconfig-push`.

## Consequências

- ✅ Funciona em todas as plataformas, incluindo celular.
- ✅ Todos os equipamentos se comunicam entre si, com endereços estáveis e previsíveis.
- ✅ Base simples para escalar (segundo hub, rotas).
- ⚠️ Não é um domínio de broadcast L2 (sem descoberta por broadcast/mDNS automática entre
  sites); a comunicação é por IP, o que atende ao objetivo.
- ⚠️ O tráfego entre clientes passa pelo hub (hub-and-spoke), não é peer-to-peer direto.
