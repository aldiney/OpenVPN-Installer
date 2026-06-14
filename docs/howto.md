# How-to: instalação e configuração

Guia prático ponta a ponta: subir o **hub** (servidor) e conectar os **equipamentos**
(Linux, Windows, macOS, Android/iOS e MikroTik). Tudo em português, com os comandos reais.

> Pré-requisitos do hub: **Debian 12+** ou **Ubuntu 24.04+**, acesso **root** (sudo) e
> internet. Os equipamentos cliente podem ser de qualquer plataforma suportada pelo OpenVPN.

---

## Parte 1 — Subir o hub (servidor)

### 1.1 Baixar o projeto

**Opção A — bootstrap (máquina nova):**

```bash
bash bootstrap.sh
```

Ele instala `git` e `gh` (pedindo confirmação), autentica no GitHub, clona o projeto em
`~/OpenVPN-Installer` e mostra como continuar.

**Opção B — clone manual:**

```bash
gh repo clone aldiney/OpenVPN-Installer ~/OpenVPN-Installer
cd ~/OpenVPN-Installer
```

### 1.2 Rodar o instalador

```bash
sudo ./install.sh
```

Aparece o menu. Escolha **1 (Instalar hub)**. O instalador vai:

1. **Verificar dependências** — lista o que falta (`openvpn`, `qrencode`) e **pede
   confirmação `[s/N]`** antes de instalar via apt. (A regra dos 7 dias é aplicada.)
2. Perguntar o **modo de IP**: `1` IPv4, `2` IPv6, `3` dual-stack.
3. Gerar a **PKI** (CA + certificado do servidor + tls-crypt).
4. Escrever o `server.conf` e **habilitar/iniciar** o serviço systemd `openvpn-server@server`.

Confirme que está no ar:

```bash
sudo systemctl status openvpn-server@server
ip addr show tun0           # deve existir a interface tun0 com 10.8.0.1
```

### 1.3 Liberar a porta no firewall

A porta padrão é **1194/UDP**. Abra no firewall do hub e, se houver, no provedor/nuvem:

```bash
# ufw
sudo ufw allow 1194/udp
# nftables/iptables: garanta que 1194/udp de entrada esteja liberada
```

> Importante: o `remote` dos clientes precisa apontar para um **IP público** ou **domínio**
> que alcance o hub. Tenha esse endereço em mãos para o próximo passo.

---

## Parte 2 — Adicionar um equipamento (gerar o perfil)

No menu, escolha **2 (Adicionar cliente)** e informe um nome (ex.: `notebook`, `celular`).
Na primeira vez, o instalador pergunta o **IP/domínio do hub** (vai para o `remote` do perfil).
Ele também pergunta se **este cliente deve sair pela internet do hub (full-tunnel)** — veja
"Saída para a internet" abaixo.

Resultado:

- `/etc/openvpn/clients/NOME.ovpn` — perfil com os certificados **embutidos** (um arquivo só);
- uma **cópia no seu home** (`~/NOME.ovpn`), fácil de transferir;
- um **QR Code** no terminal (para o celular escanear).

Use **3 (Listar clientes)** para ver os nomes e os **IPs fixos** de cada um.

---

## Parte 3 — Conectar em cada tipo de equipamento

Transfira o `NOME.ovpn` para o equipamento (scp, pendrive, etc.) — exceto no celular, que
pode escanear o QR.

### Linux

```bash
sudo apt install -y openvpn
sudo openvpn --config NOME.ovpn          # teste em primeiro plano
# para deixar como serviço:
sudo cp NOME.ovpn /etc/openvpn/client/NOME.conf
sudo systemctl enable --now openvpn-client@NOME
```

### Windows

1. Instale o **OpenVPN Connect** (ou o OpenVPN GUI) de `openvpn.net`.
2. **Import Profile → from file** e selecione o `NOME.ovpn`.
3. Clique em conectar.

### macOS

1. Instale o **OpenVPN Connect** (App Store / openvpn.net) ou o **Tunnelblick**.
2. Importe o `NOME.ovpn` e conecte.

### Android / iOS

1. Instale o **OpenVPN Connect** (Play Store / App Store).
2. **Import → QR code** e escaneie o QR mostrado no menu (opção 2), **ou** importe o arquivo
   `NOME.ovpn`.
3. Conecte.

### MikroTik (RouterOS)

Use a opção **7 (Adicionar cliente MikroTik)** e siga o
[guia do MikroTik](mikrotik-guide.md): importe os certificados e cole o script `.rsc`.

---

## Parte 4 — Verificar a rede única

Cada equipamento conectado recebe um IP fixo na faixa `10.8.0.0/24` (o hub é `10.8.0.1`).
A partir de **qualquer** equipamento conectado, você deve alcançar **qualquer outro** pelo IP:

```bash
ping 10.8.0.2            # ping em outro equipamento da VPN
ssh usuario@10.8.0.3     # acessar por SSH
```

Veja os IPs com a opção **3 (Listar clientes)** no hub.

---

## Opções extras (menu)

- **5 / 6** — ativar/desativar a **saída para a internet** por este hub (NAT). Informe a
  interface WAN (ex.: `eth0`). Isso só **habilita a capacidade** de sair pela internet do
  hub; **quem usa é decidido por cliente**.
  - **Full-tunnel por cliente**: ao adicionar um cliente, responda `s` para "sair pela
    internet do hub". Só esse cliente recebe `redirect-gateway` + DNS (via o `ccd` dele);
    os demais ficam **split-tunnel** (usam a própria internet e só alcançam a rede VPN).
  - Em hosts com **UFW**, o módulo ajusta a política de forward automaticamente (senão o
    UFW descartaria o tráfego roteado).
- **8** — **revogar** o acesso de um equipamento (remove o perfil e coloca o certificado na
  CRL).
- **9** — **desinstalar** o hub (escolhe preservar ou remover a PKI).
- **10** — **verificar/instalar dependências** a qualquer momento.
- **11** — **atualizar/migrar instalação** (ver abaixo).

## Atualizar uma instalação existente

Depois de um `git pull` no hub, aplique as correções na instalação **sem regerar nada de
cliente**:

```bash
cd ~/OpenVPN-Installer && git pull
sudo ./install.sh        # se a instalação for de versão anterior, ele OFERECE migrar
# ou, no menu, escolha a opção 11 (Atualizar/migrar instalação)
```

O upgrade é **idempotente** e **nunca quebra clientes**: nunca toca na CA nem nos
certificados/`.ovpn` dos clientes; no máximo **reemite o certificado do servidor** (mesma
CA — os clientes seguem confiando), **acrescenta** diretivas faltantes (ex.: `mssfix`) e
**abre a porta** no firewall. Mudanças que alteram rota/comportamento (ex.: `redirect-gateway`
global) são apenas **reportadas**, nunca aplicadas sozinhas. O serviço só reinicia se algo
mudou (os clientes reconectam sozinhos).

## Dois hubs (redundância)

Para não depender de um único ponto de conexão, veja [dual-hub.md](dual-hub.md).

## Problemas?

Veja [troubleshooting.md](troubleshooting.md).
