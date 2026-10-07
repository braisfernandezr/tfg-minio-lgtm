# -*- mode: ruby -*-
# vi: set ft=ruby :

require 'yaml'

# Cargar configuración del sistema operativo
config_file = File.join(File.dirname(__FILE__), 'config.yml')
if File.exist?(config_file)
  user_config = YAML.load_file(config_file)
  OS_CHOICE = user_config['sistema_operativo'].downcase
else
  puts "ERROR: No se encontró el archivo config.yml"
  exit 1
end

# Mapeo de sistemas operativos a boxes de Vagrant
OS_BOXES = {
  'debian' => {
    'box' => 'debian/bookworm64',
    'version' => '12.20250126.1'
  },
  'rocky' => {
    'box' => 'rreye/rocky-9',
    'version' => '20260213'
  },
  'alma' => {
    'box' => 'almalinux/9',
    'version' => '9.7.20260111'
  }
}

# Validar que el SO seleccionado es válido
unless OS_BOXES.key?(OS_CHOICE)
  puts "ERROR: Sistema operativo '#{OS_CHOICE}' no válido"
  puts "Opciones disponibles: #{OS_BOXES.keys.join(', ')}"
  exit 1
end

SELECTED_BOX = OS_BOXES[OS_CHOICE]['box']
SELECTED_VERSION = OS_BOXES[OS_CHOICE]['version']

MACHINES = {
  'minio-1' => {
    'ip' => '192.168.56.10',
    'memory' => 3072,
    'cpus' => 2,
    'role' => 'controller',
    'description' => 'Controladora con Ansible y MinIO'
  },
  'minio-2' => {
    'ip' => '192.168.56.11',
    'memory' => 3072,
    'cpus' => 2,
    'role' => 'worker',
    'description' => 'Worker con MinIO'
  },
  'app-monitor-1' => {
    'ip' => '192.168.56.12',
    'memory' => 1024,
    'cpus' => 2,
    'role' => 'worker',
    'description' => 'Aplicaciones y monitorización (Grafana Alloy)'
  },
  'app-monitor-2' => {
    'ip' => '192.168.56.13',
    'memory' => 1024,
    'cpus' => 2,
    'role' => 'worker',
    'description' => 'Aplicaciones y monitorización (Grafana Alloy)'
  }
}

# Recopilar todas las IPs para pasarlas al script de SSH
ALL_IPS = MACHINES.values.map { |m| m['ip'] }.join(',')

Vagrant.configure("2") do |config|
  
  # Configuración común para todas las máquinas
  config.vm.box = SELECTED_BOX
  config.vm.box_version = SELECTED_VERSION
  
  config.vm.boot_timeout = 600

  # Carpeta sincronizada con permisos restringidos. Por defecto VirtualBox
  # monta /vagrant world-writable (0777) y Ansible se niega a cargar
  # ansible.cfg desde un directorio escribible por cualquiera, lo que
  # obligaba a copiar ansible/ a /home/vagrant/ansible en la controladora.
  # Con dmode/fmode restringidos los playbooks se ejecutan directamente
  # desde /vagrant/ansible, sin copia intermedia.
  config.vm.synced_folder ".", "/vagrant",
    owner: "vagrant", group: "vagrant",
    mount_options: ["dmode=0755", "fmode=0644"]

  
  # Configurar cada máquina
  MACHINES.each do |name, machine_config|
    config.vm.define name do |machine|
      
      # Configuración de red
      machine.vm.network "private_network", ip: machine_config['ip']
      machine.vm.hostname = name
      
      # Configuración de recursos
      machine.vm.provider "virtualbox" do |vb|
        vb.name = name
        vb.memory = machine_config['memory']
        vb.cpus = machine_config['cpus']
        
        # Añadir disco virtual adicional para MinIO (dinámico, 10GB)
        if machine_config['role'] == 'controller' || name == 'minio-2'
          disk_file = "minio-disk-#{name}.vdi"
          unless File.exist?(disk_file)
            vb.customize ['createmedium', 'disk', 
                          '--filename', disk_file, 
                          '--size', 10 * 1024,
                          '--variant', 'Standard']
          end
          vb.customize ['storageattach', :id, 
                        '--storagectl', 'SATA Controller', 
                        '--port', 1, 
                        '--device', 0, 
                        '--type', 'hdd', 
                        '--medium', disk_file]
        end
      end
      
      # Provisioning: actualizar sistema e instalar dependencias básicas
      machine.vm.provision "shell", inline: <<-SHELL
        echo "=========================================="
        echo "Provisionando: #{name}"
        echo "Rol: #{machine_config['role']}"
        echo "Descripción: #{machine_config['description']}"
        echo "=========================================="
        
        # Actualizar repositorios e instalar paquetes básicos
        if command -v apt-get &> /dev/null; then
          # Debian/Ubuntu
          export DEBIAN_FRONTEND=noninteractive
          apt-get update
          apt-get install -y vim curl wget net-tools openssh-server
        elif command -v dnf &> /dev/null; then
          # Rocky/Alma Linux
          dnf install -y vim curl wget net-tools openssh-server
        fi
        
        # Asegurar que SSH está habilitado y funcionando
        if command -v apt-get &> /dev/null; then
          systemctl enable ssh
          systemctl start ssh
        else
          systemctl enable sshd
          systemctl start sshd
        fi
        
        echo "Paquetes básicos instalados"
      SHELL
      
      # Configuración específica para la controladora
      if machine_config['role'] == 'controller'
        machine.vm.provision "shell", inline: <<-SHELL
          
          echo "=========================================="
          echo "Instalando Ansible"
          echo "=========================================="
          
          # Instalar ansible
          if command -v apt-get &> /dev/null; then
            # Debian/Ubuntu
            export DEBIAN_FRONTEND=noninteractive
            apt-get update
            apt-get install -y software-properties-common python3-pip
            apt-get install -y ansible
            
          elif command -v dnf &> /dev/null; then
            # Rocky/Alma Linux
            dnf install -y epel-release
            dnf install -y ansible python3-pip
          fi
          
          ansible --version

          # Los playbooks se ejecutan directamente desde /vagrant/ansible
          # (la carpeta sincronizada ya no es world-writable, ver
          # config.vm.synced_folder). Se elimina la copia antigua si quedó
          # de un aprovisionamiento anterior, para que nadie la edite/use
          # por error.
          rm -rf /home/vagrant/ansible


        SHELL
      end
      
      # Mensaje final
      machine.vm.provision "shell", inline: <<-SHELL
        echo ""
        echo "=========================================="
        echo "  Máquina #{name} configurada"
        echo "  IP: #{machine_config['ip']}"
        echo "  Rol: #{machine_config['role']}"
        echo "=========================================="
        echo ""
      SHELL
      
    end
  end
  
  # Configuración SSH sin contraseña (ejecutar manualmente)
  MACHINES.each do |name, machine_config|
    config.vm.define name do |machine|
      machine.vm.provision "ssh-config", type: "shell", run: "never",
        path: "setup_ssh.sh",
        args: [machine_config['role'], ALL_IPS]
    end
  end
  
  # Cada fase ejecuta site.yml (roles) con su tag correspondiente. Los
  # playbooks planos originales ya no forman parte del proyecto.
  config.vm.define "minio-1" do |machine|
    machine.vm.provision "docker", type: "shell", run: "never", inline: <<-SHELL
      echo ""
      echo "=========================================="
      echo "Instalando Docker en todas las máquinas..."
      echo "=========================================="
      cd /vagrant/ansible
      sudo -u vagrant ansible-playbook site.yml --tags docker
    SHELL
  end

  config.vm.define "minio-1" do |machine|
    machine.vm.provision "minio", type: "shell", run: "never", inline: <<-SHELL
      echo ""
      echo "=========================================="
      echo "Instalando MinIO OSS en minio-1 y minio-2..."
      echo "=========================================="
      cd /vagrant/ansible
      sudo -u vagrant ansible-playbook site.yml --tags minio
    SHELL
  end

  config.vm.define "minio-1" do |machine|
    machine.vm.provision "grafana-alloy", type: "shell", run: "never", inline: <<-SHELL
      echo ""
      echo "=========================================="
      echo "Instalando Grafana Alloy en app-monitor-1 y app-monitor-2..."
      echo "=========================================="
      cd /vagrant/ansible
      sudo -u vagrant ansible-playbook site.yml --tags grafana_alloy
    SHELL
  end

  config.vm.define "minio-1" do |machine|
    machine.vm.provision "lgtm-stack", type: "shell", run: "never", inline: <<-SHELL
      echo ""
      echo "=========================================="
      echo "Instalando stack LGTM en minio-1..."
      echo "=========================================="
      cd /vagrant/ansible
      sudo -u vagrant ansible-playbook site.yml --tags lgtm_stack
    SHELL
  end
  
end