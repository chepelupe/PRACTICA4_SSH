#!/bin/bash
# ==============================================================================
# FUNCIONES SSH - VERSION CORREGIDA (ACTIVA ETH2)
# ==============================================================================

source ./funciones_compartidas.sh

verificar_instalacion_ssh() {
    echo ""
    echo "--- verificando ssh ---"
    
    if ! command -v sshd >/dev/null 2>&1; then
        echo "[x] openssh server no instalado"
        return 1
    fi
    
    echo "[ok] openssh server instalado"
    
    if service ssh status | grep -q "running"; then
        echo "[ok] servicio ssh activo"
    else
        echo "[x] servicio ssh inactivo"
    fi
    
    echo ""
    echo "estado de eth2:"
    ip link show eth2 2>/dev/null | grep -q "UP" && echo "[ok] eth2 activa" || echo "[x] eth2 inactiva"
    ip addr show eth2 2>/dev/null | grep inet || echo "  eth2 sin ip"
}

activar_eth2() {
    echo "--- activando eth2 ---"
    
    # Verificar que eth2 existe
    if ! ip link show eth2 > /dev/null 2>&1; then
        echo "error: eth2 no existe"
        echo "verifica en virtualbox que tengas 3 adaptadores"
        return 1
    fi
    
    # Activar la interfaz
    echo "activando eth2..."
    ip link set eth2 up
    sleep 2
    
    # Verificar que quedo activa
    if ip link show eth2 | grep -q "UP"; then
        echo "[ok] eth2 activada"
    else
        echo "[error] no se pudo activar eth2"
        return 1
    fi
    
    return 0
}

configurar_ssh_eth2() {
    echo ""
    echo "--- configurando ssh en eth2 ---"
    
    # PASO 1: Activar eth2
    activar_eth2 || return 1
    
    # PASO 2: Asignar IP
    echo "asignando ip 192.168.56.10 a eth2..."
    ip addr flush dev eth2 2>/dev/null
    ip addr add 192.168.56.10/24 dev eth2
    
    # Verificar IP
    if ip addr show eth2 | grep -q "192.168.56.10"; then
        echo "[ok] ip asignada correctamente"
    else
        echo "[error] no se pudo asignar la ip"
        return 1
    fi
    
    # PASO 3: Instalar SSH si es necesario
    if ! command -v sshd >/dev/null 2>&1; then
        echo "instalando openssh-server..."
        apt-get update
        apt-get install -y openssh-server
    fi
    
    # PASO 4: Configurar SSH
    echo "configurando sshd..."
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup 2>/dev/null
    
    # Configuración básica
    cat > /etc/ssh/sshd_config <<EOF
Port 22
ListenAddress 0.0.0.0
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
PermitRootLogin yes
PasswordAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF
    
    # PASO 5: Reiniciar SSH
    echo "reiniciando ssh..."
    service ssh restart
    sleep 3
    
    # PASO 6: Configuración permanente en interfaces
    if ! grep -q "iface eth2" /etc/network/interfaces; then
        echo "agregando configuracion permanente..."
        cat >> /etc/network/interfaces <<EOF

auto eth2
iface eth2 inet static
    address 192.168.56.10
    netmask 255.255.255.0
    up ip link set eth2 up
EOF
    fi
    
    # PASO 7: Verificación final
    echo ""
    echo "--- verificacion final ---"
    echo "estado de eth2:"
    ip link show eth2 | grep "UP" && echo "  interfaz: ACTIVA" || echo "  interfaz: INACTIVA"
    ip addr show eth2 | grep inet || echo "  sin ip"
    
    echo ""
    echo "estado de ssh:"
    service ssh status | grep -q "running" && echo "  ssh: ACTIVO" || echo "  ssh: INACTIVO"
    netstat -tlnp 2>/dev/null | grep :22 && echo "  ssh: escuchando en puerto 22"
    
    echo ""
    echo "================================================"
    echo "ssh configurado en eth2"
    echo "usuario: $(whoami)"
    echo "ip: 192.168.56.10"
    echo "================================================"
    echo ""
    echo "prueba desde windows:"
    echo "  ssh $(whoami)@192.168.56.10"
    echo ""
    echo "si no funciona, verifica manualmente:"
    echo "  ip link set eth2 up"
    echo "  ip addr add 192.168.56.10/24 dev eth2"
    echo "================================================"
}

submenu_ssh() {
    while true; do
        clear
        echo ""
        echo "========================================"
        echo "   gestion de ssh                       "
        echo "========================================"
        echo "1) verificar ssh"
        echo "2) activar eth2 manualmente"
        echo "3) configurar ssh en eth2"
        echo "4) volver"
        echo "========================================"
        
        read -p "seleccione opcion: " subopc
        case $subopc in
            1) verificar_instalacion_ssh; read -p "presione enter..." ;;
            2) activar_eth2; read -p "presione enter..." ;;
            3) configurar_ssh_eth2; read -p "presione enter..." ;;
            4) return ;;
            *) echo "opcion invalida"; sleep 1 ;;
        esac
    done
}