# Guía Completa de Instalación Offline — AWX 24.6.1

> Esta guía detalla cada fase del proceso de instalación. Si solo necesita los pasos rápidos,
> vea el [README principal](../README.md).

---

## Tabla de Contenido

1. [Contexto](#1-contexto)
2. [Arquitectura](#2-arquitectura)
3. [Requisitos del Servidor](#3-requisitos-del-servidor)
4. [Fase 1: Preparar el Bundle (máquina con internet)](#4-fase-1-preparar-el-bundle)
5. [Fase 2: Transferir al Servidor](#5-fase-2-transferir-al-servidor)
6. [Fase 3: Instalar Componentes Base](#6-fase-3-instalar-componentes-base)
7. [Fase 4: Iniciar Minikube Offline](#7-fase-4-iniciar-minikube-offline)
8. [Fase 5: Cargar Imágenes en Minikube](#8-fase-5-cargar-imágenes-en-minikube)
9. [Fase 6: Desplegar AWX Operator](#9-fase-6-desplegar-awx-operator)
10. [Fase 7: Desplegar AWX](#10-fase-7-desplegar-awx)
11. [Fase 8: Verificación y Acceso](#11-fase-8-verificación-y-acceso)
12. [Post-Instalación](#12-post-instalación)
13. [Resumen de Imágenes y Versiones](#13-resumen-de-imágenes-y-versiones)

---

## 1. Contexto

La última versión estable de AWX es la **24.6.1**, lanzada el 2 de julio de 2024 junto con el AWX Operator **v2.19.1**. Desde esa fecha, el proyecto AWX ha pausado nuevos releases mientras realiza una refactorización a gran escala. Esto significa que **24.6.1 es la versión más reciente disponible**.

Esta guía cubre la instalación completa de AWX en un entorno **totalmente desconectado de internet** (air-gapped), usando **Minikube** como distribución de Kubernetes de un solo nodo.

El proceso se divide en dos fases: preparar todo en una máquina con internet y luego instalar en el servidor destino sin conexión.

> ℹ️ **El script `01-prepare-bundle.sh` automatiza la Fase 1 completa.** El script `02-install-awx.sh` automatiza las Fases 3 a 8. Esta guía explica qué hace cada script por dentro, para que pueda ejecutar los pasos manualmente si lo necesita o para resolver problemas.

---

## 2. Arquitectura

| Capa | Componente | Versión | Función |
|------|-----------|---------|---------|
| SO Base | Rocky Linux / RHEL | 9.x | Sistema operativo host |
| Container Runtime | Docker CE | 27.x | Motor de contenedores |
| Kubernetes | Minikube | latest | Cluster K8s single-node |
| Orquestador | AWX Operator | 2.19.1 | Gestiona ciclo de vida AWX |
| Aplicación | AWX | 24.6.1 | Interfaz web + API + Motor |
| Base de Datos | PostgreSQL | 15 | Almacenamiento de datos AWX |
| Cache | Redis | 7 | Cache y broker de mensajes |
| Exec Environment | AWX EE | 24.6.1 | Entorno de ejecución de playbooks |

**Flujo:** Docker CE → Minikube (cluster K8s) → AWX Operator → AWX (web + task + postgres + redis + EE)

---

## 3. Requisitos del Servidor

| Recurso | Mínimo | Recomendado |
|---------|--------|-------------|
| CPU | 4 vCPUs | 4+ vCPUs |
| RAM | 8 GB | 16 GB |
| Disco libre | 40 GB | 60+ GB |
| SO | Rocky Linux 9.x / RHEL 9.x / AlmaLinux 9.x | x86_64 |

### Verificaciones previas

```bash
free -h          # Verificar RAM
```

```bash
df -h /          # Verificar disco
```

```bash
cat /etc/redhat-release    # Verificar SO
```

```bash
# SELinux en permissive
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
```

```bash
# Firewalld deshabilitado (o abrir puertos 80, 443, 6443, 8443, 30000-32767)
sudo systemctl stop firewalld
sudo systemctl disable firewalld
```

> ⚠️ En producción no se recomienda deshabilitar SELinux ni firewalld. Configure reglas específicas si la política lo requiere.

---

## 4. Fase 1: Preparar el Bundle

> **Automatizado por:** `scripts/01-prepare-bundle.sh`  
> **Ejecutar en:** cualquier máquina con Docker e internet (cualquier SO)

### 4.1 Estructura que crea el script

```
awx-offline-bundle/
├── versions.env           # Versiones de todos los componentes
├── binaries/              # minikube, kubectl
├── images/                # ~14 archivos .tar de imágenes Docker
├── rpms/                  # RPMs de Docker CE para Rocky/RHEL 9
├── manifests/             # Kustomize + AWX Custom Resource + Operator source
└── scripts/               # Copia de 02-install-awx.sh
```

### 4.2 Lo que descarga

**Binarios:**

```bash
# Minikube
curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
```

```bash
# kubectl
KUBECTL_VER=$(curl -sL https://dl.k8s.io/release/stable.txt)
curl -Lo kubectl "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/amd64/kubectl"
```

**RPMs de Docker CE** (descargados via curl desde el repo oficial, funciona desde cualquier SO):

```bash
# Se descargan directamente de:
# https://download.docker.com/linux/centos/9/x86_64/stable/Packages/
# Paquetes: containerd.io, docker-ce, docker-ce-cli, docker-buildx-plugin, docker-compose-plugin
```

**Imágenes de contenedor:**

| Imagen | Tag | Propósito |
|--------|-----|-----------|
| `quay.io/ansible/awx-operator` | 2.19.1 | Operador AWX |
| `quay.io/ansible/awx` | 24.6.1 | Aplicación AWX |
| `quay.io/ansible/awx-ee` | 24.6.1 | Execution Environment |
| `docker.io/library/postgres` | 15 | PostgreSQL |
| `docker.io/library/redis` | 7 | Redis |
| `gcr.io/k8s-minikube/kicbase` | v0.0.45 | Imagen base Minikube |
| `registry.k8s.io/kube-apiserver` | v1.30.0 | K8s API Server |
| `registry.k8s.io/kube-controller-manager` | v1.30.0 | K8s Controller |
| `registry.k8s.io/kube-scheduler` | v1.30.0 | K8s Scheduler |
| `registry.k8s.io/kube-proxy` | v1.30.0 | K8s Proxy |
| `registry.k8s.io/pause` | 3.9 | K8s pause container |
| `registry.k8s.io/coredns/coredns` | v1.11.1 | DNS interno |
| `registry.k8s.io/etcd` | 3.5.12-0 | etcd |
| `registry.k8s.io/storage-provisioner` | v5 | Storage provisioner |

Cada imagen se descarga con `docker pull` y se exporta con `docker save` a un archivo `.tar`.

### 4.3 Empaquetado final

Todo se comprime en `awx-offline-bundle.tar.gz` (~5-6 GB).

---

## 5. Fase 2: Transferir al Servidor

```bash
# Opción A: SCP
scp awx-offline-bundle.tar.gz usuario@<IP_SERVIDOR>:/root/
```

```bash
# Opción B: USB
cp awx-offline-bundle.tar.gz /media/usb/
```

```bash
# En el servidor destino
cd /root
tar xzf awx-offline-bundle.tar.gz
cd awx-offline-bundle
```

> ℹ️ A partir de aquí todos los comandos se ejecutan en el **servidor air-gapped**.

---

## 6. Fase 3: Instalar Componentes Base

> **Automatizado por:** `scripts/02-install-awx.sh` (pasos 1-4)

### 6.1 Docker CE

```bash
# Eliminar conflictos
dnf remove -y podman buildah containers-common 2>/dev/null
```

```bash
# Instalar desde RPMs locales
cd /root/awx-offline-bundle/rpms
dnf localinstall -y *.rpm
```

```bash
# Habilitar
systemctl enable --now docker
```

```bash
# Verificar
docker version
```

### 6.2 Minikube

```bash
install -o root -g root -m 0755 binaries/minikube /usr/local/bin/minikube
```

```bash
minikube version
```

### 6.3 kubectl

```bash
install -o root -g root -m 0755 binaries/kubectl /usr/local/bin/kubectl
```

```bash
kubectl version --client
```

---

## 7. Fase 4: Iniciar Minikube Offline

> **Automatizado por:** `scripts/02-install-awx.sh` (paso 5)

### 7.1 Cargar imagen base en Docker

```bash
docker load -i images/kicbase-v0.0.45.tar
```

### 7.2 Pre-cargar imágenes de Kubernetes

```bash
for img in images/kube-*.tar images/pause-*.tar images/coredns-*.tar \
           images/etcd-*.tar images/storage-provisioner-*.tar; do
  echo "Cargando: $img"
  docker load -i "$img"
done
```

### 7.3 Iniciar el cluster

Ajuste `--cpus` y `--memory` según los recursos de su servidor:

```bash
minikube start \
  --driver=docker \
  --cpus=4 \
  --memory=6g \
  --disk-size=40g \
  --install-addons=false \
  --cache-images=false \
  --base-image='gcr.io/k8s-minikube/kicbase:v0.0.45' \
  --kubernetes-version=v1.30.0
```

```bash
# Verificar
minikube status
kubectl get nodes
```

> ✅ Si el nodo aparece como **Ready**, el cluster funciona.

---

## 8. Fase 5: Cargar Imágenes en Minikube

> **Automatizado por:** `scripts/02-install-awx.sh` (paso 6)

Las imágenes AWX se cargan **dentro** de Minikube (no en el Docker del host):

```bash
minikube image load images/awx-operator-2.19.1.tar
```

```bash
minikube image load images/awx-24.6.1.tar
```

```bash
minikube image load images/awx-ee-24.6.1.tar
```

```bash
minikube image load images/postgres-15.tar
```

```bash
minikube image load images/redis-7.tar
```

```bash
# Verificar
minikube image ls | grep -E 'awx|postgres|redis'
```

---

## 9. Fase 6: Desplegar AWX Operator

> **Automatizado por:** `scripts/02-install-awx.sh` (paso 7)

```bash
kubectl create namespace awx
```

```bash
kubectl apply -k manifests/
```

```bash
# Esperar a que esté Running (Ctrl+C para salir)
kubectl get pods -n awx -w
```

Resultado esperado:

```
awx-operator-controller-manager-xxxxx   2/2     Running   0   2m
```

---

## 10. Fase 7: Desplegar AWX

> **Automatizado por:** `scripts/02-install-awx.sh` (paso 7, continuación)

```bash
kubectl apply -f manifests/awx-instance.yaml
```

```bash
# Monitorear (5-15 minutos)
kubectl get pods -n awx -w
```

Estado final esperado:

```
awx-operator-controller-manager-xxxxx   2/2     Running   10m
awx-postgres-15-0                       1/1     Running   8m
awx-task-xxxxx                          4/4     Running   6m
awx-web-xxxxx                           3/3     Running   6m
```

---

## 11. Fase 8: Verificación y Acceso

> **Automatizado por:** `scripts/02-install-awx.sh` (paso 8 + resumen final)

### Obtener contraseña

```bash
kubectl get secret awx-admin-password -n awx \
  -o jsonpath='{.data.password}' | base64 --decode ; echo
```

### Acceso por NodePort

```bash
echo "http://$(minikube ip):30080"
```

### Acceso por Port-Forward

```bash
kubectl port-forward svc/awx-service 8080:80 -n awx --address 0.0.0.0 &
# Acceder en http://<IP_SERVIDOR>:8080
```

### Acceso por SSH Tunnel (desde workstation remota)

```bash
# En tu workstation
ssh -L 8080:localhost:8080 usuario@<IP_SERVIDOR>
# Abrir http://localhost:8080
```

**Credenciales:** usuario `admin`, contraseña obtenida del paso anterior.

---

## 12. Post-Instalación

### Servicios systemd (creados automáticamente por el script)

El instalador crea dos servicios para que AWX sobreviva reinicios:

```bash
# Minikube se inicia con el sistema
systemctl status minikube

# Port-forward se mantiene activo
systemctl status awx-portforward
```

### Execution Environment Offline

En AWX, verificar en **Administration → Execution Environments** que existe el EE con imagen `quay.io/ansible/awx-ee:24.6.1` y pull policy **IfNotPresent** o **Never**.

---

## 13. Resumen de Imágenes y Versiones

| Componente | Imagen | Tamaño Aprox. |
|-----------|--------|---------------|
| AWX Operator | `quay.io/ansible/awx-operator:2.19.1` | ~250 MB |
| AWX App | `quay.io/ansible/awx:24.6.1` | ~1.5 GB |
| AWX EE | `quay.io/ansible/awx-ee:24.6.1` | ~1.8 GB |
| PostgreSQL | `docker.io/library/postgres:15` | ~380 MB |
| Redis | `docker.io/library/redis:7` | ~140 MB |
| Minikube Base | `gcr.io/k8s-minikube/kicbase:v0.0.45` | ~1.2 GB |
| K8s Components | `registry.k8s.io/kube-*:v1.30.0` | ~300 MB total |
| CoreDNS | `registry.k8s.io/coredns/coredns:v1.11.1` | ~50 MB |
| etcd | `registry.k8s.io/etcd:3.5.12-0` | ~150 MB |

**Tamaño total del bundle: ~5-6 GB**

---

> **Nota:** Las versiones de imágenes K8s pueden variar según la versión de Minikube. Verifique con `minikube start --dry-run` en la máquina con internet antes de preparar el bundle.
