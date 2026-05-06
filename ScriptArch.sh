script = r"""#!/usr/bin/env bash
# =============================================================================
#  prep-end4.sh — Preparación y validación para instalar end-4/dots-hyprland
#  Autor: generado para alyc3@hackerwomen
#  Uso:   bash prep-end4.sh
# =============================================================================

# ── Colores ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RST='\033[0m'

ok()   { echo -e "${GREEN}  [✓]${RST} $1"; }
fail() { echo -e "${RED}  [✗]${RST} $1"; ERRORS=$((ERRORS+1)); }
warn() { echo -e "${YELLOW}  [!]${RST} $1"; }
info() { echo -e "${CYAN}  [→]${RST} $1"; }
header() { echo -e "\n${BOLD}${CYAN}══ $1 ══${RST}"; }

ERRORS=0

# ── Banner ───────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}${CYAN}"
echo "  ╔═══════════════════════════════════════════════════╗"
echo "  ║      end-4/dots-hyprland — Setup Preparator       ║"
echo "  ║             para Arch Linux (alyc3)               ║"
echo "  ╚═══════════════════════════════════════════════════╝"
echo -e "${RST}"
sleep 1

# =============================================================================
# FASE 1 — VALIDACIONES
# =============================================================================
header "FASE 1: Validaciones del sistema"

# 1.1 No correr como root
if [[ "$EUID" -eq 0 ]]; then
  fail "Estás corriendo como root. El script de end-4 lo bloquea. Usa tu usuario normal."
  exit 1
else
  ok "Usuario normal: $(whoami)"
fi

# 1.2 Arquitectura x86_64
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
  ok "Arquitectura: $ARCH"
else
  fail "Arquitectura $ARCH no soportada. end-4 requiere x86_64."
  exit 1
fi

# 1.3 /etc/os-release existe y es Arch
if [[ ! -f /etc/os-release ]]; then
  fail "/etc/os-release no encontrado. El script de end-4 abortará."
  exit 1
fi

OS_ID=$(awk -F'=' '/^ID=/ { gsub(/[\"'"'"']/, "", $2); print tolower($2) }' /etc/os-release)
if [[ "$OS_ID" =~ ^(arch|endeavouros|cachyos)$ ]]; then
  ok "Distro detectada: $OS_ID (soporte oficial ✓)"
else
  warn "Distro '$OS_ID' no es Arch puro. end-4 puede dar advertencia pero continuar."
fi

# 1.4 Sudo disponible
if sudo -v 2>/dev/null; then
  ok "sudo disponible y funcional"
else
  fail "sudo no disponible o sin permisos. Agrega tu usuario al grupo wheel."
fi

# 1.5 Conexión a internet
if ping -c 1 -W 3 archlinux.org &>/dev/null; then
  ok "Conexión a internet: OK"
else
  fail "Sin conexión a internet. Requerido para descargar paquetes."
fi

# 1.6 systemd activo (requerido por 2.setups.sh del repo)
if systemctl --version &>/dev/null; then
  ok "systemd disponible"
else
  fail "systemd no encontrado. end-4 requiere systemd para habilitar servicios."
fi

# =============================================================================
# FASE 2 — INSTALAR BASE-DEVEL Y GIT
# =============================================================================
header "FASE 2: Dependencias base"

MISSING_BASE=()
for pkg in git curl base-devel; do
  if pacman -Q "$pkg" &>/dev/null; then
    ok "$pkg ya instalado"
  else
    warn "$pkg no encontrado — se instalará"
    MISSING_BASE+=("$pkg")
  fi
done

if [[ ${#MISSING_BASE[@]} -gt 0 ]]; then
  info "Instalando: ${MISSING_BASE[*]}"
  sudo pacman -S --needed --noconfirm "${MISSING_BASE[@]}" || {
    fail "Error instalando paquetes base. Revisa tu conexión o mirrors."
    exit 1
  }
  ok "Paquetes base instalados correctamente"
fi

# =============================================================================
# FASE 3 — INSTALAR AUR HELPER (yay)
# =============================================================================
header "FASE 3: AUR Helper"

if command -v yay &>/dev/null; then
  ok "yay ya instalado: $(yay --version | head -1)"
elif command -v paru &>/dev/null; then
  ok "paru ya instalado: $(paru --version | head -1)"
  warn "end-4 fue probado con yay. paru debería funcionar igual."
else
  info "Instalando yay desde AUR..."
  BUILD_DIR=$(mktemp -d)
  git clone --depth 1 https://aur.archlinux.org/yay.git "$BUILD_DIR/yay" || {
    fail "No se pudo clonar yay desde AUR."
    exit 1
  }
  cd "$BUILD_DIR/yay"
  makepkg -si --noconfirm || {
    fail "makepkg falló al compilar yay."
    exit 1
  }
  cd ~
  rm -rf "$BUILD_DIR"

  if command -v yay &>/dev/null; then
    ok "yay instalado correctamente: $(yay --version | head -1)"
  else
    fail "yay no quedó accesible en PATH tras la instalación."
    exit 1
  fi
fi

# =============================================================================
# FASE 4 — CONFIGURAR GRUPOS DE USUARIO (requerido por 2.setups.sh)
# =============================================================================
header "FASE 4: Grupos de usuario"

# Crear grupo i2c si no existe (end-4 lo necesita para control de brillo)
if getent group i2c &>/dev/null; then
  ok "Grupo i2c ya existe"
else
  info "Creando grupo i2c..."
  sudo groupadd i2c && ok "Grupo i2c creado" || fail "No se pudo crear grupo i2c"
fi

# Agregar usuario a grupos necesarios
CURRENT_USER=$(whoami)
for grp in video i2c input; do
  if id -nG "$CURRENT_USER" | grep -qw "$grp"; then
    ok "Usuario en grupo: $grp"
  else
    info "Agregando $CURRENT_USER al grupo $grp..."
    sudo usermod -aG "$grp" "$CURRENT_USER" && ok "Agregado a $grp" || warn "No se pudo agregar a $grp"
  fi
done

# =============================================================================
# FASE 5 — BLUETOOTH (habilitado por 2.setups.sh)
# =============================================================================
header "FASE 5: Bluetooth"

if systemctl is-enabled bluetooth &>/dev/null; then
  ok "Bluetooth ya habilitado"
else
  info "Habilitando bluetooth..."
  sudo systemctl enable bluetooth --now && ok "Bluetooth habilitado" || warn "Bluetooth no disponible (normal en VMs)"
fi

# =============================================================================
# FASE 6 — CLONAR EL REPO end-4
# =============================================================================
header "FASE 6: Clonar end-4/dots-hyprland"

DOTS_DIR="$HOME/dots-hyprland"

if [[ -d "$DOTS_DIR" ]]; then
  warn "El directorio $DOTS_DIR ya existe."
  read -rp "  ¿Eliminar y volver a clonar? [s/N]: " RECLONE
  if [[ "$RECLONE" =~ ^[sS]$ ]]; then
    rm -rf "$DOTS_DIR"
    info "Directorio eliminado."
  else
    info "Usando el directorio existente."
  fi
fi

if [[ ! -d "$DOTS_DIR" ]]; then
  info "Clonando end-4/dots-hyprland..."
  git clone --recurse-submodules https://github.com/end-4/dots-hyprland.git "$DOTS_DIR" || {
    fail "Error clonando el repo."
    exit 1
  }
  ok "Repo clonado en $DOTS_DIR"
else
  ok "Repo disponible en $DOTS_DIR"
fi

# =============================================================================
# RESUMEN FINAL
# =============================================================================
echo ""
echo -e "${BOLD}${CYAN}══ RESUMEN ════════════════════════════════════════════${RST}"

if [[ $ERRORS -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}"
  echo "  ✓ Todo listo. Tu sistema está preparado."
  echo -e "${RST}"
  echo -e "  ${BOLD}Siguiente paso — ejecutar el instalador oficial:${RST}"
  echo ""
  echo -e "  ${CYAN}  cd ~/dots-hyprland"
  echo -e "    ./setup install${RST}"
  echo ""
  echo -e "  ${YELLOW}  IMPORTANTE:${RST} El script te hará preguntas interactivas."
  echo "    Lee cada opción antes de confirmar."
  echo ""
  warn "Cierra sesión y vuelve a entrar antes de correr ./setup install"
  warn "para que los cambios de grupos (video, i2c, input) tengan efecto."
else
  echo -e "${RED}${BOLD}"
  echo "  ✗ Se encontraron $ERRORS error(es). Resuélvelos antes de continuar."
  echo -e "${RST}"
fi

echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════${RST}"
"""

with open("/tmp/prep-end4.sh", "w") as f:
    f.write(script)

import os
os.makedirs("/root/output", exist_ok=True)

with open("/root/output/prep-end4.sh", "w") as f:
    f.write(script)

print("Script generado correctamente.")
print(f"Líneas: {len(script.splitlines())}")
print(f"Tamaño: {len(script)} bytes")
