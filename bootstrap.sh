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

    printf '\nPronto! Para usar:\n'
    printf '  cd %s\n' "${OVPN_TARGET_DIR}"
    printf '  sudo ./install.sh\n\n'
}

# Só executa o fluxo quando o script é chamado diretamente (não ao ser "sourced"
# nos testes).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    bootstrap_main
fi
