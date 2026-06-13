# PRD — OpenVPN-Installer

> Documento de requisitos do produto. Gerado a partir do contexto do projeto (skill
> `to-prd`). O escopo aqui descrito é fatiado em issues pela skill `to-issues`.

## Problem Statement

O operador tem vários equipamentos espalhados — computadores, servidores, celulares e
roteadores MikroTik — em redes diferentes (casa, escritório, datacenter, 4G/5G). Hoje ele
não consegue acessar um equipamento a partir de outro de forma simples: cada um está atrás
de um NAT/firewall diferente, sem IP estável, e montar isso manualmente com OpenVPN exige
conhecimento de PKI, roteamento e configuração que é trabalhoso e fácil de errar.

Ele quer que **todos os seus equipamentos se comportem como se estivessem na mesma rede
local**, podendo alcançar qualquer um a partir de qualquer outro por um IP fixo e
previsível — sem depender de serviços de terceiros e mantendo o controle.

## Solution

Um instalador/gerenciador interativo em Bash, com menu, que monta e administra uma rede
OpenVPN no modelo **hub-and-spoke com `client-to-client`**: um hub central interliga todos
os equipamentos e todos se enxergam. Cada equipamento recebe um **IP fixo** na VPN.

O assistente cuida do trabalho pesado: detecta o sistema, verifica dependências (mostrando
o que falta e como instalar, e pedindo confirmação), gera a PKI, sobe o servidor, e produz
perfis prontos para cada tipo de cliente — incluindo **QR Code** para celular e um **perfil
+ script + guia** para MikroTik. Há opções no assistente para **IPv4/IPv6/dual-stack** e
para usar um hub como **saída de internet**. Para redundância, é possível ter **dois hubs
ativo-ativo**, de modo que a rede sobreviva à queda de um deles.

Tudo é guiado, em português claro, e o código é mantível e testado.

## User Stories

1. Como operador, quero detectar automaticamente meu sistema operacional, para saber de
   imediato se ele é suportado (Debian 12+ / Ubuntu 24.04+) antes de qualquer ação.
2. Como operador, quero que o instalador liste as dependências que faltam, para entender o
   que será necessário.
3. Como operador, quero ver exatamente **como** cada dependência será instalada (qual
   comando, qual pacote), para decidir com consciência.
4. Como operador, quero confirmar (`[s/N]`) antes de qualquer instalação, para nunca ter
   algo instalado sem minha autorização.
5. Como operador preocupado com segurança, quero que o instalador **recuse pacotes lançados
   há menos de 7 dias**, para evitar versões recém-publicadas ainda não validadas.
6. Como operador, quero um menu interativo claro com banner e opções numeradas, para
   navegar sem decorar comandos.
7. Como operador, quero instalar um hub OpenVPN com um passo a passo guiado, para subir a
   rede sem editar arquivos manualmente.
8. Como operador, quero que a PKI (CA, certificado do servidor e dos clientes) seja gerada
   automaticamente com padrões seguros (ECDSA, tls-crypt), para não cuidar de cripto na mão.
9. Como operador, quero que a geração da CA seja idempotente, para reexecutar o instalador
   sem recriar/estragar certificados existentes.
10. Como operador, quero adicionar um novo equipamento (cliente) informando só um nome, para
    obter rapidamente o perfil de conexão dele.
11. Como operador, quero que cada equipamento receba um **IP fixo** na VPN, para acessá-lo
    sempre no mesmo endereço.
12. Como operador, quero que o perfil `.ovpn` já venha com os certificados embutidos, para
    transferir um único arquivo ao equipamento.
13. Como operador, quero que uma cópia do perfil gerado fique no meu _home_, para transferir
    facilmente via `scp`/pendrive.
14. Como operador, quero gerar um **QR Code** do perfil, para configurar o celular
    (OpenVPN Connect) apenas escaneando.
15. Como operador, quero que todos os equipamentos conectados **se enxerguem entre si**
    (`client-to-client`), para acessar qualquer um a partir de qualquer outro.
16. Como operador, quero pingar/SSH/RDP de um equipamento para outro pelo IP da VPN, para
    administrar tudo remotamente como se estivesse na mesma LAN.
17. Como operador, quero escolher no assistente entre **IPv4-only, IPv6-only ou dual-stack**,
    para adequar a rede ao meu ambiente.
18. Como operador com IPv6, quero que o servidor distribua endereços IPv6 e rotas
    apropriadas, para que os equipamentos se comuniquem por IPv6.
19. Como operador, quero ativar (opcionalmente) a **saída para a internet** por um hub, para
    que os equipamentos naveguem usando a conexão daquele hub.
20. Como operador, quero que a saída para internet venha **desligada por padrão**, para não
    redirecionar tráfego sem intenção.
21. Como operador, quero escolher a interface WAN usada no NAT, para acertar a saída em
    máquinas com múltiplas interfaces.
22. Como operador, quero que o NAT funcione tanto com `nft` quanto com `iptables`, para
    funcionar no backend de firewall disponível.
23. Como operador, quero adicionar um roteador **MikroTik** à rede, para incluir minha
    infraestrutura de rede no mesmo conjunto.
24. Como operador, quero um perfil `.ovpn` **compatível com RouterOS** (cipher explícito,
    sem LZO), para que o MikroTik conecte sem erros de negociação.
25. Como operador, quero um **script RouterOS (`.rsc`) pronto para colar**, para configurar
    o MikroTik rapidamente sem montar comandos na mão.
26. Como operador, quero um **guia passo a passo** de MikroTik, para seguir mesmo sem
    experiência com RouterOS.
27. Como operador, quero **revogar** o acesso de um equipamento, para cortar o acesso de algo
    perdido/comprometido.
28. Como operador, quero **listar** os equipamentos cadastrados e seus IPs, para ter visão da
    rede.
29. Como operador, quero ver o **status** do servidor (ativo, clientes conectados), para
    saber a saúde da rede.
30. Como operador, quero ter um **segundo hub ativo-ativo**, para a rede não cair se um hub
    falhar.
31. Como operador, quero que os dois hubs usem a **mesma CA**, para que os perfis dos
    equipamentos sejam aceitos em qualquer um.
32. Como operador, quero exportar do hub primário um **bundle** seguro (CA, tls-crypt) e
    importá-lo no segundo hub, para sincronizar a confiança entre eles.
33. Como operador, quero que os hubs usem **sub-redes distintas** e troquem rotas, para que
    um equipamento no hub A alcance um equipamento no hub B.
34. Como operador, quero que os perfis de cliente listem os **dois hubs como `remote`**, para
    que o equipamento migre sozinho se um hub cair.
35. Como operador, quero **desinstalar** a solução de forma limpa, para reverter o que foi
    feito quando necessário.
36. Como operador, quero preparar uma máquina nova com um único `bootstrap.sh`, para instalar
    git/gh, autenticar, clonar e já abrir o menu.
37. Como operador, quero mensagens em **português claro**, para entender cada passo sem
    ambiguidade.
38. Como mantenedor, quero código simples e modular, para conseguir manter e evoluir o
    projeto com segurança.
39. Como mantenedor, quero **testes automatizados** (bats-core) em cada módulo, para alterar
    o código sem medo de regressões.
40. Como mantenedor, quero que os testes rodem **sem root e sem tocar o sistema**, para
    executá-los em qualquer lugar, inclusive no CI.
41. Como mantenedor, quero `shellcheck` limpo no CI, para manter um padrão de qualidade.
42. Como usuário de celular, quero conectar pelo app oficial OpenVPN Connect, para acessar a
    rede sem configuração complexa.

## Implementation Decisions

### Arquitetura

- O projeto é um conjunto de **módulos profundos** em `lib/` (interface pequena, lógica
  encapsulada), orquestrados por um `controller.sh` fino e por dois pontos de entrada:
  `bootstrap.sh` (preparar máquina) e `install.sh` (menu interativo).
- Funções públicas seguem `ovpn_<modulo>_<verbo>`; privadas `_ovpn_...`.
- Todo comando que toca o sistema é isolado em um módulo, para ser substituível por _stub_
  nos testes.

### Módulos previstos e seus contratos (de alto nível)

- `core` — constantes de caminho, `require_root`, tratamento de erro.
- `log` — mensagens info/aviso/erro/ok/passo.
- `ui` — banner, menu numerado com validação, confirmação `[s/N]`.
- `os_detect` — identifica e valida o SO (Debian 12+ / Ubuntu 24.04+).
- `deps` — detecta dependências, monta o plano legível de instalação, aplica a **regra dos
  7 dias** e só instala após confirmação.
- `pki` — cria CA/servidor/cliente (ECDSA prime256v1), tls-crypt, CRL; exporta/importa a CA;
  idempotente.
- `wizard_ipproto` — converte a escolha IPv4-only / IPv6-only / dual-stack em fragmentos de
  configuração (`proto`, `server-ipv6`, `push route-ipv6`).
- `server_config` — gera o `server.conf` (`dev tun`, `topology subnet`, `client-to-client`,
  `tls-crypt`, `data-ciphers AES-256-GCM:AES-128-GCM`) e gerencia o serviço via systemd.
- `ccd` — IP fixo por cliente via `client-config-dir` + `ifconfig-push`; alocação
  idempotente; rotas por cliente.
- `client_profile` — gera o `.ovpn` (certs inline), QR Code (qrencode), cópia no _home_,
  revogação.
- `mikrotik_profile` — perfil RouterOS (cipher explícito, **sem NCP, sem LZO**) + script
  `.rsc` + guia.
- `gateway` — saída para internet opcional: `push redirect-gateway def1` + NAT masquerade
  com backend `nft` (padrão) ou `iptables` (fallback); desligado por padrão.
- `hub_sync` — bundle verificável (checksum) com CA + tls-crypt para compartilhar entre hubs.
- `dualhub` — segundo hub ativo-ativo: sub-rede distinta, túnel site-to-site, troca de rotas
  estáticas, injeção dos dois `remote` nos perfis.

### Decisões técnicas

- **Topologia**: `tun` + `topology subnet` + `client-to-client`. Escolhida por ser a única
  que atende também clientes móveis (Android/iOS não suportam `tap`/L2) mantendo todos na
  mesma rede roteada (L3). IPs fixos via `ccd`.
- **Criptografia**: `tls-crypt` no canal de controle; `data-ciphers
  AES-256-GCM:AES-128-GCM`; certificados **ECDSA prime256v1**. Para MikroTik, o perfil fixa
  um **cipher explícito** (sem NCP) e **não usa LZO**.
- **IPv4/IPv6**: opção no assistente. Dual-stack usa `proto udp6` + `server-ipv6` + push de
  rotas IPv6, com encaminhamento IPv6 habilitado no hub.
- **Saída para internet**: opcional, desligada por padrão; NAT por `nft` (padrão nos alvos)
  ou `iptables`.
- **Redundância (ativo-ativo)**: dois hubs em máquinas distintas, sub-redes não sobrepostas
  (ex.: `10.8.0.0/24` e `10.8.1.0/24`), túnel site-to-site entre eles e troca de rotas
  estáticas. **CA compartilhada** via `hub_sync`. Clientes recebem os dois `remote`.
- **Gate de dependências**: detectar → exibir o que falta e como instalar → **confirmar** →
  instalar via apt. **Regra dos 7 dias** aplicada antes de instalar.
- **Locais (runtime)**: ferramenta em `~/OpenVPN-Installer`; config em `/etc/openvpn/server/`;
  PKI em `/etc/openvpn/pki/`; perfis em `/etc/openvpn/clients/` (+ cópia no _home_).
- **Idioma**: operador em pt-BR; identificadores em inglês.

## Testing Decisions

- **O que é um bom teste**: verifica **comportamento externo** (saídas e efeitos
  observáveis), não detalhes internos. Refatorar a implementação de um módulo não deve
  quebrar seus testes.
- **Framework**: bats-core, com `bats-support`/`bats-assert`. **TDD**: teste antes do código.
- **Isolamento**: nenhum teste exige root nem altera o sistema real. As constantes de
  caminho dos módulos apontam para `$BATS_TMPDIR`, e os comandos de sistema (`apt`,
  `openvpn`, `openssl`, `easy-rsa`, `systemctl`, `nft`, `iptables`, `gh`, `qrencode`, `ip`)
  são substituídos por **stubs** que registram os argumentos recebidos, permitindo afirmar
  _o que o módulo faria_ sem executá-lo.
- **Cobertura**: **todos os módulos** de `lib/` recebem testes unitários (decisão de TDD
  desde o início). Fluxos ponta a ponta pelo `controller.sh` ficam em `tests/integration/`.
- **Casos-chave por módulo** (exemplos): `deps` recusa pacote com < 7 dias e não instala sem
  confirmação; `os_detect` aceita Debian 12/Ubuntu 24.04 e recusa anteriores; `server_config`
  inclui `topology subnet` e `client-to-client`; `mikrotik_profile` usa cipher explícito e
  não usa LZO; `ccd` mantém o IP do cliente entre execuções; `gateway` aplica/remove o NAT no
  backend correto; `hub_sync` falha na importação se o checksum não bater.
- **Prior art**: projeto _greenfield_ — não há testes anteriores no repositório. O padrão de
  stubs descrito acima é o de referência a ser seguido pelos próximos módulos.
- **CI**: `.github/workflows/ci.yml` roda `shellcheck` + `bats` a cada push/PR.

## Out of Scope

- Interface web ou API de administração (apenas CLI/menu).
- **Mesh real com roteamento dinâmico (OSPF/BGP)** entre muitos hubs — fica como evolução
  futura; a v1 entrega dois hubs ativo-ativo com rotas estáticas.
- Configuração **remota automática** do MikroTik (o operador cola o script no RouterOS); o
  projeto entrega perfil + script + guia, não acesso remoto ao roteador.
- Hub OpenVPN em sistemas que não sejam Debian 12+/Ubuntu 24.04+ (ex.: RHEL, Alpine,
  Windows). Clientes, porém, podem ser de qualquer plataforma suportada pelo OpenVPN.
- OpenVPN Access Server e seu clustering proprietário.
- Gerenciamento de DNS interno/registros de nomes (a rede usa IPs fixos; nomes ficam a cargo
  do operador).

## Further Notes

- **MikroTik / RouterOS**: UDP exige RouterOS v7+; `tls-crypt` exige v7.17+. O guia deve
  registrar essas versões e, quando necessário, oferecer alternativa por TCP. RouterOS não
  faz negociação de cipher (NCP) e não suporta LZO — por isso o perfil é específico.
- **Evoluções futuras**: mesh com OSPF para 3+ hubs; mais de dois hubs; aceleração DCO
  quando disponível; suporte a mais distribuições.
- **Ordem de entrega**: a rede mínima funcional (hub único + primeiro cliente) é priorizada
  para provar o objetivo cedo; recursos (IPv6, gateway, MikroTik, segundo hub) entram como
  fatias verticais independentes sobre essa base.
