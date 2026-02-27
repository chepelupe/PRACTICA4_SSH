#!/bin/bash
# ==============================================================================
# FUNCIONES DNS - Para Linux (Devuan)
# ==============================================================================

# Cargar funciones comunes si no están disponibles
if [ -z "$GREEN" ]; then
    source "$(dirname "$0")/comunes.sh"
fi

verificar_instalacion_dns() {
    echo -e "\n${CYAN}--- VERIFICANDO PAQUETES DNS (DEVUAN) ---${NC}"
    
    if dpkg -s bind9 >/dev/null 2>&1; then 
        echo -e "${GREEN}[OK] DNS Server (BIND9)${NC}"
        if [ -f "/etc/init.d/bind9" ] || [ -f "/etc/init.d/named" ]; then
            echo -e "      ${GREEN}✓ Script de inicio encontrado${NC}"
        fi
    else 
        echo -e "${RED}[X] DNS Server NO instalado${NC}"
    fi
}

instalar_dns() {
    echo -e "${YELLOW}Instalando servidor DNS (BIND9)...${NC}"
    
    DEBIAN_FRONTEND=noninteractive apt-get install -y bind9 bind9utils dnsutils
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Instalación DNS completada.${NC}"
        
        if [ -f "/etc/init.d/bind9" ]; then
            update-rc.d bind9 defaults > /dev/null 2>&1
            echo -e "${GREEN}✓ Servicio configurado para inicio automático${NC}"
        elif [ -f "/etc/init.d/named" ]; then
            update-rc.d named defaults > /dev/null 2>&1
            echo -e "${GREEN}✓ Servicio configurado para inicio automático${NC}"
        fi
    else
        echo -e "${RED}✗ Error en la instalación DNS.${NC}"
    fi
}

reiniciar_servicio_dns() {
    echo -e "${YELLOW}Reiniciando servicio DNS...${NC}"
    
    if [ -f "/etc/init.d/bind9" ]; then
        /etc/init.d/bind9 restart
        sleep 2
        return 0
    elif [ -f "/etc/init.d/named" ]; then
        /etc/init.d/named restart
        sleep 2
        return 0
    elif pgrep named > /dev/null; then
        pkill -HUP named
        sleep 2
        return 0
    fi
    
    return 1
}

agregar_zona() {
    SERVER_IP=$(obtener_ip_actual)
    if [ -z "$SERVER_IP" ]; then 
        SERVER_IP=$(ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
        [ -z "$SERVER_IP" ] && SERVER_IP="10.0.0.1"
    fi
    
    echo -e "\n${YELLOW}--- AGREGAR ZONA DNS (CON IP VIRTUAL AUTOMÁTICA) ---${NC}"
    echo -e "${CYAN}NOTA: Se creará automáticamente una IP virtual en el servidor${NC}"
    
    read -p "Nombre del Dominio (ej. laboratorio.local): " dominio
    [ -z "$dominio" ] && return
    
    local virtual_ip=""
    while true; do
        read -p "IP virtual para $dominio (ej. 10.0.0.6): " virtual_ip
        validar_ip_completa "$virtual_ip"
        if [ $? -eq 0 ]; then 
            if [ "$virtual_ip" == "$SERVER_IP" ]; then
                echo -e "${RED}Error: No puedes usar la IP del servidor ($SERVER_IP) como IP virtual${NC}"
                continue
            fi
            break 
        else
            echo -e "${RED}IP inválida o prohibida.${NC}"
        fi
    done
    
    echo -e "\n${CYAN}PASO 1: Creando IP virtual${NC}"
    if ! crear_ip_virtual "$virtual_ip" "$INTERFACE"; then
        echo -e "${RED}ERROR CRÍTICO: No se pudo crear la IP virtual. Abortando.${NC}"
        return 1
    fi
    
    echo -e "\n${CYAN}PASO 2: Configurando zona DNS${NC}"
    CONF="/etc/bind/named.conf.local"
    FILE="/var/cache/bind/db.$dominio"
    
    mkdir -p /var/cache/bind
    
    if [ -f "$CONF" ] && grep -q "$dominio" "$CONF" 2>/dev/null; then
        echo -e "${YELLOW}La zona ya existe.${NC}"
        read -p "¿Recrear? (s/n): " rec
        if [ "$rec" != "s" ]; then return; fi
        sed -i "/zone \"$dominio\" {/,/};/d" "$CONF"
    fi
    
    if [ ! -f "$CONF" ]; then
        touch "$CONF"
    fi
    
    cat >> "$CONF" <<EOF

zone "$dominio" {
    type master;
    file "$FILE";
};
EOF
    
    cat > "$FILE" <<EOF
; Archivo de zona para $dominio
; IP virtual creada: $virtual_ip
\$TTL 604800
@ IN SOA ns1.$dominio. admin.$dominio. (
    $(date +%Y%m%d)01   ; Serial
    604800              ; Refresh
    86400               ; Retry
    2419200             ; Expire
    604800 )            ; Negative Cache TTL

; Servidores de nombres
@ IN NS ns1.$dominio.
@ IN NS ns2.$dominio.

; Servidores DNS
ns1 IN A $SERVER_IP
ns2 IN A $SERVER_IP

; Registros del dominio
@ IN A $virtual_ip
www IN CNAME @
mail IN A $virtual_ip
ftp IN A $virtual_ip

; Registro MX
@ IN MX 10 mail.$dominio.
EOF
    
    chown bind:bind "$FILE" 2>/dev/null || chmod 644 "$FILE"
    
    echo -e "\n${CYAN}PASO 3: Verificando configuración DNS${NC}"
    if command -v named-checkconf >/dev/null 2>&1; then
        named-checkconf "$CONF"
    fi
    
    if command -v named-checkzone >/dev/null 2>&1; then
        named-checkzone "$dominio" "$FILE"
    fi
    
    echo -e "\n${CYAN}PASO 4: Reiniciando servicio DNS${NC}"
    reiniciar_servicio_dns
    
    echo -e "\n${GREEN}✅ CONFIGURACIÓN COMPLETADA EXITOSAMENTE${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
    echo -e "  Dominio:        ${GREEN}$dominio${NC}"
    echo -e "  IP Virtual:     ${GREEN}$virtual_ip${NC}"
    echo -e "  Servidor DNS:   ${GREEN}$SERVER_IP${NC}"
    echo -e "  Interfaz:       ${GREEN}$INTERFACE${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
}

eliminar_zona() {
    echo -e "\n${YELLOW}--- ELIMINAR ZONA DNS ---${NC}"
    CONF="/etc/bind/named.conf.local"
    
    if [ -f "$CONF" ]; then
        echo "Zonas actuales:"
        grep "zone" "$CONF" | cut -d'"' -f2
    else
        echo "No hay archivo de configuración."
        return
    fi
    
    read -p "Nombre EXACTO de la zona a borrar: " zona_del
    [ -z "$zona_del" ] && return
    
    if grep -q "$zona_del" "$CONF"; then
        archivo="/var/cache/bind/db.$zona_del"
        if [ -f "$archivo" ]; then
            virtual_ip=$(grep -E "^@\s+IN\s+A" "$archivo" | awk '{print $4}')
            if [ -n "$virtual_ip" ]; then
                echo -e "${CYAN}Eliminando IP virtual asociada: $virtual_ip${NC}"
                eliminar_ip_virtual "$virtual_ip" "$INTERFACE"
            fi
        fi
        
        cp "$CONF" "$CONF.bak"
        sed -i "/zone \"$zona_del\" {/,/};/d" "$CONF"
        rm -f "$archivo"
        
        reiniciar_servicio_dns
        echo -e "${GREEN}Zona eliminada.${NC}"
    else
        echo -e "${RED}Zona no encontrada.${NC}"
    fi
}

listar_zonas() {
    echo -e "\n${CYAN}--- DOMINIOS CONFIGURADOS ---${NC}"
    if [ -f "/etc/bind/named.conf.local" ] && grep -q "zone" "/etc/bind/named.conf.local"; then
        while IFS= read -r line; do
            if [[ "$line" =~ zone\ \"([^\"]+)\" ]]; then
                dominio="${BASH_REMATCH[1]}"
                archivo="/var/cache/bind/db.$dominio"
                if [ -f "$archivo" ]; then
                    ip_virtual=$(grep -E "^@\s+IN\s+A" "$archivo" | awk '{print $4}')
                    echo "  - $dominio → $ip_virtual"
                else
                    echo "  - $dominio"
                fi
            fi
        done < "/etc/bind/named.conf.local"
    else
        echo "No hay zonas configuradas."
    fi
}