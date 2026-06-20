#!/usr/bin/env bash
# Nvidia-Hyprland.sh
# Configura NVIDIA correctamente para Hyprland/Wayland en Arch Linux
# Uso: bash Nvidia-Hyprland.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RST='\033[0m'

ok()     { echo -e "${GREEN}  [OK]${RST} $1"; }
fail()   { echo -e "${RED}  [ERROR]${RST} $1"; }
warn()   { echo -e "${YELLOW}  [AVISO]${RST} $1"; }
info()   { echo -e "${CYAN}  [INFO]${RST} $1"; }
header() { echo -e "\n${BOLD}${CYAN}=== $1 ===${RST}"; }

# Verificar que no se ejecute como root
if [[ "$EUID" -eq 0 ]]; then
  fail "No ejecutes este script como root. Usa tu usuario normal con sudo."
  exit 1
fi

# Verificar que sudo esté disponible
if ! command -v sudo &>/dev/null; then
  fail "sudo no esta instalado. Instalalo con: su -c 'pacman -S sudo'"
  exit 1
fi

clear
echo -e "${BOLD}${CYAN}"
echo "  ============================================="
echo "   NVIDIA + Hyprland Fix Script"
echo "   para Arch Linux"
echo "  ============================================="
echo -e "${RST}"
sleep 1

# === FASE 1: DETECTAR GPU ===
header "FASE 1: Detectando GPU NVIDIA"

if ! command -v lspci &>/dev/null; then
  info "Instalando pciutils..."
  sudo pacman -S --needed --noconfirm pciutils || {
    fail "No se pudo instalar pciutils"
    exit 1
  }
fi

GPU_INFO=$(lspci | grep -i "VGA.*NVIDIA\|3D.*NVIDIA")
if [[ -z "$GPU_INFO" ]]; then
  fail "No se detecto GPU NVIDIA. Si tienes una GPU NVIDIA, verifica:"
  fail "  - Que este correctamente conectada"
  fail "  - Que no este deshabilitada en la BIOS/UEFI"
  fail "  - Ejecuta: lspci | grep -i vga"
  exit 1
fi
ok "GPU detectada: $GPU_INFO"

# === FASE 2: INSTALAR DRIVERS NVIDIA ===
header "FASE 2: Instalando drivers NVIDIA"

# Verificar tipo de kernel
KERNEL=$(uname -r)
if [[ "$KERNEL" == *"lts"* ]]; then
  NVIDIA_PKGS=(nvidia-lts nvidia-utils libva-nvidia-driver)
  info "Detectado kernel LTS, usando nvidia-lts"
else
  NVIDIA_PKGS=(nvidia nvidia-utils nvidia-dkms libva-nvidia-driver)
  info "Usando drivers NVIDIA estandar"
fi

MISSING=()

for pkg in "${NVIDIA_PKGS[@]}"; do
  if pacman -Q "$pkg" &>/dev/null; then
    ok "$pkg: ya instalado"
  else
    warn "$pkg: falta instalar"
    MISSING+=("$pkg")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  info "Instalando paquetes faltantes: ${MISSING[*]}"
  sudo pacman -S --needed --noconfirm "${MISSING[@]}" || {
    fail "Error instalando drivers NVIDIA. Verifica tu conexion y repositorios."
    fail "Intenta manualmente: sudo pacman -S ${MISSING[*]}"
    exit 1
  }
  ok "Drivers instalados correctamente"
else
  ok "Todos los drivers NVIDIA ya estan instalados"
fi

# === FASE 3: CONFIGURAR GESTOR DE ARRANQUE ===
header "FASE 3: Configurando parametros del kernel (nvidia-drm.modeset=1)"

# Detectar si usa GRUB o systemd-boot
if [[ -f "/etc/default/grub" ]]; then
  BOOTLOADER="grub"
  GRUB_FILE="/etc/default/grub"

  if grep -q "nvidia-drm.modeset=1" "$GRUB_FILE"; then
    ok "nvidia-drm.modeset=1 ya esta en GRUB"
  else
    info "Agregando nvidia-drm.modeset=1 a GRUB..."
    sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 nvidia-drm.modeset=1"/' "$GRUB_FILE"

    if grep -q "nvidia-drm.modeset=1" "$GRUB_FILE"; then
      ok "GRUB actualizado correctamente"
    else
      fail "No se pudo actualizar GRUB automaticamente."
      warn "Edita manualmente /etc/default/grub y agrega nvidia-drm.modeset=1 a GRUB_CMDLINE_LINUX_DEFAULT"
      exit 1
    fi
  fi

  info "Regenerando grub.cfg..."
  sudo grub-mkconfig -o /boot/grub/grub.cfg && ok "grub.cfg regenerado" || {
    fail "Error regenerando grub.cfg"
    exit 1
  }

elif [[ -d "/boot/loader/entries" ]]; then
  BOOTLOADER="systemd-boot"
  info "Detectado systemd-boot. Debes agregar nvidia-drm.modeset=1 manualmente:"
  warn "Edita los archivos en /boot/loader/entries/ y agrega nvidia-drm.modeset=1 a las opciones"
else
  BOOTLOADER="desconocido"
  warn "No se detecto GRUB ni systemd-boot. Agrega nvidia-drm.modeset=1 manualmente a tu gestor de arranque."
fi

# === FASE 4: CONFIGURAR MKINITCPIO ===
header "FASE 4: Configurando modulos NVIDIA en initramfs"

MKINIT_FILE="/etc/mkinitcpio.conf"

if [[ ! -f "$MKINIT_FILE" ]]; then
  fail "No se encontro /etc/mkinitcpio.conf"
  exit 1
fi

if grep -q "nvidia_drm" "$MKINIT_FILE"; then
  ok "Modulos NVIDIA ya estan en mkinitcpio.conf"
else
  info "Agregando modulos NVIDIA a mkinitcpio.conf..."

  # Hacer backup con timestamp
  BACKUP_FILE="${MKINIT_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
  sudo cp "$MKINIT_FILE" "$BACKUP_FILE"
  ok "Backup creado en $BACKUP_FILE"

  # Agregar modulos de manera mas segura
  if grep -q '^MODULES=()' "$MKINIT_FILE"; then
    sudo sed -i 's/^MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' "$MKINIT_FILE"
  else
    sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' "$MKINIT_FILE"
  fi

  if grep -q "nvidia_drm" "$MKINIT_FILE"; then
    ok "mkinitcpio.conf actualizado correctamente"
    info "Modulos configurados: $(grep '^MODULES=' $MKINIT_FILE)"
  else
    fail "No se pudo actualizar mkinitcpio.conf automaticamente"
    warn "Agrega manualmente: MODULES=(... nvidia nvidia_modeset nvidia_uvm nvidia_drm)"
    exit 1
  fi
fi

info "Regenerando initramfs (esto puede tardar unos segundos)..."
sudo mkinitcpio -P && ok "Initramfs regenerado correctamente" || {
  fail "Error regenerando initramfs. Verifica los errores anteriores."
  exit 1
}

# === FASE 5: CONFIGURAR VARIABLES DE ENTORNO ===
header "FASE 5: Variables de entorno NVIDIA para Wayland"

ENV_FILE="$HOME/.config/hypr/env.conf"
mkdir -p "$HOME/.config/hypr"

# Verificar si ya existen las variables
if [[ -f "$ENV_FILE" ]] && grep -q "LIBVA_DRIVER_NAME,nvidia" "$ENV_FILE"; then
  ok "Variables NVIDIA ya existen en env.conf"
else
  info "Creando/actualizando $ENV_FILE..."
  
  # Hacer backup si el archivo existe
  [[ -f "$ENV_FILE" ]] && cp "$ENV_FILE" "${ENV_FILE}.bak"
  
  cat >> "$ENV_FILE" << 'ENVEOF'

# Configuracion NVIDIA para Wayland/Hyprland
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

# === FASE 6: CONFIGURAR LAUNCHER ===
header "FASE 6: Configurar inicio automatico de Hyprland"

BASH_PROFILE="$HOME/.bash_profile"

# Verificar si ya existe la configuracion
if [[ -f "$BASH_PROFILE" ]] && grep -q "start-hyprland\|Hyprland" "$BASH_PROFILE"; then
  ok "Inicio de Hyprland ya configurado en .bash_profile"
else
  info "Configurando auto-inicio de Hyprland en TTY1..."
  
  # Backup si existe
  [[ -f "$BASH_PROFILE" ]] && cp "$BASH_PROFILE" "${BASH_PROFILE}.bak"
  
  cat >> "$BASH_PROFILE" << 'PROFILEEOF'

# Auto-iniciar Hyprland en TTY1
if [[ -z "$WAYLAND_DISPLAY" ]] && [[ "$XDG_VTNR" -eq 1 ]]; then
  exec start-hyprland
fi
PROFILEEOF
  ok ".bash_profile configurado"
fi

# Verificar start-hyprland
if command -v start-hyprland &>/dev/null; then
  ok "start-hyprland: disponible en PATH"
else
  warn "start-hyprland no encontrado en PATH"
  warn "Buscando en ubicaciones comunes..."
  
  # Buscar en ubicaciones tipicas
  POSSIBLE_PATHS=(
    "$HOME/.local/bin/start-hyprland"
    "/usr/local/bin/start-hyprland"
    "$HOME/.local/share/bin/start-hyprland"
  )
  
  FOUND=false
  for path in "${POSSIBLE_PATHS[@]}"; do
    if [[ -f "$path" ]]; then
      info "Encontrado en: $path"
      FOUND=true
      break
    fi
  done
  
  if [[ "$FOUND" == false ]]; then
    warn "No se encontro start-hyprland. Es posible que necesites instalarlo."
    info "Puedes buscar mas con: find / -name 'start-hyprland' 2>/dev/null"
  fi
fi

# === VERIFICACION FINAL ===
header "Verificacion de configuracion"

ERRORS=0

# Verificar modosetting
if ! grep -q "nvidia-drm.modeset=1" /proc/cmdline 2>/dev/null; then
  warn "nvidia-drm.modeset=1 no esta activo (se aplicara tras reiniciar)"
else
  ok "nvidia-drm.modeset=1 activo"
fi

# Verificar modulos cargados
if lsmod | grep -q nvidia; then
  ok "Modulos NVIDIA cargados"
else
  warn "Modulos NVIDIA no cargados (normal si no has reiniciado)"
fi

# Verificar DRM
if [[ -e "/dev/dri/card0" ]]; then
  ok "Dispositivo DRM detectado"
else
  warn "No se detecta /dev/dri/card0"
  ERRORS=$((ERRORS + 1))
fi

# === RESUMEN FINAL ===
echo ""
echo -e "${BOLD}${CYAN}=== RESUMEN ===================================${RST}"

if [[ $ERRORS -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}  Configuracion completada exitosamente.${RST}"
else
  echo -e "${YELLOW}${BOLD}  Configuracion completada con $ERRORS advertencia(s).${RST}"
fi

echo ""
echo -e "  ${BOLD}Pasos siguientes:${RST}"
echo ""
echo -e "  1. ${CYAN}sudo reboot${RST} (o escribe 'reboot')"
echo -e "  2. Al iniciar sesion en TTY1, Hyprland se iniciara automaticamente"
echo -e "     o escribe ${CYAN}start-hyprland${RST} manualmente"
echo ""
echo -e "${YELLOW}  IMPORTANTE:${RST}"
echo -e "  - Siempre usa ${CYAN}start-hyprland${RST}, nunca 'Hyprland' directamente"
echo -e "  - Si hay problemas, revisa: ${CYAN}~/.local/share/hyprland/hyprland.log${RST}"
echo -e "  - Para debug: ${CYAN}Hyprland -c ~/.config/hypr/hyprland.conf${RST}"
echo ""

read -rp "  Quieres reiniciar ahora? [s/N]: " REBOOT
if [[ "$REBOOT" =~ ^[sS]$ ]]; then
  echo ""
  info "Reiniciando en 3 segundos..."
  sleep 3
  sudo reboot
else
  info "Recuerda reiniciar manualmente para aplicar los cambios."
fi

echo -e "\n${BOLD}${CYAN}===============================================${RST}"