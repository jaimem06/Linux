#!/usr/bin/env bash
# nvidia-hyprland-fix.sh
# Configura NVIDIA correctamente para Hyprland/Wayland en Arch Linux
# Uso: bash nvidia-hyprland-fix.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RST='\033[0m'

ok()     { echo -e "${GREEN}  [OK]${RST} $1"; }
fail()   { echo -e "${RED}  [ERROR]${RST} $1"; }
warn()   { echo -e "${YELLOW}  [AVISO]${RST} $1"; }
info()   { echo -e "${CYAN}  [-->]${RST} $1"; }
header() { echo -e "\n${BOLD}${CYAN}=== $1 ===${RST}"; }

# No correr como root
if [[ "$EUID" -eq 0 ]]; then
  fail "No corras como root. Usa tu usuario normal."
  exit 1
fi

clear
echo -e "${BOLD}${CYAN}"
echo "  ============================================="
echo "   NVIDIA + Hyprland Fix Script"
echo "   para Arch Linux (alyc3@hackerwomen)"
echo "  ============================================="
echo -e "${RST}"
sleep 1

# === FASE 1: DETECTAR GPU ===
header "FASE 1: Detectando GPU NVIDIA"

GPU_INFO=$(lspci | grep -i nvidia)
if [[ -z "$GPU_INFO" ]]; then
  fail "No se detectó GPU NVIDIA. Abortando."
  exit 1
fi
ok "GPU detectada: $GPU_INFO"

# === FASE 2: INSTALAR DRIVERS NVIDIA ===
header "FASE 2: Instalando drivers NVIDIA"

NVIDIA_PKGS=(nvidia nvidia-utils nvidia-dkms libva-nvidia-driver)
MISSING=()

for pkg in "${NVIDIA_PKGS[@]}"; do
  if pacman -Q "$pkg" &>/dev/null; then
    ok "$pkg: ya instalado"
  else
    warn "$pkg: falta"
    MISSING+=("$pkg")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  info "Instalando: ${MISSING[*]}"
  sudo pacman -S --needed --noconfirm "${MISSING[@]}" || {
    fail "Error instalando drivers NVIDIA."
    exit 1
  }
  ok "Drivers instalados correctamente"
fi

# === FASE 3: CONFIGURAR GRUB ===
header "FASE 3: Configurando GRUB (nvidia-drm.modeset=1)"

GRUB_FILE="/etc/default/grub"

if grep -q "nvidia-drm.modeset=1" "$GRUB_FILE"; then
  ok "nvidia-drm.modeset=1 ya esta en GRUB"
else
  info "Agregando nvidia-drm.modeset=1 al GRUB..."
  sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 nvidia-drm.modeset=1"/' "$GRUB_FILE"

  if grep -q "nvidia-drm.modeset=1" "$GRUB_FILE"; then
    ok "GRUB actualizado correctamente"
  else
    fail "No se pudo actualizar GRUB automaticamente."
    warn "Edita manualmente /etc/default/grub y agrega nvidia-drm.modeset=1"
    exit 1
  fi
fi

info "Regenerando grub.cfg..."
sudo grub-mkconfig -o /boot/grub/grub.cfg && ok "grub.cfg regenerado" || {
  fail "Error regenerando grub.cfg"
  exit 1
}

# === FASE 4: CONFIGURAR MKINITCPIO ===
header "FASE 4: Configurando modulos NVIDIA en initramfs"

MKINIT_FILE="/etc/mkinitcpio.conf"

if grep -q "nvidia_drm" "$MKINIT_FILE"; then
  ok "Modulos NVIDIA ya estan en mkinitcpio.conf"
else
  info "Agregando modulos NVIDIA a mkinitcpio.conf..."

  # Hacer backup
  sudo cp "$MKINIT_FILE" "${MKINIT_FILE}.bak"
  ok "Backup creado en ${MKINIT_FILE}.bak"

  # Agregar modulos
  sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' "$MKINIT_FILE"

  # Limpiar doble espacio si MODULES estaba vacio
  sudo sed -i 's/MODULES=(  /MODULES=(/' "$MKINIT_FILE"
  sudo sed -i 's/MODULES=( /MODULES=(/' "$MKINIT_FILE"

  if grep -q "nvidia_drm" "$MKINIT_FILE"; then
    ok "mkinitcpio.conf actualizado"
    info "Contenido actual: $(grep '^MODULES=' $MKINIT_FILE)"
  else
    fail "No se pudo actualizar mkinitcpio.conf"
    exit 1
  fi
fi

info "Regenerando initramfs (puede tardar unos segundos)..."
sudo mkinitcpio -P && ok "Initramfs regenerado correctamente" || {
  fail "Error regenerando initramfs"
  exit 1
}

# === FASE 5: CONFIGURAR VARIABLES DE ENTORNO NVIDIA ===
header "FASE 5: Variables de entorno NVIDIA para Wayland"

ENV_FILE="$HOME/.config/hypr/env.conf"
mkdir -p "$HOME/.config/hypr"

if [[ -f "$ENV_FILE" ]] && grep -q "nvidia" "$ENV_FILE"; then
  ok "Variables NVIDIA ya existen en env.conf"
else
  info "Creando/actualizando $ENV_FILE..."
  cat >> "$ENV_FILE" << 'ENVEOF'

# NVIDIA Wayland fixes
env = LIBVA_DRIVER_NAME,nvidia
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = WLR_NO_HARDWARE_CURSORS,1
env = ELECTRON_OZONE_PLATFORM_HINT,auto
env = XDG_SESSION_TYPE,wayland
env = XDG_CURRENT_DESKTOP,Hyprland
ENVEOF
  ok "Variables NVIDIA agregadas a $ENV_FILE"
fi

# === FASE 6: CONFIGURAR LAUNCHER CORRECTO ===
header "FASE 6: Configurar start-hyprland como launcher"

BASH_PROFILE="$HOME/.bash_profile"

if [[ -f "$BASH_PROFILE" ]] && grep -q "start-hyprland" "$BASH_PROFILE"; then
  ok "start-hyprland ya configurado en .bash_profile"
else
  info "Configurando auto-start con start-hyprland en TTY1..."
  cat >> "$BASH_PROFILE" << 'PROFILEEOF'

# Auto-start Hyprland en TTY1
if [[ -z "$WAYLAND_DISPLAY" ]] && [[ "$XDG_VTNR" -eq 1 ]]; then
  exec start-hyprland
fi
PROFILEEOF
  ok ".bash_profile configurado"
fi

# Verificar que start-hyprland existe
if command -v start-hyprland &>/dev/null; then
  ok "start-hyprland: disponible en PATH"
else
  warn "start-hyprland no encontrado. Verifica que end-4 se instalo correctamente."
  warn "Busca el archivo con: find ~/.local -name 'start-hyprland' 2>/dev/null"
fi

# === RESUMEN FINAL ===
echo ""
echo -e "${BOLD}${CYAN}=== RESUMEN ===================================${RST}"
echo -e "${GREEN}${BOLD}"
echo "  Todo configurado correctamente."
echo -e "${RST}"
echo -e "  ${BOLD}Ahora:${RST}"
echo ""
echo -e "  1. ${CYAN}reboot${RST}"
echo -e "  2. Al volver al TTY, escribe: ${CYAN}start-hyprland${RST}"
echo ""
echo -e "${YELLOW}  IMPORTANTE:${RST} Nunca uses 'Hyprland' directamente."
echo -e "${YELLOW}  Siempre usa 'start-hyprland' para NVIDIA.${RST}"
echo ""
echo -e "${BOLD}${CYAN}===============================================${RST}"

read -rp "  Reiniciar ahora? [s/N]: " REBOOT
if [[ "$REBOOT" =~ ^[sS]$ ]]; then
  info "Reiniciando..."
  sudo reboot
fi
