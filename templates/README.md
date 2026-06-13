# templates/ — Modelos de configuração

Modelos usados para gerar arquivos finais. Variáveis no formato `{{NOME}}` são
substituídas pelos módulos em `lib/`.

| Arquivo | Gera |
|---|---|
| `server.conf.tmpl` | Configuração do servidor OpenVPN (`/etc/openvpn/server/`). |
| `client.ovpn.tmpl` | Perfil `.ovpn` de cliente padrão (certs inline). |
| `mikrotik.ovpn.tmpl` | Perfil `.ovpn` compatível com RouterOS. |
| `mikrotik.rsc.tmpl` | Comandos RouterOS prontos para colar. |
| `ccd-client.tmpl` | Entrada de `client-config-dir` (IP fixo do cliente). |

Os modelos são preenchidos em tempo de execução; nada de segredo é versionado aqui.
