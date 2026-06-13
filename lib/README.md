# lib/ — Módulos

Cada arquivo `*.sh` aqui é um **módulo profundo**: uma interface pequena e estável que
esconde bastante complexidade. Os módulos são carregados com `source`, não executados
diretamente.

## Convenções

- Funções públicas: `ovpn_<modulo>_<verbo>` (ex.: `ovpn_pki_build_ca`).
- Funções internas (privadas): prefixo `_ovpn_...`.
- Texto para o operador e comentários em **pt-BR**; identificadores em inglês.
- Todo comando que toca o sistema (apt, openvpn, openssl, systemctl, nft...) deve passar
  por um módulo, para que os testes possam substituí-lo por _stubs_.

## Módulos previstos

| Arquivo | Responsabilidade |
|---|---|
| `core.sh` | Constantes de caminho, `require_root`, tratamento de erro. |
| `log.sh` | Mensagens coloridas (info/aviso/erro/ok/passo). |
| `ui.sh` | Banner, menu numerado, confirmação `[s/N]`. |
| `os_detect.sh` | Gate de SO (Debian 12+ / Ubuntu 24.04+). |
| `deps.sh` | Detecção de dependências, regra dos 7 dias, instalar só após confirmação. |
| `pki.sh` | CA/servidor/cliente (ECDSA), tls-crypt, exportar/importar CA. |
| `wizard_ipproto.sh` | Escolha IPv4-only / IPv6-only / dual-stack. |
| `server_config.sh` | Geração do `server.conf` (tun + topology subnet + client-to-client). |
| `ccd.sh` | IPs fixos por cliente (`client-config-dir` + `ifconfig-push`). |
| `client_profile.sh` | Geração do `.ovpn`, QR (qrencode), revogação. |
| `mikrotik_profile.sh` | Perfil RouterOS (cipher explícito, sem LZO) + script `.rsc`. |
| `gateway.sh` | Saída para internet opcional (NAT nft/iptables). |
| `hub_sync.sh` | Bundle de CA compartilhada entre hubs. |
| `dualhub.sh` | Segundo hub ativo-ativo (site-to-site + rotas). |
| `controller.sh` | Orquestradores finos que ligam o menu aos módulos. |
