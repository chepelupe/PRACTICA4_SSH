#!/bin/bash
# ==============================================================================
# GESTOR DE INFRAESTRUCTURA - VERSIÓN MODULAR
# Devuan Linux (Servidor) y Windows 10 (Cliente)
# ==============================================================================

# Obtener la ruta absoluta del directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =========================
# CARGAR MÓDULOS (CON TUS NOMBRES DE ARCHIVO)
# =========================

# Verificar que los archivos existen antes de cargarlos
echo "Cargando módulos desde: $SCRIPT_DIR"

if [ -f "$SCRIPT_DIR/funciones_compartidas.sh" ]; then
    source "$SCRIPT_DIR/funciones_compartidas.sh"
    echo "✓ Módulo funciones_compartidas.sh cargado"
else
    echo "✗ Error: No se encuentra funciones_compartidas.sh en $SCRIPT_DIR"
    exit 1
fi

if [ -f "$SCRIPT_DIR/funciones_dhcp" ]; then
    source "$SCRIPT_DIR/funciones_dhcp"
    echo "✓ Módulo funciones_dhcp cargado"
else
    echo "✗ Error: No se encuentra funciones_dhcp en $SCRIPT_DIR"
    exit 1
fi

if [ -f "$SCRIPT_DIR/funciones_dns" ]; then
    source "$SCRIPT_DIR/funciones_dns"
    echo "✓ Módulo funciones_dns cargado"
else
    echo "✗ Error: No se encuentra funciones_dns en $SCRIPT_DIR"
    exit 1
fi

if [ -f "$SCRIPT_DIR/funciones_ssh" ]; then
    source "$SCRIPT_DIR/funciones_ssh"
    echo "✓ Módulo funciones_ssh cargado"
else
    echo "✗ Error: No se encuentra funciones_ssh en $SCRIPT_DIR"
    exit 1
fi

echo "Todos los módulos cargados correctamente."
sleep 2

# =========================
# FUNCIONES ADICIONALES
# =========================

instalar_todos_roles() {
    echo -e "\n${CYAN}--- INSTALANDO TODOS LOS ROLES ---${NC}"
    echo -e "${YELLOW}Actualizando repositorios...${NC}"
    apt-get update
    
    # Llamar a las funciones de instalación de cada módulo
    instalar_dhcp
    instalar_dns
    instalar_ssh_linux
    
    configurar_firewall_ping
}

configurar_ip_estatica() {
    CURRENT_IP=$(obtener_ip_actual)
    echo -e "\n${YELLOW}--- CONFIGURACIÓN IP ESTÁTICA ($INTERFACE) ---${NC}"
    echo "IP Actual: ${CURRENT_IP:-Ninguna}"
    
    read -p "¿Configurar IP ESTATICA nueva? (s/n): " resp
    if [[ "$resp" == "s" ]]; then
        local nueva_ip=""
        
        while true; do
            read -p "Ingrese IP Estática: " nueva_ip
            validar_ip_completa "$nueva_ip"
            res=$?
            if [ $res -eq 0 ]; then
                break
            elif [ $res -eq 2 ]; then
                echo -e "${RED}Error: IP Prohibida o Reservada.${NC}"
            else
                echo -e "${RED}Error: Formato inválido.${NC}"
            fi
        done

        echo -e "${CYAN}Aplicando configuración...${NC}"
        
        cp /etc/network/interfaces /etc/network/interfaces.bak 2>/dev/null
        
        cat > /etc/network/interfaces <<EOF
# Configuración de red - Devuan
# Generado automáticamente por gestor-infraestructura

auto lo
iface lo inet loopback

allow-hotplug eth0
iface eth0 inet dhcp

auto $INTERFACE
iface $INTERFACE inet static
    address $nueva_ip
    netmask 255.255.255.0
EOF

        ip addr flush dev $INTERFACE
        ip addr add $nueva_ip/24 dev $INTERFACE
        ip link set $INTERFACE up
        
        echo "nameserver 127.0.0.1" > /etc/resolv.conf
        
        configurar_firewall_ping
        
        echo -e "${GREEN}IP $nueva_ip asignada a $INTERFACE.${NC}"
    fi
}

verificar_instalacion() {
    echo -e "\n${CYAN}--- VERIFICACIÓN COMPLETA DEL SISTEMA ---${NC}"
    
    # Verificar IPs
    echo -e "\n${CYAN}IPs configuradas en $INTERFACE:${NC}"
    ip addr show $INTERFACE | grep "inet" | awk '{print "   " $2}' || echo "   No hay IPs"
    
    # Verificar servicios
    echo -e "\n${CYAN}Estado de servicios:${NC}"
    
    # DHCP
    if dpkg -s isc-dhcp-server >/dev/null 2>&1; then 
        echo -e "  DHCP: ${GREEN}Instalado${NC}"
        if /etc/init.d/isc-dhcp-server status > /dev/null 2>&1; then
            echo -e "         ${GREEN}✓ Activo${NC}"
        else
            echo -e "         ${RED}✗ Inactivo${NC}"
        fi
    fi
    
    # DNS
    if dpkg -s bind9 >/dev/null 2>&1; then 
        echo -e "  DNS:   ${GREEN}Instalado${NC}"
        if pgrep named > /dev/null; then
            echo -e "         ${GREEN}✓ Activo${NC}"
        else
            echo -e "         ${RED}✗ Inactivo${NC}"
        fi
    fi
    
    # SSH
    if dpkg -s openssh-server >/dev/null 2>&1; then 
        echo -e "  SSH:   ${GREEN}Instalado${NC}"
        if systemctl is-active ssh >/dev/null 2>&1; then
            echo -e "         ${GREEN}✓ Activo${NC}"
        else
            echo -e "         ${RED}✗ Inactivo${NC}"
        fi
    fi
}

ejecutar_pruebas() {
    SERVER_IP=$(obtener_ip_actual)
    echo -e "\n${CYAN}--- PRUEBAS DE RESOLUCIÓN ---${NC}"
    read -p "Dominio a probar (ej. laboratorio.local): " dom
    if [ -z "$dom" ]; then return; fi
    
    echo -e "\n${YELLOW}[PRUEBA 1: NSLOOKUP desde Devuan]${NC}"
    nslookup "$dom" localhost
    
    echo -e "\n${YELLOW}[PRUEBA 2: PING desde Devuan al dominio]${NC}"
    ping -c 2 "$dom"
    
    echo -e "\n${YELLOW}[PRUEBA 3: Verificar IP virtual]${NC}"
    ip addr show $INTERFACE | grep "inet"
    
    echo -e "\n${CYAN}--- INSTRUCCIONES PARA CLIENTE WINDOWS ---${NC}"
    echo "1. Abre CMD como administrador"
    echo "2. Ejecuta: ipconfig /flushdns"
    echo "3. Prueba: ping $dom"
    echo "4. Prueba: nslookup $dom"
    
    read -p "Enter para continuar..."
}

# =========================
# VERIFICACIÓN INICIAL
# =========================

# Verificar root (función definida en funciones_compartidas.sh)
check_root

# Limpiar caracteres Windows
sed -i 's/\r$//' "$0" 2>/dev/null

# Seleccionar interfaz al inicio (función definida en funciones_compartidas.sh)
seleccionar_interfaz

# Mostrar información del sistema
echo -e "\n${CYAN}Sistema detectado:${NC} $(lsb_release -d 2>/dev/null | cut -f2 || echo 'Devuan')"
echo -e "${CYAN}Interfaz interna:${NC} $INTERFACE"
echo -e "${CYAN}IP principal:${NC} $(obtener_ip_actual)"
sleep 2

# =========================
# MENÚ PRINCIPAL
# =========================

while true; do
    clear
    IP_ACTUAL=$(obtener_ip_actual)
    IPS_COUNT=$(ip addr show $INTERFACE | grep -c "inet")
    IPS_VIRT_COUNT=$((IPS_COUNT - 1))
    
    echo -e "${YELLOW}===============================================${NC}"
    echo -e "${YELLOW}   GESTOR DE INFRAESTRUCTURA - VERSIÓN 6.0   ${NC}"
    echo -e "${YELLOW}   (Servidor Linux Devuan)                   ${NC}"
    echo -e "${YELLOW}===============================================${NC}"
    echo -e "Interfaz:       ${GREEN}$INTERFACE${NC}"
    echo -e "IP Principal:   ${GREEN}$IP_ACTUAL${NC}"
    echo -e "IPs Virtuales:  ${GREEN}$IPS_VIRT_COUNT${NC}"
    echo -e "${YELLOW}===============================================${NC}"
    echo ""
    echo "  1)  Verificar instalación completa"
    echo "  2)  Instalar todos los roles (DHCP + DNS + SSH)"
    echo ""
    echo "  --- CONFIGURACIÓN DE RED ---"
    echo "  3)  Configurar IP Estática (principal)"
    echo ""
    echo "  --- SERVICIOS ---"
    echo "  4)  Configurar servidor DHCP"
    echo "  5)  Gestión de dominios DNS (con IPs virtuales)"
    echo "  6)  Gestión de SSH (acceso remoto)"
    echo ""
    echo "  --- PRUEBAS Y UTILIDADES ---"
    echo "  7)  Ejecutar pruebas de resolución"
    echo "  8)  Ver instrucciones para cliente Windows"
    echo "  9)  Salir"
    echo ""
    echo -e "${YELLOW}===============================================${NC}"
    
    read -p "Seleccione una opción [1-9]: " MAIN_OPC
    
    case $MAIN_OPC in
        1) verificar_instalacion; read -p "Enter..." ;;
        2) instalar_todos_roles; read -p "Enter..." ;;
        3) configurar_ip_estatica; read -p "Enter..." ;;
        4) configurar_dhcp; read -p "Enter..." ;;
        5) submenu_dns ;;
        6) submenu_ssh ;;
        7) ejecutar_pruebas ;;
        8) generar_instrucciones_windows ;;
        9) 
            echo -e "${GREEN}¡Hasta luego!${NC}"
            exit 0 
            ;;
        *) 
            echo -e "${RED}Opción inválida${NC}"
            sleep 1
            ;;
    esac
done