#!/bin/bash
# ==============================================================================
# MENU PRINCIPAL
# ==============================================================================

echo "cargando modulos..."

source ./funciones_compartidas.sh
source ./funciones_dhcp.sh
source ./funciones_dns.sh
source ./funciones_ssh.sh

echo "todos los modulos cargados"
sleep 2

# =========================
# FUNCIONES ADICIONALES
# =========================

instalar_todos_roles() {
    echo ""
    echo "--- instalando todos los roles ---"
    apt-get update
    instalar_dhcp
    instalar_dns
    echo "instalacion completada"
}

activar_todas_interfaces() {
    echo ""
    echo "--- activando todas las interfaces ---"
    activar_interfaces_red
    activar_eth2
}

configurar_ip_estatica() {
    if [ -z "$INTERFACE" ] || [ "$INTERFACE" == "pendiente" ]; then
        echo ""
        echo "primero selecciona una interfaz"
        seleccionar_interfaz
    fi
    
    CURRENT_IP=$(obtener_ip_actual 2>/dev/null)
    echo ""
    echo "--- ip estatica ($INTERFACE) ---"
    echo "ip actual: ${CURRENT_IP:-ninguna}"
    echo ""
    
    read -p "ip estatica (ej. 192.168.56.100): " nueva_ip
    validar_ip_completa "$nueva_ip" || { echo "ip invalida"; return; }
    
    if [ "$(echo $nueva_ip | cut -d'.' -f1-3)" != "192.168.56" ]; then
        echo "error: debe ser 192.168.56.0/24"
        return
    fi
    
    ip addr flush dev $INTERFACE 2>/dev/null
    ip addr add $nueva_ip/24 dev $INTERFACE
    ip link set $INTERFACE up
    
    cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

allow-hotplug eth0
iface eth0 inet dhcp

auto $INTERFACE
iface $INTERFACE inet static
    address $nueva_ip
    netmask 255.255.255.0
EOF

    echo "ip $nueva_ip asignada"
}

verificar_instalacion() {
    echo ""
    echo "--- verificacion ---"
    echo ""
    echo "interfaces:"
    ip -4 addr show | grep -v "127.0.0.1" | sed 's/^/  /'
    echo ""
    echo "estado eth2:"
    ip link show eth2 2>/dev/null | grep "UP" && echo "  eth2: ACTIVA" || echo "  eth2: INACTIVA"
    echo ""
    echo "servicios:"
    dpkg -s isc-dhcp-server >/dev/null 2>&1 && echo "  dhcp: instalado" || echo "  dhcp: no"
    dpkg -s bind9 >/dev/null 2>&1 && echo "  dns: instalado" || echo "  dns: no"
    dpkg -s openssh-server >/dev/null 2>&1 && echo "  ssh: instalado" || echo "  ssh: no"
}

mostrar_instrucciones() {
    echo ""
    echo "================================================"
    echo "instrucciones"
    echo "================================================"
    echo ""
    echo "1. configura el adaptador 3 como 'solo anfitrion'"
    echo "2. opcion 2a para activar todas las interfaces"
    echo "3. opcion 6 para configurar ssh en eth2"
    echo "4. conectate con: ssh $(whoami)@192.168.56.10"
    echo "5. prueba: nslookup siganplaticando.com 192.168.56.100"
    echo "6. prueba: ping 192.168.56.200"
    echo "================================================"
}

# =========================
# VERIFICACION INICIAL
# =========================

check_root

clear
echo "================================================"
echo "   gestor de infraestructura                    "
echo "================================================"
echo ""

read -p "seleccionar interfaz interna ahora? (s/n): " sel_interfaz
if [[ "$sel_interfaz" == "s" ]]; then
    seleccionar_interfaz
else
    INTERFACE="pendiente"
fi

# =========================
# MENU PRINCIPAL
# =========================

while true; do
    clear
    echo "==============================================="
    echo "   menu principal                              "
    echo "==============================================="
    echo "interfaz interna: ${INTERFACE:-no definida}"
    echo "==============================================="
    echo ""
    echo "  1)  verificar instalacion"
    echo "  2)  instalar todos los roles"
    echo "  2a) activar todas las interfaces (eth1 y eth2)"
    echo ""
    echo "  3)  ip estatica en eth1"
    echo "  4)  configurar dhcp"
    echo "  5)  gestion de dns"
    echo "  6)  configurar ssh en eth2"
    echo ""
    echo "  7)  instrucciones"
    echo "  8)  seleccionar interfaz"
    echo "  9)  salir"
    echo ""
    echo "==============================================="
    
    read -p "seleccione opcion: " MAIN_OPC
    
    case $MAIN_OPC in
        1) verificar_instalacion; read -p "presione enter..." ;;
        2) instalar_todos_roles; read -p "presione enter..." ;;
        2a) activar_todas_interfaces; read -p "presione enter..." ;;
        3) configurar_ip_estatica; read -p "presione enter..." ;;
        4) configurar_dhcp; read -p "presione enter..." ;;
        5) submenu_dns ;;
        6) submenu_ssh ;;
        7) mostrar_instrucciones; read -p "presione enter..." ;;
        8) seleccionar_interfaz; read -p "presione enter..." ;;
        9) echo "hasta luego"; exit 0 ;;
        *) echo "opcion invalida"; sleep 1 ;;
    esac
done