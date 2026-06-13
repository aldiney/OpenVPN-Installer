# CLAUDE.md — Regras do projeto OpenVPN-Installer

Este arquivo orienta qualquer agente (e qualquer pessoa) que trabalhe neste repositório.
Leia antes de escrever código.

## O que é o projeto

Instalador/gerenciador interativo em **Bash** que usa OpenVPN para interligar computadores,
servidores, celulares e roteadores MikroTik em uma **rede única**, onde qualquer
equipamento alcança qualquer outro por IP.

## Regras inegociáveis

1. **Regra dos 7 dias (segurança)**: NUNCA, em hipótese alguma, instalar um pacote ou
   versão lançado há **menos de 7 dias**. Isso vale tanto para o código do instalador
   (módulo `deps.sh` deve recusar/avisar) quanto para qualquer dependência que o agente
   decida adicionar ao projeto. Na dúvida, fixe uma versão mais antiga e estável.

2. **Confirmação antes de instalar**: o instalador detecta o que falta, mostra **exatamente
   o que será instalado e como**, e só prossegue após o operador confirmar (`[s/N]`).
   Nunca instalar nada silenciosamente.

3. **Não citar projetos internos de inspiração**: não mencione, referencie ou cite, em
   nenhum arquivo, comentário, commit ou documentação, qualquer projeto interno usado apenas
   como inspiração (em especial o projeto cujo menu inspirou este instalador). Essas
   referências são internas e não devem aparecer no projeto.

4. **Linguagem clara e objetiva**: tanto na comunicação com o operador quanto no código. O
   código deve ser **mantível por humanos** — simples, direto, sem esperteza desnecessária.

## Idioma

- Texto voltado ao operador (mensagens do terminal, README, docs, comentários): **pt-BR**.
- Identificadores de código (funções, variáveis): **inglês**.

## Sistemas suportados

- Debian 12+ e Ubuntu 24.04+. O módulo `os_detect.sh` bloqueia o resto com mensagem clara.

## Arquitetura e convenções de código

- **Módulos profundos**: cada arquivo em `lib/` expõe uma interface pequena e estável e
  esconde a complexidade. Funções públicas `ovpn_<modulo>_<verbo>`; privadas `_ovpn_...`.
- **Orquestradores finos**: `lib/controller.sh` apenas sequencia chamadas aos módulos; a
  lógica mora nos módulos.
- **Tudo que toca o sistema passa por um módulo** (apt, openvpn, openssl, systemctl, nft,
  iptables...), para ser substituível por _stub_ nos testes.
- **Bash seguro**: `set -euo pipefail`; aspas em variáveis; `shellcheck` limpo (config em
  `.shellcheckrc`).
- **Padrão de menu**: `install.sh` mostra um banner + menu numerado, com submenus por
  função, e o gate de dependências com confirmação antes de instalar.

## Testes (TDD)

- Escreva o teste **antes** do código (vermelho → verde). Framework: **bats-core**.
- Teste **comportamento externo**, nunca detalhes internos.
- Nenhum teste exige root nem altera o sistema real: caminhos vão para `$BATS_TMPDIR` e os
  comandos de sistema são substituídos por _stubs_ em `tests/test_helper/stubs/`.
- CI roda `shellcheck` + `bats` em cada push/PR (`.github/workflows/ci.yml`).

## Decisões de arquitetura travadas

Registradas como ADRs em `docs/prd/adr/`. Resumo:

- Topologia `tun` + `topology subnet` + `client-to-client` (única que também atende
  celular; Android/iOS não suportam `tap`/L2). IP fixo por cliente via `client-config-dir`.
- Cripto: `tls-crypt`, `data-ciphers AES-256-GCM:AES-128-GCM`, PKI ECDSA prime256v1.
  Perfil MikroTik usa cipher **explícito** (sem NCP) e **sem LZO**.
- Redundância: dois hubs **ativo-ativo** com sub-redes distintas, túnel site-to-site e
  troca de rotas. CA compartilhada. Mesh real (OSPF) fica como evolução futura.

## Onde as coisas ficam (em tempo de execução)

- Ferramenta: `~/OpenVPN-Installer`
- Config do servidor: `/etc/openvpn/server/`
- PKI: `/etc/openvpn/pki/`
- Perfis de cliente: `/etc/openvpn/clients/` (+ cópia no _home_ do operador)

Nada de segredos (chaves, certs, `.ovpn`) é versionado — ver `.gitignore`.

## Fluxo de trabalho

- O escopo está no PRD (`docs/prd/PRD.md`) e fatiado em issues (label `ready-for-agent`).
- Implemente uma issue por vez, como fatia vertical demonstrável, com testes.
