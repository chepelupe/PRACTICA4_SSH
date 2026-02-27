#!/bin/bash
# ==============================================================================
# FUNCIONES DHCP - VERSION FINAL
# ==============================================================================

source ./funciones_compartidas.sh

verificar_instalacion_dhcp() {
    echo ""
    echo "--- verificando dhcp ---"
    if dpkg -s isc-dhcp-server >/dev/null 2>&1; then 
        echo "[ok] dhcp server instalado"
    else 
        echo "[x] dhcp server no instalado"
    fi
}

instalar_dhcp() {
    echo "instalando servidor dhcp..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y isc-dhcp-server
    if [ $? -eq 0 ]; then
        echo "instalacion completada"
        if [ -f "/etc/init.d/isc-dhcp-server" ]; then
            update-rc.d isc-dhcp-server defaults > /dev/null 2>&1
        fi
    else
        echo "error en la instalacion"
    fi
}

validar_rango_dhcp() {
    local ip_ini=$1
    local ip_fin=$2
    local server_ip=$3
    
    local red_server=$(echo $server_ip | cut -d'.' -f1-3)
    local red_ini=$(echo $ip_ini | cut -d'.' -f1-3)
    local red_fin=$(echo $ip_fin | cut -d'.' -f1-3)
    
    if [ "$red_server" != "$red_ini" ] || [ "$red_server" != "$red_fin" ]; then
        echo "error: las ips deben estar en la misma red que el servidor"
        return 1
    fi
    
    local num_ini=$(echo $ip_ini | cut -d'.' -f4)
    local num_fin=$(echo $ip_fin | cut -d'.' -f4)
    
    if [ $num_ini -ge $num_fin ]; then
        echo "error: la ip inicial debe ser menor que la final"
        return 1
    fi
    
    if [ "$ip_ini" == "$server_ip" ] || [ "$ip_fin" == "$server_ip" ]; then
        echo "error: no puedes usar la ip del servidor en el rango"
        return 1
    fi
    
    return 0
}

configurar_dhcp() {
    SERVER_IP=$(obtener_ip_actual)
    if [ -z "$SERVER_IP" ]; then 
        echo "configura la ip estatica primero"
        return
    fi

    echo ""
    echo "--- configurar servidor dhcp ---"
    echo "ip del servidor: $SERVER_IP"
    read -p "nombre del ambito: " scope_name
    
    local ip_ini=""
    while true; do
        read -p "ip inicial (ej. 192.168.56.150): " ip_ini
        validar_ip_completa "$ip_ini" && break
        echo "ip invalida"
    done

    local ip_fin=""
    while true; do
        read -p "ip final (ej. 192.168.56.200): " ip_fin
        validar_ip_completa "$ip_fin" && break
        echo "ip invalida"
    done
    
    if ! validar_rango_dhcp "$ip_ini" "$ip_fin" "$SERVER_IP"; then
        read -p "presione enter..."
        return
    fi
    
    local gateway=""
    while true; do
        read -p "gateway (enter para omitir): " input_gw
        if [ -z "$input_gw" ]; then 
            gateway=""; break
        fi
        if validar_ip_completa "$input_gw"; then
            local red_gw=$(echo $input_gw | cut -d'.' -f1-3)
            local red_server=$(echo $SERVER_IP | cut -d'.' -f1-3)
            if [ "$red_gw" == "$red_server" ]; then
                gateway=$input_gw; break
            else
                echo "error: el gateway debe estar en la misma red"
            fi
        else
            echo "ip invalida"
        fi
    done

    local lease_time="86400"
    read -p "tiempo concesion en segundos [86400]: " input_lease
    if [ ! -z "$input_lease" ] && [ "$input_lease" -gt 0 ]; then
        lease_time=$input_lease
    fi
    
    local subnet_base=$(echo $SERVER_IP | cut -d'.' -f1-3)
    SUBNET="${subnet_base}.0"
    BROADCAST="${subnet_base}.255"
    
    if [ -f "/etc/default/isc-dhcp-server" ]; then
        sed -i 's/^INTERFACESv4=.*/INTERFACESv4="'$INTERFACE'"/' /etc/default/isc-dhcp-server
    else
        echo "INTERFACESv4=\"$INTERFACE\"" > /etc/default/isc-dhcp-server
    fi
    
    cat > /etc/dhcp/dhcpd.conf <<EOF
option subnet-mask 255.255.255.0;
option broadcast-address $BROADCAST;
default-lease-time $lease_time;
max-lease-time $((lease_time * 2));
authoritative;

subnet $SUBNET netmask 255.255.255.0 {
    range $ip_ini $ip_fin;
    option domain-name-servers $SERVER_IP;
EOF

    if [ ! -z "$gateway" ]; then
        echo "    option routers $gateway;" >> /etc/dhcp/dhcpd.conf
    fi

    echo "}" >> /etc/dhcp/dhcpd.conf
    
    echo "reiniciando servicio dhcp..."
    if [ -f "/etc/init.d/isc-dhcp-server" ]; then
        /etc/init.d/isc-dhcp-server restart
        sleep 3
        if /etc/init.d/isc-dhcp-server status > /dev/null 2>&1; then
            echo "servidor dhcp configurado"
        else
            echo "fallo: el servicio dhcp no arranco"
        fi
    fi
}