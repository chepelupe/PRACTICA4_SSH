#!/bin/bash
# ==============================================================================
# FUNCIONES DNS - VERSION FINAL
# ==============================================================================

source ./funciones_compartidas.sh

verificar_instalacion_dns() {
    echo ""
    echo "--- verificando dns ---"
    if dpkg -s bind9 >/dev/null 2>&1; then 
        echo "[ok] dns server instalado"
    else 
        echo "[x] dns server no instalado"
    fi
}

instalar_dns() {
    echo "instalando servidor dns..."
    apt update
    DEBIAN_FRONTEND=noninteractive apt-get install -y bind9 bind9utils dnsutils
    if [ $? -eq 0 ]; then
        echo "instalacion completada"
        if [ -f "/etc/init.d/bind9" ]; then
            update-rc.d bind9 defaults > /dev/null 2>&1
        fi
    else
        echo "error en la instalacion"
    fi
}

reiniciar_servicio_dns() {
    echo "reiniciando servicio dns..."
    if [ -f "/etc/init.d/bind9" ]; then
        /etc/init.d/bind9 restart
        sleep 2
    fi
}

agregar_zona() {
    SERVER_IP=$(obtener_ip_actual)
    if [ -z "$SERVER_IP" ]; then 
        SERVER_IP=$(ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
        [ -z "$SERVER_IP" ] && SERVER_IP="192.168.56.100"
    fi
    
    echo ""
    echo "--- agregar zona dns ---"
    read -p "nombre del dominio (ej. siganplaticando.com): " dominio
    [ -z "$dominio" ] && return
    
    local virtual_ip=""
    while true; do
        read -p "ip virtual para $dominio (ej. 192.168.56.200): " virtual_ip
        validar_ip_completa "$virtual_ip" || continue
        if [ "$virtual_ip" == "$SERVER_IP" ]; then
            echo "error: no puedes usar la ip del servidor"
            continue
        fi
        local red_ip=$(echo $virtual_ip | cut -d'.' -f1-3)
        if [ "$red_ip" != "192.168.56" ]; then
            echo "error: la ip debe estar en 192.168.56.0/24"
            continue
        fi
        break
    done
    
    echo ""
    echo "creando ip virtual..."
    crear_ip_virtual "$virtual_ip" "$INTERFACE"
    
    CONF="/etc/bind/named.conf.local"
    FILE="/var/cache/bind/db.$dominio"
    mkdir -p /var/cache/bind
    
    if [ -f "$CONF" ] && grep -q "$dominio" "$CONF" 2>/dev/null; then
        echo "la zona ya existe"
        read -p "recrear? (s/n): " rec
        [ "$rec" != "s" ] && return
        sed -i "/zone \"$dominio\" {/,/};/d" "$CONF"
    fi
    
    cat >> "$CONF" <<EOF

zone "$dominio" {
    type master;
    file "$FILE";
};
EOF
    
    cat > "$FILE" <<EOF
\$TTL 604800
@ IN SOA ns1.$dominio. admin.$dominio. (
    $(date +%Y%m%d)01
    604800
    86400
    2419200
    604800 )

@ IN NS ns1.$dominio.
@ IN NS ns2.$dominio.

ns1 IN A $SERVER_IP
ns2 IN A $SERVER_IP

@ IN A $virtual_ip
www IN A $virtual_ip
mail IN A $virtual_ip
ftp IN A $virtual_ip

@ IN MX 10 mail.$dominio.
EOF
    
    chmod 644 "$FILE"
    
    echo ""
    echo "reiniciando servicio dns..."
    reiniciar_servicio_dns
    
    echo ""
    echo "dominio $dominio configurado con ip $virtual_ip"
    echo "prueba: nslookup $dominio $SERVER_IP"
}

eliminar_zona() {
    echo ""
    echo "--- eliminar zona dns ---"
    CONF="/etc/bind/named.conf.local"
    
    if [ ! -f "$CONF" ]; then
        echo "no hay archivo de configuracion"
        return
    fi
    
    echo "zonas actuales:"
    grep "zone" "$CONF" | cut -d'"' -f2
    
    read -p "nombre de la zona a borrar: " zona_del
    [ -z "$zona_del" ] && return
    
    if grep -q "$zona_del" "$CONF"; then
        archivo="/var/cache/bind/db.$zona_del"
        if [ -f "$archivo" ]; then
            virtual_ip=$(grep -E "^@\s+IN\s+A" "$archivo" | awk '{print $4}')
            if [ -n "$virtual_ip" ]; then
                echo "eliminando ip virtual $virtual_ip"
                eliminar_ip_virtual "$virtual_ip" "$INTERFACE"
            fi
        fi
        
        sed -i "/zone \"$zona_del\" {/,/};/d" "$CONF"
        rm -f "$archivo"
        reiniciar_servicio_dns
        echo "zona eliminada"
    else
        echo "zona no encontrada"
    fi
}

listar_zonas() {
    echo ""
    echo "--- dominios configurados ---"
    if [ -f "/etc/bind/named.conf.local" ]; then
        grep "zone" /etc/bind/named.conf.local | cut -d'"' -f2
    else
        echo "no hay zonas configuradas"
    fi
}

submenu_dns() {
    while true; do
        clear
        echo ""
        echo "========================================"
        echo "   gestion de dns                       "
        echo "========================================"
        echo "1) verificar instalacion dns"
        echo "2) instalar servidor dns"
        echo "3) agregar zona"
        echo "4) eliminar zona"
        echo "5) listar zonas"
        echo "6) volver"
        echo "========================================"
        
        read -p "seleccione opcion: " subopc
        case $subopc in
            1) verificar_instalacion_dns; read -p "presione enter..." ;;
            2) instalar_dns; read -p "presione enter..." ;;
            3) agregar_zona; read -p "presione enter..." ;;
            4) eliminar_zona; read -p "presione enter..." ;;
            5) listar_zonas; read -p "presione enter..." ;;
            6) return ;;
            *) echo "opcion invalida"; sleep 1 ;;
        esac
    done
}