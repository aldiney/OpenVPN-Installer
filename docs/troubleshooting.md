# Solução de problemas

Guia rápido para os problemas mais comuns. Mensagens do instalador são sempre em pt-BR.

## Instalação / dependências

- **"Sistema não suportado"** — o hub só roda em **Debian 12+** ou **Ubuntu 24.04+**.
  Clientes podem ser de qualquer plataforma.
- **Instalação travou pedindo confirmação** — o instalador nunca instala nada sem você
  responder `s`. Leia o plano exibido e confirme.
- **Pacote recusado pela "regra dos 7 dias"** — por segurança, não instalamos pacotes
  lançados há menos de 7 dias. Aguarde ou ajuste a fonte do pacote.

## Conexão dos clientes

- **Cliente não conecta** — confira:
  - o `remote` no `.ovpn` aponta para o IP/domínio correto do hub (`OVPN_REMOTE_HOST`);
  - a porta (`1194/udp` por padrão) está liberada no firewall do hub;
  - o serviço está ativo: `systemctl status openvpn-server@server`.
- **Conecta mas não enxerga outros equipamentos** — o servidor precisa de
  `client-to-client` (já incluído) e cada cliente recebe um IP fixo; verifique com a opção
  "Listar clientes".
- **Acesso de um equipamento perdido/comprometido** — use "Revogar cliente": o perfil é
  removido e o certificado entra na CRL.

## Celular

- **QR não aparece** — instale o `qrencode` no hub. Sem ele, transfira o `.ovpn` manualmente.
- Use o app **OpenVPN Connect** (Android/iOS) e importe o `.ovpn` (ou escaneie o QR).

## MikroTik

- Veja o guia dedicado: [mikrotik-guide.md](mikrotik-guide.md). Pontos comuns:
  UDP exige RouterOS v7+, `tls-crypt` exige v7.17+, e o relógio do roteador precisa estar
  correto (validade dos certificados).

## Dois hubs (dual-hub)

- Veja [dual-hub.md](dual-hub.md). Erros comuns: sub-redes iguais (não são permitidas) e
  CA diferente entre os hubs (use o bundle do `hub_sync`).

## Saída para a internet

- **Clientes não navegam após ativar** — confira a interface WAN informada e se o
  encaminhamento de pacotes está ativo (`net.ipv4.ip_forward=1`). Ao desativar, a regra de
  NAT é removida.
- **Full-tunnel sem internet (mas `ping` por IP funciona) em host com UFW** — é o caso mais
  comum: o UFW tem `FORWARD policy DROP` e descarta o tráfego TCP/UDP encaminhado da VPN (só
  passa ICMP e conexões já estabelecidas). O masquerade existe, mas o pacote morre no filtro
  FORWARD antes do NAT. Sintoma: sem DNS, sem web, mas `ping <ip>` responde.
  - **Correção pelo menu**: rode de novo **5 (Ativar saída para a internet)** — o código
    agora cria `ufw route allow in on tun0 out on <WAN>` e grava o NAT no `before.rules`
    (persistente, sobrevive ao reboot).
  - **Manual (equivalente)**: `sudo ufw route allow in on tun0 out on <WAN> && sudo ufw reload`.
  - Reconecte o cliente e teste `nslookup` / `mtr`.

## MTU: HTTPS/transferências grandes travando (ping/SSH OK)

Se **ping, SSH e traceroute funcionam**, mas **HTTPS ou transferências grandes ficam
penduradas** dentro da VPN, é o sintoma clássico de **MTU/MSS**: pacotes próximos do MTU são
descartados no caminho.

- O `server.conf` já inclui **`mssfix`** (padrão `1420`) para limitar o tamanho do pacote e
  evitar isso. Se ainda ocorrer em algum caminho, reduza o valor (ex.: `OVPN_MSSFIX=1380`)
  e reinstale/re-renderize a configuração.
- Vale para IPv4 e IPv6.

## Desinstalação

- "Desinstalar o hub" para o serviço e remove a configuração. Você escolhe **preservar** ou
  **remover** a PKI (certificados). Preserve se pretende reinstalar mantendo os clientes.
