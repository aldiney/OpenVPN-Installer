# Dois hubs ativo-ativo

Para não depender de um único ponto de conexão, a rede pode ter **dois hubs ativos ao
mesmo tempo**. Os clientes se distribuem entre eles e, se um cair, migram para o outro —
mantendo todos na mesma rede.

## Como funciona

- Cada hub usa uma **sub-rede distinta** (ex.: hub A = `10.8.0.0/24`, hub B = `10.8.1.0/24`).
- Os dois hubs compartilham a **mesma CA** (transferida pelo bundle do `hub_sync`).
- Um **túnel site-to-site** liga os hubs; cada um anuncia a rota para a sub-rede do outro,
  então um cliente do hub A alcança um cliente do hub B.
- Os perfis de cliente listam **os dois hubs como `remote`** (variável `OVPN_REMOTE_HOST_2`).

## Passo a passo (resumo)

1. **Instale o hub A** normalmente (sub-rede padrão `10.8.0.0/24`).
2. **Exporte a CA do hub A:**

   ```
   ovpn_hub_export /caminho/bundle-ca.tar.gz
   ```

3. **No hub B**, instale com uma **sub-rede diferente** (`OVPN_SUBNET_V4=10.8.1.0`) e
   **importe a CA** antes de gerar os certificados do servidor:

   ```
   ovpn_hub_import /caminho/bundle-ca.tar.gz
   ```

4. **Configure as rotas entre os hubs** (em cada hub, apontando para a sub-rede do outro):

   ```
   # no hub A:
   ovpn_dualhub_configure 10.8.1.0 255.255.255.0
   # no hub B:
   OVPN_SUBNET_V4=10.8.1.0 ovpn_dualhub_configure 10.8.0.0 255.255.255.0
   ```

5. **Gere os perfis de cliente com os dois hubs** definindo `OVPN_REMOTE_HOST` e
   `OVPN_REMOTE_HOST_2` — o `.ovpn` terá os dois `remote` e o cliente migra sozinho.

## Observações

- As sub-redes dos dois hubs **não podem se sobrepor** (o `ovpn_dualhub_configure` valida).
- O túnel site-to-site em si (uma conexão OpenVPN ponto-a-ponto entre os hubs) é montado
  pelo operador conforme a topologia da rede; as rotas geradas aqui assumem esse túnel.
- Para 3+ hubs, rotas estáticas não escalam bem — aí entra roteamento dinâmico (OSPF),
  fora do escopo desta versão.
