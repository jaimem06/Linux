#!/usr/bin/env bash
# ScriptArch.sh - Preparador para end-4/dots-hyprland en Arch Linux

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RST='\033[0m'

ok()     { echo -e "${GREEN}  [OK]${RST} $1"; }
fail()   { echo -e "${RED}  [ERROR]${RST} $1"; ERRORS=$((ERRORS+1)); }
warn()   { echo -e "${YELLOW}  [AVISO]${RST} $1"; }
info()   { echo -e "${CYAN}  [INFO]${RST} $1"; }
header() { echo -e "\n${BOLD}${CYAN}=== $1 ===${RST}"; }

ERRORS=0

clear
echo -e "${BOLD}${CYAN}"
echo "  ============================================="
echo "   end-4/dots-hyprland - Preparador de Sistema"
echo "   para Arch Linux y derivadas"
echo "  ============================================="
echo -e "${RST}"
sleep 1

# === FASE 1: VALIDACIONES DEL SISTEMA ===
header "FASE 1: Validaciones del sistema"

# Verificar usuario
if [[ "$EUID" -eq 0 ]]; then
  fail "No ejecutes este script como root. Usa tu usuario normal con sudo."
  exit 1
else
  ok "Usuario actual: $(whoami)"
fi

# Verificar arquitectura
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
  ok "Arquitectura: $ARCH (compatible)"
else
  fail "Arquitectura $ARCH no soportada. Se requiere x86_64."
  exit 1
fi

# Verificar sistema operativo
if [[ ! -f /etc/os-release ]]; then
  fail "/etc/os-release no encontrado. Esto no parece ser un sistema Linux compatible."
  exit 1
fi

OS_ID=$(awk -F'=' '/^ID=/ { gsub(/["'"'"']/, "", $2); print tolower($2) }' /etc/os-release)
OS_NAME=$(awk -F'=' '/^PRETTY_NAME=/ { gsub(/"/, "", $2); print $2 }' /etc/os-release)

if [[ "$OS_ID" =~ ^(arch|endeavouros|cachyos|arcolinux|garuda|artix)$ ]]; then
  ok "Distribucion: $OS_NAME (soporte oficial o compatible)"
else
  warn "Distribucion '$OS_NAME' detectada. Podria funcionar pero no tiene soporte oficial."
  warn "Distribuciones soportadas: Arch, EndeavourOS, CachyOS, ArcoLinux, Garuda"
  read -rp "  Continuar de todos modos? [s/N]: " CONTINUE
  if [[ ! "$CONTINUE" =~ ^[sS]$ ]]; then
    info "Abortando por solicitud del usuario."
    exit 0
  fi
fi

# Verificar sudo
if sudo -v 2>/dev/null; then
  ok "Privilegios sudo: funcionales"
else
  fail "sudo no funciona o no esta configurado correctamente."
  info "Agrega tu usuario al grupo wheel: su -c 'usermod -aG wheel $(whoami)'"
  info "Luego cierra sesion y vuelve a entrar."
  exit 1
fi

# Verificar internet
if ping -c 1 -W 3 archlinux.org &>/dev/null; then
  ok "Conexion a internet: OK"
else
  fail "Sin conexion a internet."
  info "Configura tu red con: nmtui"
  info "O verifica con: ip link"
  exit 1
fi

# Verificar systemd
if systemctl --version &>/dev/null; then
  ok "systemd: disponible"
else
  fail "systemd no encontrado. Este script requiere systemd."
  exit 1
fi

# Verificar espacio en disco
ROOT_SPACE=$(df -h / | awk 'NR==2 {print $4}')
ROOT_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
if [[ $ROOT_USAGE -gt 90 ]]; then
  warn "Espacio en disco bajo: $ROOT_SPACE disponible ($ROOT_USAGE% usado)"
  warn "Se recomienda al menos 5GB libres para la instalacion."
else
  ok "Espacio en disco: $ROOT_SPACE disponible"
fi

# === FASE 2: DEPENDENCIAS BASE ===
header "FASE 2: Instalando dependencias base"

MISSING_BASE=()
BASE_PKGS=(git curl base-devel wget unzip)

for pkg in "${BASE_PKGS[@]}"; do
  if pacman -Q "$pkg" &>/dev/null; then
    ok "$pkg: instalado"
  else
    warn "$pkg: falta - se instalara"
    MISSING_BASE+=("$pkg")
  fi
done

if [[ ${#MISSING_BASE[@]} -gt 0 ]]; then
  info "Instalando paquetes faltantes: ${MISSING_BASE[*]}"
  sudo pacman -S --needed --noconfirm "${MISSING_BASE[@]}" || {
    fail "Error instalando paquetes base. Verifica tu conexion y repositorios."
    info "Intenta manualmente: sudo pacman -S ${MISSING_BASE[*]}"
    exit 1
  }
  ok "Paquetes base instalados correctamente"
else
  ok "Todas las dependencias base ya estan instaladas"
fi

# === FASE 3: AUR HELPER ===
header "FASE 3: Configurando AUR Helper"

AUR_HELPER=""
if command -v yay &>/dev/null; then
  AUR_HELPER="yay"
  ok "yay detectado: $(yay --version 2>/dev/null | head -1 || echo 'version desconocida')"
elif command -v paru &>/dev/null; then
  AUR_HELPER="paru"
  ok "paru detectado: $(paru --version 2>/dev/null | head -1 || echo 'version desconocida')"
  warn "Se recomienda yay para mejor compatibilidad con end-4/dots-hyprland."
  read -rp "  Deseas instalar yay igualmente? [s/N]: " INSTALL_YAY
  if [[ ! "$INSTALL_YAY" =~ ^[sS]$ ]]; then
    info "Usando paru como AUR helper."
  else
    AUR_HELPER=""  # Forzar instalación de yay
  fi
else
  info "No se encontro AUR helper. Se instalara yay."
fi

# Instalar yay si es necesario
if [[ -z "$AUR_HELPER" ]]; then
  info "Instalando yay desde AUR..."
  BUILD_DIR=$(mktemp -d)
  
  if ! git clone --depth 1 https://aur.archlinux.org/yay.git "$BUILD_DIR/yay" 2>/dev/null; then
    fail "No se pudo clonar el repositorio de yay. Verifica tu conexion."
    rm -rf "$BUILD_DIR"
    exit 1
  fi
  
  cd "$BUILD_DIR/yay" || exit 1
  
  if ! makepkg -si --noconfirm 2>/dev/null; then
    fail "Error compilando yay. Intentando con permisos reducidos..."
    makepkg -si --noconfirm || {
      fail "Fallo la compilacion de yay."
      info "Intenta instalarlo manualmente:"
      info "  git clone https://aur.archlinux.org/yay.git"
      info "  cd yay && makepkg -si"
      cd ~
      rm -rf "$BUILD_DIR"
      exit 1
    }
  fi
  
  cd ~
  rm -rf "$BUILD_DIR"
  
  if command -v yay &>/dev/null; then
    ok "yay instalado correctamente: $(yay --version 2>/dev/null | head -1 || echo 'version desconocida')"
    AUR_HELPER="yay"
  else
    fail "yay no quedo disponible en PATH. Agrega ~/.local/bin a tu PATH."
    exit 1
  fi
fi

# === FASE 4: GRUPOS DE USUARIO ===
header "FASE 4: Configurando grupos de usuario"

# Crear grupo i2c si no existe
if ! getent group i2c &>/dev/null; then
  info "Creando grupo i2c (necesario para sensores)..."
  if sudo groupadd i2c; then
    ok "Grupo i2c creado correctamente"
  else
    warn "No se pudo crear el grupo i2c. Algunos sensores podrian no funcionar."
  fi
else
  ok "Grupo i2c: ya existe"
fi

# Agregar usuario a grupos necesarios
CURRENT_USER=$(whoami)
GRUPOS_NECESARIOS=(video i2c input)

for grp in "${GRUPOS_NECESARIOS[@]}"; do
  if id -nG "$CURRENT_USER" | grep -qw "$grp"; then
    ok "Usuario en grupo $grp: OK"
  else
    info "Agregando $CURRENT_USER al grupo $grp..."
    if sudo usermod -aG "$grp" "$CURRENT_USER"; then
      ok "Agregado exitosamente al grupo $grp"
    else
      warn "No se pudo agregar al grupo $grp"
    fi
  fi
done

# Verificar si hay cambios en grupos
if id -nG "$CURRENT_USER" | grep -qw "i2c\|video\|input"; then
  warn "IMPORTANTE: Debes cerrar sesion y volver a entrar para aplicar los cambios de grupos."
fi

# === FASE 5: SERVICIOS ===
header "FASE 5: Configurando servicios del sistema"

# Bluetooth
if systemctl is-enabled bluetooth &>/dev/null; then
  ok "Servicio bluetooth: habilitado"
elif systemctl is-active bluetooth &>/dev/null; then
  ok "Servicio bluetooth: activo"
else
  if pacman -Q bluez &>/dev/null || pacman -Q bluez-utils &>/dev/null; then
    info "Habilitando servicio bluetooth..."
    sudo systemctl enable bluetooth --now 2>/dev/null && ok "Bluetooth habilitado" || warn "No se pudo habilitar bluetooth"
  else
    info "Bluetooth no detectado. Se omite la configuracion."
  fi
fi

# Verificar otros servicios utiles
for service in NetworkManager; do
  if systemctl is-enabled "$service" &>/dev/null; then
    ok "Servicio $service: habilitado"
  else
    warn "Servicio $service no habilitado. Considera habilitarlo: sudo systemctl enable $service"
  fi
done

# === FASE 6: CLONAR REPOSITORIO ===
header "FASE 6: Obteniendo end-4/dots-hyprland"

DOTS_DIR="$HOME/dots-hyprland"
REPO_URL="https://github.com/end-4/dots-hyprland.git"

if [[ -d "$DOTS_DIR" ]]; then
  warn "El directorio $DOTS_DIR ya existe."
  
  # Verificar si es un repositorio git
  if [[ -d "$DOTS_DIR/.git" ]]; then
    info "Directorio existente es un repositorio git."
    read -rp "  Deseas actualizarlo (git pull) o re-clonarlo? [A=actualizar/R=reclonar/N=omitir]: " REPO_ACTION
    
    case "$REPO_ACTION" in
      [aA]*)
        info "Actualizando repositorio existente..."
        cd "$DOTS_DIR" || exit 1
        if git pull --recurse-submodules; then
          ok "Repositorio actualizado correctamente."
        else
          fail "Error actualizando el repositorio."
          exit 1
        fi
        cd ~
        ;;
      [rR]*)
        info "Eliminando y re-clonando repositorio..."
        rm -rf "$DOTS_DIR"
        ;;
      *)
        info "Usando repositorio existente sin cambios."
        ;;
    esac
  else
    read -rp "  El directorio existe pero no es un repo git. Eliminar y clonar? [s/N]: " RECLONE
    if [[ "$RECLONE" =~ ^[sS]$ ]]; then
      rm -rf "$DOTS_DIR"
      info "Directorio eliminado."
    fi
  fi
fi

# Clonar si no existe
if [[ ! -d "$DOTS_DIR" ]]; then
  info "Clonando end-4/dots-hyprland..."
  info "Esto puede tardar unos minutos dependiendo de tu conexion..."
  
  if git clone --recurse-submodules "$REPO_URL" "$DOTS_DIR" 2>/dev/null; then
    ok "Repositorio clonado exitosamente en $DOTS_DIR"
    
    # Verificar submódulos
    cd "$DOTS_DIR" || exit 1
    if git submodule status | grep -q "^\-"; then
      warn "Algunos submodulos no se inicializaron. Ejecutando git submodule update --init..."
      git submodule update --init --recursive && ok "Submodulos inicializados" || warn "Error en submodulos"
    fi
    cd ~
  else
    fail "Error clonando el repositorio. Verifica:"
    fail "  - Tu conexion a internet"
    fail "  - Que GitHub no este bloqueado"
    fail "  - Intenta manualmente: git clone $REPO_URL $DOTS_DIR"
    exit 1
  fi
else
  ok "Repositorio disponible en $DOTS_DIR"
fi

# Verificar estructura del repositorio
if [[ -f "$DOTS_DIR/setup" ]] || [[ -f "$DOTS_DIR/install.sh" ]]; then
  ok "Script de instalacion encontrado"
else
  warn "No se encontro el script de instalacion. El repositorio podria estar incompleto."
  info "Archivos en el directorio:"
  ls -la "$DOTS_DIR" | head -10
fi

# === RESUMEN FINAL ===
echo ""
echo -e "${BOLD}${CYAN}=== RESUMEN FINAL =============================${RST}"

if [[ $ERRORS -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}"
  echo "  Sistema preparado correctamente!"
  echo -e "${RST}"
  echo ""
  echo -e "  ${BOLD}Para completar la instalacion:${RST}"
  echo ""
  echo -e "    1. ${CYAN}Cierra sesion y vuelve a entrar${RST} (requerido por cambios de grupos)"
  echo -e "    2. ${CYAN}cd ~/dots-hyprland${RST}"
  echo -e "    3. ${CYAN}./setup install${RST}  o  ${CYAN}./install.sh${RST}"
  echo ""
  echo -e "  ${BOLD}Comandos utiles:${RST}"
  echo -e "    Backup de configuracion actual: ${CYAN}cp -r ~/.config ~/.config.backup${RST}"
  echo -e "    Ver logs de instalacion: ${CYAN}tail -f ~/.local/share/hyprland/hyprland.log${RST}"
  echo ""
else
  echo -e "${RED}${BOLD}"
  echo "  Se encontraron $ERRORS error(es) durante la preparacion."
  echo -e "${RST}"
  echo "  Resuelve los errores antes de continuar con la instalacion."
  echo "  Puedes volver a ejecutar este script despues de corregirlos."
fi

echo -e "${BOLD}${CYAN}===============================================${RST}"
echo ""
read -rp "  Presiona ENTER para salir..." DUMMY