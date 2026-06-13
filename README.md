# OpenVPN-Installer

Instalador e gerenciador interativo de **OpenVPN** para interligar seus equipamentos —
computadores, servidores, celulares e roteadores **MikroTik** — em uma **rede única e
privada**, onde qualquer equipamento alcança qualquer outro por IP.

> Objetivo: acessar qualquer um dos seus equipamentos a partir de qualquer outro, como se
> todos estivessem na mesma rede local, não importa onde estejam.

> **Status:** implementação completa, desenvolvida em fatias verticais com testes
> automatizados (bats-core) e CI verde a cada mudança. A validação final em equipamentos
> reais — conexão de cliente/celular/MikroTik e failover entre dois hubs — fica a cargo do
> operador no host alvo.

## Como funciona

A rede é montada no modelo **hub-and-spoke** com a diretiva `client-to-client`: um servidor
central (hub) interliga todos os equipamentos, e todos enxergam todos. Cada equipamento
recebe um **IP fixo** dentro da VPN, então você sempre o acessa pelo mesmo endereço.

Para evitar ponto único de falha, é possível ter **dois hubs ativos ao mesmo tempo**
(ativo-ativo): os equipamentos se distribuem entre eles, e um túnel entre os hubs garante
que todos continuem se enxergando.

Recursos:

- 🔗 **Rede única** — todos os equipamentos se comunicam entre si (`client-to-client`).
- 📌 **IP fixo por equipamento** — endereços estáveis e previsíveis.
- 📱 **Celular** — perfis com QR Code para o app OpenVPN Connect (Android/iOS).
- 🛜 **MikroTik** — perfil compatível com RouterOS + script pronto para colar + guia.
- 🌐 **IPv4, IPv6 ou dual-stack** — escolhível no assistente.
- 🚪 **Saída para a internet opcional** — um hub pode servir de gateway de internet para os
  equipamentos conectados (desligado por padrão).
- ♻️ **Dois hubs ativo-ativo** — redundância e múltiplos pontos de entrada.
- ✅ **Instalação consciente** — o script detecta o que falta, mostra exatamente o que vai
  instalar e **só prossegue após a sua confirmação**.
- 🧹 **Gestão pelo menu** — adicionar/listar clientes, ver status, revogar acesso e
  desinstalar (preservando ou removendo a PKI).

## Requisitos

- **Sistema operacional**: Debian 12+ ou Ubuntu 24.04+.
- **Acesso root** (sudo) na máquina que será o hub.
- Conexão com a internet para baixar dependências.

## Uso

O projeto tem dois pontos de entrada:

### 1. `bootstrap.sh` — preparar a máquina

Prepara uma máquina nova: instala `git` e `gh`, autentica no GitHub, clona o projeto e
deixa tudo pronto para usar.

```bash
bash bootstrap.sh
```

### 2. `install.sh` — assistente principal

Menu interativo que instala e gerencia o hub, gera perfis de cliente, configura MikroTik,
ativa saída para internet, etc.

```bash
sudo ./install.sh
```

## Segurança

Este projeto adota regras explícitas de segurança:

- **Regra dos 7 dias**: nunca instala um pacote/versão lançado há **menos de 7 dias**, para
  evitar versões recém-publicadas ainda não validadas pela comunidade.
- **Confirmação antes de instalar**: o instalador sempre lista o que falta e **como** vai
  instalar, e aguarda sua autorização antes de executar qualquer instalação.
- Chaves e perfis gerados ficam em `/etc/openvpn/` e no seu _home_ — **nunca** são
  versionados no repositório.

## Estrutura do projeto

```
bootstrap.sh           # prepara a máquina e baixa o projeto
install.sh             # menu interativo principal
lib/                   # módulos (ver lib/README.md)
tests/                 # testes bats-core (ver tests/README.md)
docs/                  # documentação
  prd/                 # PRD e decisões de arquitetura (ADRs)
  mikrotik-guide.md    # guia para conectar um MikroTik
  dual-hub.md          # guia dos dois hubs ativo-ativo
  troubleshooting.md   # solução de problemas
```

## Licença

[MIT](LICENSE) © 2026 Aldiney Carneiro
