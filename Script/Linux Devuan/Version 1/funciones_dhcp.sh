#!/bin/bash
# ==============================================================================
# FUNCIONES DHCP - Para Linux (Devuan)
# ==============================================================================

# Cargar funciones comunes si no están disponibles
if [ -z "$GREEN" ]; then
    source "$(dirname "$0")/comunes.sh"
fi

verificar_instalacion_dhcp() {
    echo -e "\n${CYAN}--- VERIFICANDO PAQUETES DHCP (DEVUAN) ---${NC}"
    
    if dpkg -s isc-dhcp-server >/dev/null 2>&1; then 
        echo -e "${GREEN}[OK] DHCP Server${NC}"
        if [ -f "/etc/init.d/isc-dhcp-server" ]; then
            echo -e "      ${GREEN}✓ Script de inicio encontrado${NC}"
        fi
    else 
        echo -e "${RED}[X] DHCP Server NO instalado${NC}"
    fi
}

instalar_dhcp() {
    echo -e "${YELLOW}Instalando servidor DHCP...${NC}"
    
    DEBIAN_FRONTEND=noninteractive apt-get install -y isc-dhcp-server
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Instalación DHCP completada.${NC}"
        
        if [ -f "/etc/init.d/isc-dhcp-server" ]; then
            update-rc.d isc-dhcp-server defaults > /dev/null 2>&1
            echo -e "${GREEN}✓ Servicio configurado para inicio automático${NC}"
        fi
    else
        echo -e "${RED}✗ Error en la instalación DHCP.${NC}"
    fi
}

configurar_dhcp() {
    SERVER_IP=$(obtener_ip_actual)
    if [ -z "$SERVER_IP" ]; then 
        echo -e "${RED}¡ALERTA! Configura la IP Estática primero.${NC}"
        return
    fi

    echo -e "\n${YELLOW}--- CONFIGURAR SERVIDOR DHCP (PARA CLIENTES WINDOWS) ---${NC}"
    read -p "Nombre del Ámbito DHCP (ej. Red_Windows): " scope_name
    
    local ip_ini=""
    while true; do
        read -p "IP Inicial del rango (para clientes Windows): " ip_ini
        validar_ip_completa "$ip_ini"
        if [ $? -eq 0 ]; then break; fi
        echo -e "${RED}IP inválida o prohibida.${NC}"
    done

    local ip_fin=""
    while true; do
        read -p "IP Final del rango: " ip_fin
        validar_ip_completa "$ip_fin"
        if [ $? -eq 0 ]; then break; fi
        echo -e "${RED}IP inválida o prohibida.${NC}"
    done
    
    local gateway=""
    while true; do
        read -p "Gateway para clientes (Enter para omitir): " input_gw
        if [ -z "$input_gw" ]; then 
            gateway=""; break
        fi
        validar_ip_completa "$input_gw"
        if [ $? -eq 0 ]; then 
            gateway=$input_gw; break
        fi
        echo -e "${RED}IP inválida o prohibida.${NC}"
    done

    local lease_time=""
    while true; do
        read -p "Tiempo concesión (segundos) [Enter=86400]: " input_lease
        if [ -z "$input_lease" ]; then 
            lease_time=86400; break
        fi
        if [[ "$input_lease" =~ ^[0-9]+$ ]] && [ "$input_lease" -gt 0 ]; then
            lease_time=$input_lease; break
        else
            echo -e "${RED}Error: Debe ser un número entero positivo.${NC}"
        fi
    done
    
    SUBNET=$(echo $SERVER_IP | cut -d'.' -f1-3).0
    BROADCAST="${SUBNET%.*}.255"
    
    echo -e "${CYAN}Generando configuración DHCP...${NC}"
    
    if [ -f "/etc/default/isc-dhcp-server" ]; then
        sed -i 's/^INTERFACESv4=.*/INTERFACESv4="'$INTERFACE'"/' /etc/default/isc-dhcp-server
    else
        echo "INTERFACESv4=\"$INTERFACE\"" > /etc/default/isc-dhcp-server
    fi
    
    cat > /etc/dhcp/dhcpd.conf <<EOF
# Configuración DHCP para clientes Windows
# Ámbito: $scope_name
# Generado: $(date)

option subnet-mask 255.255.255.0;
option broadcast-address $BROADCAST;
option netbios-name-servers $SERVER_IP;
option netbios-node-type 8;

default-lease-time $lease_time;
max-lease-time $((lease_time * 2));
authoritative;

subnet $SUBNET netmask 255.255.255.0 {
    range $ip_ini $ip_fin;
    option domain-name-servers $SERVER_IP;
    option domain-name "lab.local";
EOF

    if [ ! -z "$gateway" ]; then
        echo "    option routers $gateway;" >> /etc/dhcp/dhcpd.conf
    fi

    echo "}" >> /etc/dhcp/dhcpd.conf
    
    echo -e "${YELLOW}Reiniciando servicio DHCP...${NC}"
    /etc/init.d/isc-dhcp-server restart
    sleep 3
    
    if /etc/init.d/isc-dhcp-server status > /dev/null 2>&1; then
        echo -e "${GREEN}>>> SERVIDOR DHCP CONFIGURADO CORRECTAMENTE <<<${NC}"
    else
        echo -e "${RED}FALLO: El servicio DHCP no arrancó.${NC}"
        tail -30 /var/log/syslog | grep -i "dhcpd\|dhcp" | tail -10
    fi
}