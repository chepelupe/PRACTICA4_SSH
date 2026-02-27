#!/bin/bash
# ==============================================================================
# FUNCIONES SSH - Para Linux (Devuan)
# ==============================================================================

# Cargar funciones comunes si no están disponibles
if [ -z "$GREEN" ]; then
    source "$(dirname "$0")/comunes.sh"
fi

verificar_instalacion_ssh() {
    echo -e "\n${CYAN}--- VERIFICANDO SERVICIO SSH (DEVUAN) ---${NC}"
    
    if dpkg -s openssh-server >/dev/null 2>&1; then 
        echo -e "${GREEN}[OK] OpenSSH Server instalado${NC}"
    else 
        echo -e "${RED}[X] OpenSSH Server NO instalado${NC}"
    fi
    
    if systemctl is-active ssh >/dev/null 2>&1; then
        echo -e "${GREEN}[OK] Servicio SSH activo${NC}"
    else
        echo -e "${RED}[X] Servicio SSH inactivo${NC}"
    fi
    
    if systemctl is-enabled ssh >/dev/null 2>&1; then
        echo -e "${GREEN}[OK] SSH habilitado en el arranque${NC}"
    else
        echo -e "${RED}[X] SSH no está habilitado en el arranque${NC}"
    fi
    
    # Verificar puerto 22
    if ss -tlnp | grep -q ":22"; then
        echo -e "${GREEN}[OK] Puerto 22 escuchando${NC}"
    else
        echo -e "${RED}[X] Puerto 22 no está escuchando${NC}"
    fi
}

instalar_ssh_linux() {
    echo -e "\n${CYAN}--- INSTALANDO Y CONFIGURANDO SSH EN LINUX ---${NC}"
    echo -e "${YELLOW}¡IMPORTANTE! Después de esta instalación,${NC}"
    echo -e "${YELLOW}toda configuración posterior será vía SSH remota.${NC}"
    echo ""
    
    read -p "¿Continuar con la instalación de SSH? (s/n): " confirmar
    if [[ "$confirmar" != "s" ]]; then
        echo -e "${YELLOW}Instalación cancelada.${NC}"
        return
    fi
    
    # Instalar OpenSSH Server
    echo -e "${CYAN}Instalando openssh-server...${NC}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error en la instalación de SSH.${NC}"
        return 1
    fi
    
    # Hacer backup de la configuración original
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d)
    
    # Configurar SSH para mayor seguridad (opcional)
    echo -e "${CYAN}Configurando SSH...${NC}"
    
    # Permitir autenticación por contraseña (útil para primera conexión)
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
    
    # Habilitar login como root (opcional, con precaución)
    # sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
    
    # Configurar para que inicie automáticamente
    echo -e "${CYAN}Habilitando SSH en el arranque del sistema...${NC}"
    systemctl enable ssh
    
    # Iniciar servicio
    echo -e "${CYAN}Iniciando servicio SSH...${NC}"
    systemctl restart ssh
    
    # Verificar estado
    sleep 2
    if systemctl is-active ssh >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Servicio SSH iniciado correctamente${NC}"
    else
        echo -e "${RED}✗ Error al iniciar servicio SSH${NC}"
        systemctl status ssh --no-pager
        return 1
    fi
    
    # Configurar firewall para permitir SSH
    echo -e "${CYAN}Configurando firewall para SSH (puerto 22)...${NC}"
    if command -v iptables >/dev/null 2>&1; then
        iptables -A INPUT -p tcp --dport 22 -j ACCEPT
        iptables -A OUTPUT -p tcp --sport 22 -j ACCEPT
        echo -e "${GREEN}✓ Reglas iptables agregadas${NC}"
    fi
    
    # Obtener IP para conexión
    SERVER_IP=$(obtener_ip_actual)
    
    echo -e "\n${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ SSH CONFIGURADO CORRECTAMENTE${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "  IP del servidor: ${CYAN}$SERVER_IP${NC}"
    echo -e "  Puerto:          ${CYAN}22${NC}"
    echo -e "  Usuario:         ${CYAN}$(whoami)${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Para conectarte desde otro equipo:${NC}"
    echo -e "  ssh $(whoami)@$SERVER_IP"
    echo -e ""
    echo -e "${YELLOW}¡RECUERDA! Ahora debes continuar la configuración${NC}"
    echo -e "${YELLOW}desde una conexión SSH remota.${NC}"
    
    # Preguntar si quiere probar la conexión localmente
    read -p "¿Probar conexión SSH localmente? (s/n): " probar
    if [[ "$probar" == "s" ]]; then
        echo -e "${CYAN}Probando conexión SSH...${NC}"
        ssh -o ConnectTimeout=5 localhost "echo 'Conexión SSH exitosa'"
    fi
}

generar_instrucciones_windows() {
    echo -e "\n${CYAN}--- INSTRUCCIONES PARA CONFIGURAR SSH EN WINDOWS ---${NC}"
    echo -e "${YELLOW}Copia y ejecuta el siguiente script en PowerShell (como Administrador):${NC}"
    echo ""
    echo "=================================================="
    cat "$(dirname "$0")/../scripts_windows/configurar_ssh.ps1" 2>/dev/null || echo "Archivo de script Windows no encontrado"
    echo "=================================================="
    
    echo -e "\n${CYAN}O puedes ejecutar estos comandos manualmente:${NC}"
    echo ""
    echo "# 1. Instalar OpenSSH Server"
    echo "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0"
    echo ""
    echo "# 2. Iniciar y habilitar servicio"
    echo "Start-Service sshd"
    echo "Set-Service -Name sshd -StartupType 'Automatic'"
    echo ""
    echo "# 3. Configurar firewall"
    echo "New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22"
    
    read -p "Presiona Enter para continuar..."
}

configurar_par_claves() {
    echo -e "\n${CYAN}--- CONFIGURACIÓN DE PAR DE CLAVES SSH ---${NC}"
    
    SERVER_IP=$(obtener_ip_actual)
    
    echo -e "Para mejorar la seguridad, puedes configurar autenticación por claves."
    echo ""
    echo -e "${YELLOW}En tu cliente Linux/Mac, ejecuta:${NC}"
    echo "  ssh-keygen -t ed25519"
    echo "  ssh-copy-id $(whoami)@$SERVER_IP"
    echo ""
    echo -e "${YELLOW}En tu cliente Windows (PowerShell):${NC}"
    echo "  ssh-keygen -t ed25519"
    echo "  type \$env:USERPROFILE\.ssh\id_ed25519.pub | ssh $(whoami)@$SERVER_IP \"cat >> ~/.ssh/authorized_keys\""
    
    read -p "Presiona Enter para continuar..."
}

submenu_ssh() {
    while true; do
        clear
        echo -e "\n${CYAN}========================================${NC}"
        echo -e "${CYAN}   GESTIÓN DE SSH (ACCESO REMOTO)       ${NC}"
        echo -e "${CYAN}========================================${NC}"
        echo "1) Verificar estado de SSH"
        echo "2) Instalar y configurar SSH en Linux"
        echo "3) Ver instrucciones para Windows"
        echo "4) Configurar autenticación por claves"
        echo "5) Volver al Menú Principal"
        echo "========================================"
        
        read -p "Seleccione opción: " subopc
        case $subopc in
            1) verificar_instalacion_ssh; read -p "Enter..." ;;
            2) instalar_ssh_linux; read -p "Enter..." ;;
            3) generar_instrucciones_windows ;;
            4) configurar_par_claves; read -p "Enter..." ;;
            5) return ;;
            *) echo "Opción inválida"; sleep 1 ;;
        esac
    done
}