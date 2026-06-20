#!/usr/bin/env bash

# Verifica paquetes maliciosos conocidos desde la lista oficial de Arch Linux
LIST_URL="https://md.archlinux.org/s/SxbqukK6IA"
TEMP_FILE=$(mktemp) || { echo "ERROR: No se pudo crear archivo temporal"; exit 1; }
trap 'rm -f "$TEMP_FILE"' EXIT

# Colores para la salida
ROJO='\033[0;31m'
VERDE='\033[0;32m'
AMARILLO='\033[1;33m'
NC='\033[0m' # Sin Color

echo "Obteniendo lista de paquetes infectados desde Arch Linux..."

# Descargar la lista con timeout y reintentos
if ! curl -fsSL --connect-timeout 10 --max-time 30 --retry 3 "$LIST_URL" -o "$TEMP_FILE"; then
    echo -e "${ROJO}ERROR: No se pudo descargar la lista desde $LIST_URL${NC}"
    exit 1
fi

# Verificar que el archivo no esté vacío
if [[ ! -s "$TEMP_FILE" ]]; then
    echo -e "${ROJO}ERROR: El archivo descargado está vacío${NC}"
    exit 1
fi

# Extraer nombres de paquetes válidos (solo minúsculas, dígitos, puntos, guiones, etc.)
mapfile -t PAQUETES_INFECTADOS < <(
    sed 's/<[^>]*>//g' "$TEMP_FILE" \
    | grep -oP '^[a-z0-9][a-z0-9_.+\-]*[a-z0-9]$' \
    | sort -u
)

total=${#PAQUETES_INFECTADOS[@]}
if [[ $total -eq 0 ]]; then
    echo -e "${ROJO}ERROR: No se encontraron nombres de paquetes válidos en la lista${NC}"
    exit 1
fi

echo -e "${AMARILLO}Verificando $total paquetes potencialmente infectados...${NC}"
echo ""

# Obtener paquetes instalados (foreign + AUR)
echo "Obteniendo lista de paquetes instalados (AUR/foreign)..."
mapfile -t instalados < <(pacman -Qmq 2>/dev/null | sort)

if [[ ${#instalados[@]} -eq 0 ]]; then
    echo -e "${AMARILLO}ATENCION: No se encontraron paquetes AUR instalados${NC}"
    echo -e "${VERDE}Sistema limpio - no tienes paquetes AUR que verificar${NC}"
    exit 0
fi

# Comparar listas
mapfile -t encontrados < <(comm -12 <(printf "%s\n" "${instalados[@]}") <(printf "%s\n" "${PAQUETES_INFECTADOS[@]}"))

# Mostrar resultados
if [[ ${#encontrados[@]} -eq 0 ]]; then
    echo -e "${VERDE}Sistema limpio! No se encontraron paquetes infectados instalados.${NC}"
else
    echo -e "${ROJO}ALERTA! Se encontraron ${#encontrados[@]} paquete(s) potencialmente infectado(s):${NC}"
    echo ""
    for pkg in "${encontrados[@]}"; do
        # Obtener información adicional del paquete si está disponible
        info=$(pacman -Qi "$pkg" 2>/dev/null | grep -E "Installed Date|Install Reason|Build Date" | sed 's/^/    /')
        echo -e "${ROJO}  * $pkg${NC}"
        [[ -n "$info" ]] && echo "$info"
        echo ""
    done
    
    echo -e "${AMARILLO}ACCIONES RECOMENDADAS:${NC}"
    echo "  1. No ejecutes estos paquetes ni sus binarios"
    echo "  2. Investiga cada paquete con: pacman -Qi <paquete>"
    echo "  3. Considera eliminar los paquetes infectados: sudo pacman -Rns <paquete>"
    echo "  4. Cambia tus contraseñas y claves SSH si usaste estos paquetes"
    echo "  5. Revisa los logs del sistema en busca de actividad sospechosa"
fi

# Mostrar estadísticas
echo ""
echo -e "${AMARILLO}Estadisticas:${NC}"
echo "  * Paquetes en lista negra: $total"
echo "  * Paquetes AUR instalados: ${#instalados[@]}"
echo "  * Paquetes infectados encontrados: ${#encontrados[@]}"