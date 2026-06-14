#!/usr/bin/env bash
# bootstrap.sh — prepara uma máquina nova e baixa o OpenVPN-Installer.
#
# O que faz:
#   1. Verifica/instala git e gh (pedindo confirmação antes do apt).
#   2. Autentica no GitHub (repositório privado).
#   3. Clona o projeto em ~/OpenVPN-Installer e orienta o operador.
#
# Uso:
#   bash bootstrap.sh

OVPN_REPO="${OVPN_REPO:-aldiney/OpenVPN-Installer}"
OVPN_BRANCH="${OVPN_BRANCH:-main}"
OVPN_TARGET_DIR="${OVPN_TARGET_DIR:-${HOME}/OpenVPN-Installer}"

bootstrap_step() { printf '\n\033[0;34m==> %s\033[0m\n' "$*"; }

# Seam: o comando existe? (substituível nos testes)
_bootstrap_cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Verifica e instala git e gh, mostrando o plano e pedindo confirmação.
bootstrap_ensure_tools() {
    local missing=()
    _bootstrap_cmd_exists git || missing+=(git)
    _bootstrap_cmd_exists gh || missing+=(gh)

    if [[ ${#missing[@]} -eq 0 ]]; then
        printf 'git e gh já estão instalados.\n'
        return 0
    fi

    printf 'Faltando: %s\n' "${missing[*]}"
    printf 'Serão instalados via apt: %s\n' "${missing[*]}"
    local ans
    read -r -p "Prosseguir com a instalação? [s/N]: " ans
    if [[ ! "${ans}" =~ ^[sS]$ ]]; then
        printf 'Instalação cancelada pelo operador.\n'
        return 1
    fi

    apt-get update -qq
    apt-get install -y "${missing[@]}"
}

# Garante autenticação no GitHub (necessária para o repo privado).
bootstrap_auth_github() {
    if gh auth status >/dev/null 2>&1; then
        printf 'gh já autenticado.\n'
        return 0
    fi
    gh auth login
}

# Instala o comando 'openvpn-installer' no PATH (symlink para o install.sh).
bootstrap_install_command() {
    local bindir="${OVPN_BIN_DIR:-/usr/local/bin}"
    local link="${bindir}/openvpn-installer"
    if ln -sf "${OVPN_TARGET_DIR}/install.sh" "${link}" 2>/dev/null; then
        printf "    Comando 'openvpn-installer' instalado em %s\n" "${link}"
    else
        printf "    (não foi possível criar %s — rode como root para ter o comando)\n" "${link}"
    fi
}

# Clona (ou atualiza) o repositório no diretório destino.
bootstrap_clone() {
    if [[ -d "${OVPN_TARGET_DIR}/.git" ]]; then
        printf 'Repo já existe em %s — atualizando.\n' "${OVPN_TARGET_DIR}"
        git -C "${OVPN_TARGET_DIR}" pull --ff-only origin "${OVPN_BRANCH}"
    else
        gh repo clone "${OVPN_REPO}" "${OVPN_TARGET_DIR}" -- --branch "${OVPN_BRANCH}"
    fi
}

bootstrap_main() {
    bootstrap_step "1/3  Verificando git e gh"
    bootstrap_ensure_tools

    bootstrap_step "2/3  Autenticando no GitHub"
    bootstrap_auth_github

    bootstrap_step "3/3  Clonando ${OVPN_REPO}"
    bootstrap_clone
    bootstrap_install_command

    printf '\nPronto! Para usar:\n'
    printf '  sudo openvpn-installer        # de qualquer lugar\n'
    printf '  # ou: cd %s && sudo ./install.sh\n\n' "${OVPN_TARGET_DIR}"
}

# Só executa o fluxo quando o script é chamado diretamente (não ao ser "sourced"
# nos testes).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    bootstrap_main
fi
