#!/bin/bash

# Script para configurar SSH sin contraseña entre máquinas
# Argumentos:
#   $1: Tipo de máquina (controller/worker)
#   $2: Lista de IPs de las demás máquinas (separadas por comas)

TIPO_MAQUINA=$1
IPS_OTRAS_MAQUINAS=$2


mkdir -p /home/vagrant/.ssh
chmod 700 /home/vagrant/.ssh

# Convertir lista de IPs a array
IFS=',' read -ra IPS <<< "$IPS_OTRAS_MAQUINAS"

# Recopilar claves SSH de todos los hosts y añadirlas a known_hosts
echo "=== Recopilando claves SSH de los hosts ==="
for ip in "${IPS[@]}"; do
    echo "Intentando obtener clave de $ip..."
    # Se intenta recopilar 3 veces por host
    for i in {1..3}; do
        if ssh-keyscan -H "$ip" >> /home/vagrant/.ssh/known_hosts 2>/dev/null; then
            echo "Clave obtenida de $ip"
            break
        fi
        if [ $i -eq 3 ]; then
            echo "Host $ip no disponible después de 3 intentos, continuando con el siguiente host..."
        fi
        sleep 2
    done
done

# Eliminar duplicados en known_hosts
if [ -f /home/vagrant/.ssh/known_hosts ]; then
    sort -u /home/vagrant/.ssh/known_hosts -o /home/vagrant/.ssh/known_hosts
fi

chmod 600 /home/vagrant/.ssh/known_hosts
chown -R vagrant:vagrant /home/vagrant/.ssh

if [ "$TIPO_MAQUINA" == "controller" ]; then
    echo "Configurando máquina CONTROLADORA"
    
    # Generar par de claves SSH si no existe
    if [ ! -f /home/vagrant/.ssh/id_rsa ]; then
        sudo -u vagrant ssh-keygen -t rsa -b 4096 -f /home/vagrant/.ssh/id_rsa -N "" -C "vagrant@controller"
        echo "Par de claves SSH generado"
    fi
    
    # Añadir la clave pública al authorized_keys local
    cat /home/vagrant/.ssh/id_rsa.pub >> /home/vagrant/.ssh/authorized_keys
    chmod 600 /home/vagrant/.ssh/authorized_keys
    chown vagrant:vagrant /home/vagrant/.ssh/authorized_keys
    
    # Guardar la clave pública en la carpta compartida
    cp /home/vagrant/.ssh/id_rsa.pub /vagrant/controller_key.pub
    echo "Clave pública exportada a /vagrant/controller_key.pub"
    
else
    echo "Configurando máquina WORKER"
    
    # Esperar a que la clave pública del controlador esté disponible
    echo "Esperando clave pública del controlador..."
    while [ ! -f /vagrant/controller_key.pub ]; do
        sleep 2
    done
    
    # Crear authorized_keys si no existe (preservando el que ya existe)
    touch /home/vagrant/.ssh/authorized_keys
    
    # Verificar que la clave del controlador no esté ya añadida
    CONTROLLER_KEY=$(cat /vagrant/controller_key.pub)
    if ! grep -qF "$CONTROLLER_KEY" /home/vagrant/.ssh/authorized_keys; then
        # Añadir la clave pública del controlador al authorized_keys
        cat /vagrant/controller_key.pub >> /home/vagrant/.ssh/authorized_keys
        echo "Clave pública del controlador añadida a authorized_keys"
    else
        echo "Clave pública del controlador ya estaba en authorized_keys"
    fi
    
    chmod 600 /home/vagrant/.ssh/authorized_keys
    chown vagrant:vagrant /home/vagrant/.ssh/authorized_keys
    
fi