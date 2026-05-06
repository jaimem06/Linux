#!/usr/bin/env bash
# prep-end4.sh - Preparador para end-4/dots-hyprland en Arch Linux

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RST='\033[0m'

ok()     { echo -e "${GREEN}  [OK]${RST} $1"; }
fail()   { echo -e "${RED}  [ERROR]${RST} $1"; ERRORS=$((ERRORS+1)); }
warn()   { echo -e "${YELLOW}  [AVISO]${RST} $1"; }
info()   { echo -e "${CYAN}  [-->]${RST} $1"; }
header() { echo -e "\n${BOLD}${CYAN}=== $1 ===${RST}"; }

ERRORS=0

clear
echo -e "${BOLD}${CYAN}"
echo "  ============================================="
echo "   end-4/dots-hyprland - Setup Preparator"
echo "   para Arch Linux (alyc3@hackerwomen)"
echo "  ============================================="
echo -e "${RST}"
sleep 1

header "FASE 1: Validaciones del sistema"

if [[ "$EUID" -eq 0 ]]; then
  fail "No corras este script como root. Usa tu usuario normal."
  exit 1
else
  ok "Usuario: $(whoami)"
fi

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
  ok "Arquitectura: $ARCH"
else
  fail "Arquitectura $ARCH no soportada. Se requiere x86_64."
  exit 1
fi

if [[ ! -f /etc/os-release ]]; then
  fail "/etc/os-release no encontrado."
  exit 1
fi

OS_ID=$(awk -F'=' '/^ID=/ { gsub(/["'"'"']/, "", $2); print tolower($2) }' /etc/os-release)
if [[ "$OS_ID" =~ ^(arch|endeavouros|cachyos)$ ]]; then
  ok "Distro: $OS_ID (soporte oficial)"
else
  warn "Distro '$OS_ID' puede funcionar pero no es oficialmente soportada."
fi

if sudo -v 2>/dev/null; then
  ok "sudo: funcional"
else
  fail "sudo no disponible. Agrega tu usuario al grupo wheel."
  exit 1
fi

if ping -c 1 -W 3 archlinux.org &>/dev/null; then
  ok "Internet: OK"
else
  fail "Sin internet. Conectate con nmtui primero."
  exit 1
fi

if systemctl --version &>/dev/null; then
  ok "systemd: disponible"
else
  fail "systemd no encontrado."
  exit 1
fi

header "FASE 2: Dependencias base"

MISSING_BASE=()
for pkg in git curl base-devel wget; do
  if pacman -Q "$pkg" &>/dev/null; then
    ok "$pkg: instalado"
  else
    warn "$pkg: falta - se instalara"
    MISSING_BASE+=("$pkg")
  fi
done

if [[ ${#MISSING_BASE[@]} -gt 0 ]]; then
  info "Instalando: ${MISSING_BASE[*]}"
  sudo pacman -S --needed --noconfirm "${MISSING_BASE[@]}" || {
    fail "Error instalando paquetes base."
    exit 1
  }
  ok "Paquetes base instalados"
fi

header "FASE 3: AUR Helper (yay)"

if command -v yay &>/dev/null; then
  ok "yay: $(yay --version | head -1)"
elif command -v paru &>/dev/null; then
  ok "paru: $(paru --version | head -1)"
  warn "paru detectado. yay es recomendado para end-4."
else
  info "Instalando yay desde AUR..."
  BUILD_DIR=$(mktemp -d)
  git clone --depth 1 https://aur.archlinux.org/yay.git "$BUILD_DIR/yay" || {
    fail "No se pudo clonar yay."
    exit 1
  }
  cd "$BUILD_DIR/yay"
  makepkg -si --noconfirm || {
    fail "makepkg fallo compilando yay."
    exit 1
  }
  cd ~
  rm -rf "$BUILD_DIR"
  if command -v yay &>/dev/null; then
    ok "yay instalado: $(yay --version | head -1)"
  else
    fail "yay no quedo en PATH."
    exit 1
  fi
fi

header "FASE 4: Grupos de usuario"

if ! getent group i2c &>/dev/null; then
  info "Creando grupo i2c..."
  sudo groupadd i2c && ok "Grupo i2c creado" || warn "No se pudo crear i2c"
else
  ok "Grupo i2c: existe"
fi

CURRENT_USER=$(whoami)
for grp in video i2c input; do
  if id -nG "$CURRENT_USER" | grep -qw "$grp"; then
    ok "Grupo $grp: OK"
  else
    info "Agregando $CURRENT_USER al grupo $grp..."
    sudo usermod -aG "$grp" "$CURRENT_USER" && ok "Agregado a $grp" || warn "No se pudo agregar a $grp"
  fi
done

header "FASE 5: Bluetooth"

if systemctl is-enabled bluetooth &>/dev/null; then
  ok "Bluetooth: ya habilitado"
else
  info "Habilitando bluetooth..."
  sudo systemctl enable bluetooth --now && ok "Bluetooth habilitado" || warn "Bluetooth no disponible"
fi

header "FASE 6: Clonar end-4/dots-hyprland"

DOTS_DIR="$HOME/dots-hyprland"

if [[ -d "$DOTS_DIR" ]]; then
  warn "Ya existe $DOTS_DIR"
  read -rp "  Eliminar y volver a clonar? [s/N]: " RECLONE
  if [[ "$RECLONE" =~ ^[sS]$ ]]; then
    rm -rf "$DOTS_DIR"
    info "Directorio eliminado."
  else
    info "Usando directorio existente."
  fi
fi

if [[ ! -d "$DOTS_DIR" ]]; then
  info "Clonando dots-hyprland..."
  git clone --recurse-submodules https://github.com/end-4/dots-hyprland.git "$DOTS_DIR" || {
    fail "Error clonando el repo."
    exit 1
  }
  ok "Repo clonado en $DOTS_DIR"
else
  ok "Repo disponible en $DOTS_DIR"
fi

echo ""
echo -e "${BOLD}${CYAN}=== RESUMEN ===================================${RST}"

if [[ $ERRORS -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}"
  echo "  Todo listo. Sistema preparado correctamente."
  echo -e "${RST}"
  echo -e "  ${BOLD}Siguiente paso:${RST}"
  echo ""
  echo -e "  ${CYAN}  cd ~/dots-hyprland && ./setup install${RST}"
  echo ""
  echo -e "${YELLOW}  AVISO: Cierra sesion y vuelve a entrar antes${RST}"
  echo -e "${YELLOW}  de correr ./setup install para activar los grupos.${RST}"
else
  echo -e "${RED}${BOLD}  Se encontraron $ERRORS error(es). Resuelvelos antes de continuar.${RST}"
fi

echo -e "${BOLD}${CYAN}===============================================${RST}"
