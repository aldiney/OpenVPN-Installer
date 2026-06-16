# Dois hubs ativo-ativo

Para não depender de um único ponto de conexão, a rede pode ter **dois hubs ativos ao
mesmo tempo**. Os clientes se distribuem entre eles e, se um cair, migram para o outro —
mantendo todos na mesma rede.

Todo o fluxo é feito pelo **menu** do instalador, na opção **15 — Dois hubs (ativo-ativo)**.

## Como funciona (ADR 0004)

- Cada hub usa uma **sub-rede distinta** (ex.: hub A = `10.8.0.0/24`, hub B = `10.8.1.0/24`).
  A rede da VPN é escolhida na instalação (opção 1).
- Os dois hubs compartilham a **mesma CA**, transferida pelo bundle de **CA mestra**
  (inclui a `ca.key`, para o hub B emitir o próprio certificado de servidor).
- O **enlace** entre os hubs reusa o mecanismo nativo do OpenVPN: o **hub B conecta-se ao
  hub A como um cliente comum**, e a sub-rede do hub B é roteada via `iroute` no hub A. Não
  há porta nova a abrir: o hub B conecta para fora, na porta 1194 já existente do hub A.
- Cada hub anuncia aos seus clientes a rota para a sub-rede do outro, então um cliente do
  hub A alcança um cliente do hub B.
- Os perfis de cliente listam **os dois hubs como `remote`** (failover com `remote-random`).

> **Papéis:** o **hub A** é o ponto de encontro (recebe o enlace); o **hub B** é quem
> conecta. O failover é ativo-ativo para os clientes; o enlace inter-hub passa pelo hub A.

## Passo a passo

### 1. Instale o hub A (ponto de encontro)

1. `sudo openvpn-installer` → opção **1 (Instalar hub)**. Quando perguntar a **rede da VPN**,
   use a do hub A (ex.: `10.8.0.0`).
2. Defina o IP/domínio público do hub A: opção **13 (Alterar host/IP do hub)** — usado no
   `remote` dos perfis.

### 2. Leve a CA mestra para o hub B

No **hub A**, menu **15 → 1 (Exportar CA mestra)**. Informe um arquivo de saída
(ex.: `/root/ca-mestra.tar.gz`) e confirme. O bundle contém a **chave privada da CA** —
transfira-o ao hub B por um canal seguro (ex.: `scp`) e apague-o depois.

### 3. Instale o hub B (quem conecta)

No **hub B**, na ordem:

1. `sudo openvpn-installer` → menu **15 → 3 (Importar CA de um bundle)** → aponte para o
   `ca-mestra.tar.gz` transferido. Isso instala a CA compartilhada (`ca.crt` + `ca.key`) e
   a chave `tls-crypt` comum.
2. Opção **1 (Instalar hub)** → quando perguntar a **rede da VPN**, use uma **diferente**
   da do hub A (ex.: `10.8.1.0`). A instalação **mantém** a CA e o `tls-crypt` importados
   (são idempotentes) e emite o certificado de servidor do hub B sob a CA compartilhada.
3. Defina o IP/domínio público do hub B: opção **13**.

### 4. Registre o enlace no hub A

No **hub A**, menu **15 → 4 (Registrar hub par)**:

- Nome do peer: ex. `hub-b`.
- Sub-rede do hub par: a do hub B (ex.: `10.8.1.0`), máscara `255.255.255.0`.

Isso emite o **perfil de conexão do enlace** (`hub-b.ovpn`, com um único `remote` = hub A),
marca a sub-rede do hub B com `iroute` e instala/anuncia a rota dessa sub-rede no hub A.
Transfira o `hub-b.ovpn` (mostrado no fim) para o hub B.

### 5. Suba o enlace no hub B

No **hub B**:

1. Instale o perfil do enlace como serviço de cliente e suba-o:

   ```
   sudo cp hub-b.ovpn /etc/openvpn/client/hub-b.conf
   sudo systemctl enable --now openvpn-client@hub-b
   ```

2. Descubra a **interface do enlace** que subiu (além do `tun0` do servidor):

   ```
   ip -o link show | awk -F': ' '/tun/ {print $2}'
   ```

   Normalmente é `tun1`. Use esse nome nos passos seguintes.

3. Menu **15 → 6 (Ativar encaminhamento do enlace)** → informe a interface do enlace
   (ex.: `tun1`). Habilita e persiste o `ip_forward` e libera o forward (sem NAT).
4. Menu **15 → 5 (Anunciar a sub-rede do hub par aos clientes)** → informe a sub-rede do
   **hub A** (ex.: `10.8.0.0`). Assim, os clientes do hub B aprendem a alcançar o hub A.
   (A rota de kernel para o hub A já chega automaticamente pelo enlace.)

### 6. Gere os perfis de cliente com os dois hubs

Em **um** dos hubs, defina o 2º hub e gere os clientes:

1. Menu **15 → 7 (Definir/alterar o 2º hub dos clientes)** → informe o host do **outro** hub.
2. Opção **2 (Adicionar cliente)** — o `.ovpn` sai com os **dois `remote`** e
   `remote-random`; o cliente tenta um e, se cair, migra para o outro.

## Verificação rápida

- Conecte um cliente em cada hub e faça `ping` de um para o outro (IPs `10.8.0.x` ↔ `10.8.1.x`).
- Derrube um hub (`sudo systemctl stop openvpn-server@server`) e confirme que o cliente
  reconecta no outro.

## Observações

- As sub-redes dos dois hubs **não podem se sobrepor** (validado ao registrar o peer).
- O bundle de **CA mestra** contém a chave privada da CA: trate-o como segredo.
- Failover assimétrico: o ponto de encontro inter-hub é o hub A; os clientes ainda migram
  entre os hubs para a própria sub-rede. Para 3+ hubs, rotas estáticas não escalam — aí
  entra roteamento dinâmico (OSPF), fora do escopo desta versão.
