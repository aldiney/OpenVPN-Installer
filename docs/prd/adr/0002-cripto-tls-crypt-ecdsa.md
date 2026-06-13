# ADR 0002 — Criptografia: tls-crypt, ECDSA e ciphers AES-GCM

- **Status**: Aceito
- **Data**: 2026-06-13

## Contexto

Precisamos de padrões seguros e modernos, mas que também funcionem com clientes mais
restritos, em especial o **MikroTik/RouterOS**, que não faz negociação de cipher (NCP) e
não suporta compressão LZO.

## Decisão

- Canal de controle protegido com **`tls-crypt`** (oculta e autentica o handshake, mitiga
  varredura/DoS).
- Certificados **ECDSA prime256v1** (chaves menores, rápido, amplamente suportado).
- Canal de dados: `data-ciphers AES-256-GCM:AES-128-GCM` para clientes modernos (com NCP).
- **Perfis MikroTik** fixam um **cipher explícito** (sem depender de NCP) e **não usam LZO**.

## Consequências

- ✅ Segurança moderna por padrão para a maioria dos clientes.
- ✅ Compatibilidade garantida com MikroTik via perfil específico.
- ⚠️ As particularidades do MikroTik ficam isoladas no módulo `mikrotik_profile`, para não
  contaminar os perfis padrão.
- ⚠️ `tls-crypt` no MikroTik exige RouterOS v7.17+; o guia registra a versão e a alternativa.
