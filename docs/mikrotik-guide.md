# Guia: conectar um MikroTik (RouterOS) à rede

Este guia mostra como ligar um roteador MikroTik à sua rede OpenVPN. O instalador
gera, para cada cliente MikroTik, dois arquivos em `/etc/openvpn/clients/`:

- `NOME.mikrotik.ovpn` — perfil compatível com RouterOS (cipher explícito, sem LZO).
- `NOME.rsc` — comandos RouterOS prontos para colar no terminal.

## Requisitos de versão

- **RouterOS v7+** para usar **UDP** (em versões antigas, use **TCP**).
- **RouterOS v7.17+** para usar **tls-crypt** (recomendado).
- O RouterOS **não** faz negociação de cipher (NCP) nem suporta **LZO** — por isso o
  perfil já vem com o `cipher` explícito e sem compressão.
- O relógio do roteador precisa estar correto (a validade dos certificados é checada).

## Passo a passo

1. **Gere o perfil** no hub, pelo menu do instalador (opção "Adicionar cliente MikroTik")
   ou com a função `ovpn_mikrotik_create NOME`.

2. **Copie os certificados para o MikroTik.** No RouterOS, em `Files`, envie o `ca.crt`
   e o certificado/chave do cliente (extraídos do `.ovpn`), e importe em `/certificate`:

   ```
   /certificate import file-name=ca.crt
   /certificate import file-name=NOME.crt
   /certificate import file-name=NOME.key
   ```

3. **Crie o cliente OpenVPN.** Cole o conteúdo do arquivo `NOME.rsc` no terminal do
   RouterOS (ajuste `connect-to`/`port` se necessário). Ele roda algo como:

   ```
   /interface ovpn-client add name=ovpn-NOME connect-to=SEU-HUB port=1194 \
       protocol=udp mode=ip user="NOME" \
       cipher=AES-256-GCM auth=SHA256 certificate=NOME-cert \
       verify-server-certificate=yes disabled=no
   ```

4. **Verifique a conexão:**

   ```
   /interface ovpn-client print
   /ip address print
   ```

   O cliente deve receber o IP fixo definido para ele na VPN.

## Observações sobre cipher/auth

- O `cipher` do perfil precisa estar entre os `data-ciphers` aceitos pelo servidor.
  O padrão do projeto é `AES-256-GCM` (compatível com o servidor e com RouterOS v7+).
- Em GCM, a autenticação é embutida no próprio cipher; o `auth` aqui vale para o canal
  de controle. Em RouterOS muito antigos, prefira **AES-256-CBC** com `auth SHA256`
  (e ajuste os `data-ciphers` do servidor para aceitá-lo).

## Solução de problemas

- **Não conecta por UDP:** seu RouterOS pode ser anterior ao v7 — use TCP.
- **Erro de certificado:** confira o relógio do roteador e se a CA foi importada.
- **tls-crypt não aceito:** atualize para RouterOS v7.17+ ou gere um perfil sem tls-crypt.
