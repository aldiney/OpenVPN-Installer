#!/usr/bin/env bash
# Módulo ui — interação com o operador (banner, menu, confirmação).
# Carregado via `source`; não é executado diretamente.

# Mostra o banner do projeto.
ovpn_ui_banner() {
    cat <<'BANNER'

  ╔══════════════════════════════════════╗
  ║          OpenVPN-Installer           ║
  ║   uma rede única para seus equipos   ║
  ╚══════════════════════════════════════╝

BANNER
}

# Mostra um menu numerado. Uso: ovpn_ui_menu "Título" "Opção A" "Opção B" ...
# As opções são numeradas a partir de 1; cabe ao chamador tratar a escolha.
ovpn_ui_menu() {
    local title="$1"
    shift
    printf '=== %s ===\n' "${title}"
    local index=1
    local item
    for item in "$@"; do
        printf '%d. %s\n' "${index}" "${item}"
        index=$((index + 1))
    done
}

# Pergunta sim/não. Retorna 0 só quando a resposta é "s" ou "S".
# Uso: ovpn_ui_confirm "Prosseguir?"  (lê da entrada padrão)
ovpn_ui_confirm() {
    local prompt="${1:-Confirmar?}"
    local answer
    read -r -p "${prompt} [s/N]: " answer
    [[ "${answer}" =~ ^[sS]$ ]]
}
