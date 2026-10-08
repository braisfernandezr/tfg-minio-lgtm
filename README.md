# TFG - Diseño y despliegue de una infraestructura de almacenamiento distribuido y observabilidad nativa de la nube mediante IaC (9.8 M.H.)

**Autor:** Brais Fernández Reyes
**Dirección:** Roberto Rey Expósito
**Institución:** Universidade da Coruña, Facultade de Informática

Trabajo de Fin de Grado: diseño y despliegue automatizado, mediante técnicas de Infrastructure as Code (Vagrant + Ansible), de un clúster de almacenamiento de objetos **MinIO** en modo distribuido junto a una pila de observabilidad nativa de la nube **LGTM** (Loki, Grafana, Tempo, Mimir) recolectada mediante **Grafana Alloy**. Incluye una aplicación de demostración (**TNS**, de Grafana Labs) que genera métricas, logs y trazas para validar todo el pipeline de extremo a extremo de forma experimental.

El entorno completo, formado por cuatro máquinas virtuales, se aprovisiona de forma automatizada y reproducible.

## Arquitectura

La arquitectura lógica se organiza en cuatro nodos agrupados en dos planos diferenciados, todos conectados a través de una red privada:

```text
┌────────────────────────────────────────────────────────────────────────┐
│                         Plano de aplicación                            │
│                                                                        │
│  ┌─────────────────────────┐          ┌─────────────────────────┐      │
│  │ app-monitor-1           │          │ app-monitor-2           │      │
│  │ 192.168.56.12           │          │ 192.168.56.13           │      │
│  │ - TNS (docker compose)  │          │ - TNS (docker compose)  │      │
│  │ - Grafana Alloy         │          │ - Grafana Alloy         │      │
│  └─────────────┬───────────┘          └────────────┬────────────┘      │
└────────────────┼───────────────────────────────────┼───────────────────┘
                 │                                   │
═════════════════▼═══════════════════════════════════▼════════════════════
                    Red privada: 192.168.56.0/24
═════════════════▲═══════════════════════════════════▲════════════════════
                 │                                   │
┌────────────────┼───────────────────────────────────┼───────────────────┐
│  ┌─────────────┴───────────┐          ┌────────────┴────────────┐      │
│  │ minio-1                 │          │ minio-2                 │      │
│  │ 192.168.56.10           │<-------->│ 192.168.56.11           │      │
│  │ - MinIO (distribuido)   │ clúster  │ - MinIO (distribuido)   │      │
│  │ - Stack LGTM (docker)   │  MinIO   │                         │      │
│  │ - Controlador Ansible   │          │                         │      │
│  └─────────────────────────┘          └─────────────────────────┘      │
│                                                                        │
│                  Plano de almacenamiento y observabilidad              │
└────────────────────────────────────────────────────────────────────────┘
```

| Máquina         | IP             | RAM   | vCPU | Rol         | Servicios                                   |
|-----------------|----------------|-------|------|-------------|----------------------------------------------|
| `minio-1`       | 192.168.56.10  | 3 GB  | 2    | Controlador | Ansible, MinIO, LGTM                         |
| `minio-2`       | 192.168.56.11  | 3 GB  | 2    | Worker      | MinIO                                        |
| `app-monitor-1` | 192.168.56.12  | 1 GB  | 2    | Worker      | App TNS, Grafana Alloy                       |
| `app-monitor-2` | 192.168.56.13  | 1 GB  | 2    | Worker      | App TNS, Grafana Alloy                       |

## Stack tecnológico

- **Vagrant + VirtualBox** — motor de virtualización local y aprovisionamiento inicial de las 4 VMs.
- **Ansible** — gestión de la configuración (agentless). Todo el código está organizado de manera mantenible en roles reutilizables (`docker`, `firewall`, `minio`, `grafana_alloy`, `lgtm_stack`).
- **MinIO** (Open Source) — almacenamiento de objetos compatible con API S3. Desplegado explícitamente como servicio nativo de `systemd` (y no en contenedor Docker) para que cumpla las condiciones de acceso directo al disco local y direccionamiento de red exigidos para formar el clúster distribuido.
- **Docker / Docker Compose** — orquestación de contenedores para el stack LGTM, Alloy y la aplicación de demostración TNS.
- **Grafana Alloy** — agente unificado de recolección de métricas, logs y trazas (integrando el exportador Node Exporter para el sistema operativo).
- **Stack LGTM** (en `minio-1`):
  - **Loki** — logs de sistema y Docker. Almacena mediante backend S3 en MinIO.
  - **Tempo** — trazas distribuidas. Recibe directamente las trazas Jaeger de TNS y usa backend S3 en MinIO.
  - **Mimir** — métricas. Recibe los datos vía protocolo de remote-write de Prometheus. Almacena en backend S3 en MinIO.
  - **Grafana** — capa unificada de visualización. Configurado mediante aprovisionamiento automático para permitir la correlación en la interfaz entre las distintas fuentes de datos (ej. navegar de trazas a logs utilizando el `traceID` común).
- **TNS app** — aplicación web de demostración instrumentada en origen que incluye una base de datos, una app y un generador de carga para testear la observabilidad end-to-end.

## Puesta en marcha rápida

1. Levantar las máquinas virtuales:

   ```bash
   vagrant up
   ```

   Esto crea las 4 VMs, configura las direcciones de red IP estáticas y, en `minio-1`, instala los paquetes de Ansible.

2. Configurar la comunicación SSH sin contraseña entre los distintos nodos:

   ```bash
   vagrant provision --provision-with ssh-config
   ```

3. Ejecutar el aprovisionamiento de la infraestructura con Ansible directamente desde la controladora (`minio-1`):

   ```bash
   vagrant ssh minio-1
   cd /vagrant/ansible && ansible-playbook site.yml
   ```

4. Levantar la aplicación TNS que genera la carga en **ambos** nodos de aplicación (`app-monitor-*`):

   ```bash
   vagrant ssh app-monitor-1
   cd /vagrant && docker compose up -d
   exit

   vagrant ssh app-monitor-2
   cd /vagrant && docker compose up -d
   ```

   Las trazas de protocolo Jaeger generadas en TNS se envían directamente al receptor Jaeger nativo de Tempo en `192.168.56.10:14268` sin hacer un paso intermedio a través de Alloy.

### Acceso a los servicios

| Servicio        | URL                              | Credenciales             |
|-----------------|-----------------------------------|---------------------------|
| MinIO Consola   | http://192.168.56.10:9001         | minioadmin / minioadmin123|
| Grafana         | http://192.168.56.10:3000         | admin / admin             |
| Alloy UI        | http://192.168.56.1{2,3}:12345    | -                         |

### Verificar el pipeline de telemetría y el almacenamiento en MinIO

Al desplegarse Loki y Mimir, los datos recientes se retienen de forma temporal en la memoria antes de transferirse al almacenamiento S3 del clúster de MinIO (flush por defecto de 2 horas). Para visualizar los datos alojados inmediatamente en MinIO puedes forzar los volcados llamando a sus API:

```bash
# Loki: sube a MinIO los chunks que tenga en memoria ahora mismo
curl -X POST http://192.168.56.10:3100/flush

# Mimir: cierra y sube el bloque TSDB actual
curl -X POST http://192.168.56.10:9009/ingester/flush
```

Y revisar los buckets que han sido automatizados durante el despliegue del almacenamiento `LGTM` en MinIO:

```bash
sudo -u vagrant mc ls local/loki-data --insecure
sudo -u vagrant mc ls local/mimir-blocks --insecure
```

En la interfaz de Grafana ya se encontrarán disponibles el panel *Node Exporter Full* de monitorización y el *Dashboard oficial del clúster de MinIO* (alimentado por las métricas de `Mimir`).

## Alcance, Seguridad y Credenciales

Al tratarse de un entorno de laboratorio diseñado con fines académicos, se han priorizado decisiones de diseño sobre el endurecimiento activo de las infraestructuras de seguridad. 
Esto se materializa en:
- El uso de credenciales por defecto en texto plano.
- La ausencia de comunicaciones cifradas por TLS entre componentes.
- La desactivación de todos los puertos del cortafuegos `firewalld` en lugar de aplicar normas selectivas de apertura.

## Licencia / Uso Académico

Este proyecto está publicado bajo la [Licencia MIT](LICENSE). Eres libre de utilizar, copiar, modificar y distribuir este código, con la única condición de incluir el aviso de derechos de autor y licencia original.

Proyecto desarrollado de forma independiente como Trabajo de Fin de Grado. MinIO se despliega en su edición **Community / bare-metal** sin necesidad de poseer licencias comerciales.
