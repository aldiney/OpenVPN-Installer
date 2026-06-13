# tests/ — Testes (bats-core)

Testes escritos com [bats-core](https://github.com/bats-core/bats-core). Seguimos TDD:
o teste vem antes do código (vermelho → verde).

## Estrutura

- `unit/` — um arquivo `*.bats` por módulo de `lib/`. Testa **comportamento externo**
  (saídas e efeitos observáveis), nunca detalhes internos.
- `integration/` — fluxos ponta a ponta pelo `controller.sh`, sobre _stubs_.
- `test_helper/` — utilitários compartilhados:
  - `common.bash` — carrega o módulo sob teste, aponta as constantes de caminho para
    `$BATS_TMPDIR` (sandbox) e adiciona os _stubs_ ao `PATH`.
  - `stubs/` — substitutos de `apt`, `openvpn`, `openssl`, `easy-rsa`, `systemctl`,
    `nft`, `iptables`, `gh`, `qrencode`, `ip`. Cada stub registra os argumentos
    recebidos para que o teste verifique **o que o módulo faria**, sem tocar no sistema.

## Princípios

- Nenhum teste exige root nem altera o sistema real.
- `apt`/`openvpn`/etc. nunca são chamados de verdade — sempre via stub.
- Testar só o contrato público; refatorações internas não devem quebrar testes.
