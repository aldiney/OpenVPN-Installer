#!/usr/bin/env bash
# install.sh — assistente principal (menu interativo) do OpenVPN-Installer.
#
# Carrega os módulos de lib/, exige root, valida o sistema operacional e abre
# o menu. Execute como root:
#   sudo ./install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Ordem importa: módulos básicos primeiro, depois os de domínio e o controller.
for module in core log ui os_detect deps pki wizard_ipproto server_config ccd client_profile gateway controller; do
    # shellcheck source=/dev/null
    source "${LIB_DIR}/${module}.sh"
done

ovpn_require_root
ovpn_os_assert_supported
ovpn_menu_main
