#!/usr/bin/env bash
#===============================================================================
#  AWX OFFLINE INSTALLER — FASE 2: INSTALACIÓN (Servidor SIN internet)
#===============================================================================
#  Este script instala AWX 24.6.1 de forma completamente offline usando
#  el bundle preparado con 01-prepare-bundle.sh.
#
#  Uso:  sudo bash 02-install-awx.sh [opciones]
#
#  Opciones:
#    --cpus N        CPUs para Minikube (default: auto-detecta, mínimo 2)
#    --memory NNg    RAM para Minikube (default: auto-calcula)
#    --disk NNg      Disco para Minikube (default: 40g)
#    --skip-docker   No instalar Docker (si ya está instalado)
#    --help          Mostrar ayuda
#
#  Requisitos:
#    - Rocky Linux 9.x / RHEL 9.x / AlmaLinux 9.x
#    - Bundle descomprimido en el directorio actual
#    - Ejecutar como root
#===============================================================================

set -euo pipefail

# ─── Colores y formato ───────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

CHECKMARK="${GREEN}✔${NC}"
CROSS="${RED}✘${NC}"
ARROW="${CYAN}➜${NC}"
WARN="${YELLOW}⚠${NC}"
SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

# ─── Funciones de logging ────────────────────────────────────────────────────
banner() {
    clear
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}                                                              ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}     ${BOLD}AWX OFFLINE INSTALLER${NC}                                    ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}     Ansible AWX ${AWX_VERSION:-24.6.1} + Minikube + Kubernetes             ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}                                                              ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log_step() {
    echo ""
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC} ${ARROW} ${BOLD}$1${NC}"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────────┘${NC}"
}

log_info()    { echo -e "  ${ARROW} $1"; }
log_success() { echo -e "  ${CHECKMARK} $1"; }
log_warn()    { echo -e "  ${WARN} $1"; }
log_error()   { echo -e "  ${CROSS} ${RED}$1${NC}"; }

log_cmd() {
    echo -e "  ${DIM}\$ $1${NC}"
}

fail() {
    log_error "$1"
    echo ""
    echo -e "  ${RED}La instalación ha fallado. Revise el error anterior.${NC}"
    echo -e "  ${DIM}Log disponible en: ${INSTALL_LOG}${NC}"
    exit 1
}

# ─── Parseo de argumentos ────────────────────────────────────────────────────
MK_CPUS=""
MK_MEMORY=""
MK_DISK="40g"
SKIP_DOCKER=false

show_help() {
    echo "Uso: sudo bash 02-install-awx.sh [opciones]"
    echo ""
    echo "Opciones:"
    echo "  --cpus N        CPUs para Minikube (default: auto)"
    echo "  --memory NNg    RAM para Minikube (default: auto)"
    echo "  --disk NNg      Disco para Minikube (default: 40g)"
    echo "  --skip-docker   Omitir instalación de Docker"
    echo "  --help          Mostrar esta ayuda"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --cpus)    MK_CPUS="$2"; shift 2 ;;
        --memory)  MK_MEMORY="$2"; shift 2 ;;
        --disk)    MK_DISK="$2"; shift 2 ;;
        --skip-docker) SKIP_DOCKER=true; shift ;;
        --help)    show_help ;;
        *)         log_error "Opción desconocida: $1"; show_help ;;
    esac
done

# ─── Variables de control ────────────────────────────────────────────────────
INSTALL_LOG="/var/log/awx-offline-install.log"
START_TIME=$(date +%s)
TOTAL_STEPS=9
CURRENT_STEP=0

next_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    log_step "PASO ${CURRENT_STEP}/${TOTAL_STEPS} — $1"
}

# ─── Detectar directorio del bundle ──────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Buscar el bundle: puede estar en el directorio actual, padre, o junto al script
if [[ -f "./versions.env" ]]; then
    BUNDLE_DIR="$(pwd)"
elif [[ -f "${SCRIPT_DIR}/../versions.env" ]]; then
    BUNDLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
elif [[ -f "${SCRIPT_DIR}/versions.env" ]]; then
    BUNDLE_DIR="${SCRIPT_DIR}"
else
    # Buscar si hay un directorio awx-offline-bundle cerca
    for candidate in ./awx-offline-bundle ../awx-offline-bundle /root/awx-offline-bundle; do
        if [[ -f "${candidate}/versions.env" ]]; then
            BUNDLE_DIR="$(cd "${candidate}" && pwd)"
            break
        fi
    done
fi

if [[ -z "${BUNDLE_DIR:-}" ]] || [[ ! -f "${BUNDLE_DIR}/versions.env" ]]; then
    echo -e "${CROSS} ${RED}No se encontró el bundle de AWX offline.${NC}"
    echo ""
    echo "  Asegúrese de:"
    echo "  1. Haber descomprimido awx-offline-bundle.tar.gz"
    echo "  2. Ejecutar este script desde el directorio del bundle"
    echo "     o desde awx-offline-bundle/scripts/"
    echo ""
    echo "  Ejemplo:"
    echo "    cd /root/awx-offline-bundle"
    echo "    sudo bash scripts/02-install-awx.sh"
    exit 1
fi

# Cargar versiones
source "${BUNDLE_DIR}/versions.env"

# ─── INICIO ──────────────────────────────────────────────────────────────────
banner

echo -e "  Bundle:    ${BOLD}${BUNDLE_DIR}${NC}"
echo -e "  AWX:       ${BOLD}${AWX_VERSION}${NC}"
echo -e "  Operator:  ${BOLD}${AWX_OPERATOR_VERSION}${NC}"
echo -e "  K8s:       ${BOLD}${K8S_VERSION}${NC}"
echo ""

# Redirigir toda la salida detallada al log
exec > >(tee -a "${INSTALL_LOG}") 2>&1

# ═══════════════════════════════════════════════════════════════════════════════
#  PASO 1: Limpiar instalaciones previas
# ═══════════════════════════════════════════════════════════════════════════════
next_step "Limpiar instalaciones previas (si existen)"

CLEANUP_DONE=false

# Verificar si hay un Minikube previo corriendo
if command -v minikube &>/dev/null && minikube status &>/dev/null 2>&1; then
    log_warn "Se detectó un cluster Minikube existente"

    # Verificar si hay AWX desplegado
    if kubectl get namespace awx &>/dev/null 2>&1; then
        log_info "Eliminando namespace 'awx' y todos sus recursos..."
        kubectl delete namespace awx --timeout=120s 2>/dev/null || true
        log_success "Namespace 'awx' eliminado"
    fi

    log_info "Deteniendo y eliminando cluster Minikube..."
    minikube delete 2>/dev/null || true
    log_success "Cluster Minikube eliminado"
    CLEANUP_DONE=true
elif command -v minikube &>/dev/null; then
    # Minikube existe pero no está corriendo — limpiar de todas formas
    log_info "Limpiando residuos de Minikube anterior..."
    minikube delete 2>/dev/null || true
    CLEANUP_DONE=true
fi

# Limpiar servicios systemd previos
if [[ -f /etc/systemd/system/awx-portforward.service ]]; then
    log_info "Deteniendo servicio awx-portforward anterior..."
    systemctl stop awx-portforward 2>/dev/null || true
    systemctl disable awx-portforward 2>/dev/null || true
    rm -f /etc/systemd/system/awx-portforward.service
    CLEANUP_DONE=true
fi

if [[ -f /etc/systemd/system/minikube.service ]]; then
    log_info "Eliminando servicio minikube anterior..."
    systemctl stop minikube 2>/dev/null || true
    systemctl disable minikube 2>/dev/null || true
    rm -f /etc/systemd/system/minikube.service
    CLEANUP_DONE=true
fi

if [[ "${CLEANUP_DONE}" == true ]]; then
    systemctl daemon-reload 2>/dev/null || true
    log_success "Limpieza completada"
else
    log_success "No se detectaron instalaciones previas — ambiente limpio"
fi

# Limpiar directorio de kubeconfig
rm -rf ~/.kube/config 2>/dev/null || true

# ═══════════════════════════════════════════════════════════════════════════════
#  PASO 2: Verificar requisitos
# ═══════════════════════════════════════════════════════════════════════════════
next_step "Verificar requisitos del sistema"

# Root check
if [[ $EUID -ne 0 ]]; then
    fail "Este script debe ejecutarse como root o con sudo"
fi
log_success "Ejecutando como root"

# OS check
if [[ -f /etc/redhat-release ]]; then
    OS_RELEASE=$(cat /etc/redhat-release)
    log_success "Sistema operativo: ${OS_RELEASE}"
else
    log_warn "No se detectó un sistema RHEL/Rocky/Alma. Continuando de todas formas..."
fi

# CPU
TOTAL_CPUS=$(nproc)
if [[ -z "${MK_CPUS}" ]]; then
    # Reservar 1 CPU para el host, mínimo 2 para Minikube
    MK_CPUS=$(( TOTAL_CPUS > 2 ? TOTAL_CPUS - 1 : 2 ))
fi
log_success "CPUs totales: ${TOTAL_CPUS} → Minikube usará: ${MK_CPUS}"

# RAM
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
TOTAL_RAM_GB=$(( TOTAL_RAM_MB / 1024 ))
if [[ -z "${MK_MEMORY}" ]]; then
    # Dejar 2GB para el host, mínimo 4g para Minikube
    MK_MEMORY_MB=$(( TOTAL_RAM_MB - 2048 ))
    [[ $MK_MEMORY_MB -lt 4096 ]] && MK_MEMORY_MB=4096
    MK_MEMORY="${MK_MEMORY_MB}m"
fi
log_success "RAM total: ${TOTAL_RAM_GB}GB → Minikube usará: ${MK_MEMORY}"

if [[ $TOTAL_RAM_GB -lt 6 ]]; then
    log_warn "RAM baja (${TOTAL_RAM_GB}GB). Mínimo recomendado: 8GB. La instalación podría ser inestable."
fi

# Disk
DISK_AVAIL_GB=$(df -BG / | tail -1 | awk '{print $4}' | tr -d 'G')
log_success "Disco disponible en /: ${DISK_AVAIL_GB}GB"
if [[ $DISK_AVAIL_GB -lt 30 ]]; then
    log_warn "Poco espacio en disco. Se recomiendan al menos 40GB libres."
fi

# Bundle files check
log_info "Verificando contenido del bundle..."
for required in binaries/minikube binaries/kubectl images/awx-${AWX_VERSION}.tar \
                images/awx-operator-${AWX_OPERATOR_VERSION}.tar \
                images/awx-ee-${AWX_VERSION}.tar images/postgres-${POSTGRES_VERSION}.tar \
                images/redis-${REDIS_VERSION}.tar images/kicbase-${KICBASE_VERSION}.tar \
                manifests/kustomization.yaml manifests/awx-instance.yaml; do
    if [[ ! -f "${BUNDLE_DIR}/${required}" ]]; then
        fail "Archivo faltante en el bundle: ${required}"
    fi
done
log_success "Bundle verificado — todos los archivos presentes"

# ═══════════════════════════════════════════════════════════════════════════════
#  PASO 2: Configurar sistema operativo
# ═══════════════════════════════════════════════════════════════════════════════
next_step "Configurar sistema operativo"

# SELinux
SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Disabled")
if [[ "${SELINUX_STATUS}" == "Enforcing" ]]; then
    log_info "Cambiando SELinux a permissive..."
    setenforce 0
    sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config 2>/dev/null || true
    log_success "SELinux → permissive"
else
    log_success "SELinux ya está en: ${SELINUX_STATUS}"
fi

# Firewalld
if systemctl is-active --quiet firewalld 2>/dev/null; then
    log_info "Deteniendo firewalld..."
    systemctl stop firewalld
    systemctl disable firewalld
    log_success "Firewalld detenido y deshabilitado"
else
    log_success "Firewalld no está activo"
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  PASO 3: Instalar Docker CE
# ═══════════════════════════════════════════════════════════════════════════════
next_step "Instalar Docker CE"

if [[ "${SKIP_DOCKER}" == true ]]; then
    log_info "Omitiendo instalación de Docker (--skip-docker)"
    if ! command -v docker &>/dev/null; then
        fail "Docker no está instalado. No use --skip-docker si Docker no está presente."
    fi
    log_success "Docker existente: $(docker --version | head -1)"
else
    # Eliminar conflictos
    log_info "Eliminando paquetes conflictivos..."
    dnf remove -y podman buildah containers-common 2>/dev/null || true

    if [[ -d "${BUNDLE_DIR}/rpms" ]] && ls "${BUNDLE_DIR}"/rpms/*.rpm &>/dev/null; then
        log_info "Instalando Docker CE desde RPMs locales..."
        dnf localinstall -y "${BUNDLE_DIR}"/rpms/*.rpm 2>&1 | tail -3
        log_success "Docker CE instalado desde RPMs"
    elif command -v docker &>/dev/null; then
        log_warn "No se encontraron RPMs pero Docker ya existe. Usando Docker existente."
    else
        fail "No se encontraron RPMs de Docker en ${BUNDLE_DIR}/rpms/ y Docker no está instalado."
    fi

    # Habilitar e iniciar
    systemctl enable --now docker
    log_success "Docker habilitado e iniciado"
fi

# Verificar
docker info &>/dev/null || fail "Docker no responde correctamente"
log_success "Docker funcionando: $(docker --version | head -1)"

# ═══════════════════════════════════════════════════════════════════════════════
#  PASO 4: Instalar Minikube y kubectl
# ═══════════════════════════════════════════════════════════════════════════════
next_step "Instalar Minikube y kubectl"

log_info "Instalando Minikube..."
install -o root -g root -m 0755 "${BUNDLE_DIR}/binaries/minikube" /usr/local/bin/minikube
log_success "Minikube: $(minikube version --short 2>/dev/null || echo 'instalado')"

log_info "Instalando kubectl..."
install -o root -g root -m 0755 "${BUNDLE_DIR}/binaries/kubectl" /usr/local/bin/kubectl
log_success "kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>&1 | head -1)"

# ═══════════════════════════════════════════════════════════════════════════════
#  PASO 5: Iniciar Minikube
# ═══════════════════════════════════════════════════════════════════════════════
next_step "Iniciar cluster de Minikube (offline)"

# Cargar imagen base en Docker del host
log_info "Cargando imagen base de Minikube en Docker..."
docker load -i "${BUNDLE_DIR}/images/kicbase-${KICBASE_VERSION}.tar" 2>&1 | tail -1
log_success "Imagen kicbase cargada"

# Pre-cargar imágenes K8s en Docker
log_info "Pre-cargando imágenes de Kubernetes..."
for img_file in "${BUNDLE_DIR}"/images/kube-*.tar \
                "${BUNDLE_DIR}/images/pause-${PAUSE_VERSION}.tar" \
                "${BUNDLE_DIR}/images/coredns-${COREDNS_VERSION}.tar" \
                "${BUNDLE_DIR}/images/etcd-${ETCD_VERSION}.tar" \
                "${BUNDLE_DIR}/images/storage-provisioner-${STORAGE_PROVISIONER_VERSION}.tar"; do
    if [[ -f "$img_file" ]]; then
        fname=$(basename "$img_file")
        log_info "  ${DIM}${fname}${NC}"
        docker load -i "$img_file" 2>&1 | tail -1
    fi
done
log_success "Imágenes de Kubernetes cargadas"

# Limpiar cluster anterior si existe
if minikube status &>/dev/null; then
    log_warn "Minikube existente detectado. Eliminando..."
    minikube delete 2>/dev/null || true
fi

# Iniciar
log_info "Iniciando Minikube..."
log_cmd "minikube start --driver=docker --cpus=${MK_CPUS} --memory=${MK_MEMORY} --disk-size=${MK_DISK} ..."
echo ""

minikube start \
    --driver=docker \
    --cpus="${MK_CPUS}" \
    --memory="${MK_MEMORY}" \
    --disk-size="${MK_DISK}" \
    --install-addons=false \
    --cache-images=false \
    --force \
    --base-image="gcr.io/k8s-minikube/kicbase:${KICBASE_VERSION}" \
    --kubernetes-version="${K8S_VERSION}" \
    2>&1 | while read -r line; do echo "  ${line}"; done

echo ""

# Verificar
if kubectl get nodes 2>/dev/null | grep -q "Ready"; then
    log_success "Cluster Minikube iniciado y nodo en estado Ready"
else
    fail "El nodo de Minikube no está en estado Ready. Revise: minikube status"
fi

# Crear StorageClass "standard" si no existe (Minikube no siempre lo crea automáticamente)
if ! kubectl get sc standard &>/dev/null; then
    log_info "Creando StorageClass 'standard' para Minikube..."
    kubectl apply -f - <<SCEOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: k8s.io/minikube-hostpath
reclaimPolicy: Delete
volumeBindingMode: Immediate
SCEOF
    log_success "StorageClass 'standard' creado"
else
    log_success "StorageClass 'standard' ya existe"
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  PASO 6: Cargar imágenes AWX en Minikube
# ═══════════════════════════════════════════════════════════════════════════════
next_step "Cargar imágenes de AWX en Minikube"

AWX_IMAGES=(
    "awx-operator-${AWX_OPERATOR_VERSION}.tar"
    "awx-${AWX_VERSION}.tar"
    "awx-ee-${AWX_VERSION}.tar"
    "postgres-${POSTGRES_VERSION}.tar"
    "redis-${REDIS_VERSION}.tar"
)

for img_file in "${AWX_IMAGES[@]}"; do
    log_info "Cargando: ${BOLD}${img_file}${NC}"
    minikube image load "${BUNDLE_DIR}/images/${img_file}" 2>&1 | tail -1
    log_success "${img_file}"
done

# Cargar kube-rbac-proxy si existe en el bundle (sidecar del Operator)
if [[ -f "${BUNDLE_DIR}/images/kube-rbac-proxy-v0.15.0.tar" ]]; then
    log_info "Cargando: ${BOLD}kube-rbac-proxy-v0.15.0.tar${NC}"
    minikube image load "${BUNDLE_DIR}/images/kube-rbac-proxy-v0.15.0.tar" 2>&1 | tail -1
    log_success "kube-rbac-proxy-v0.15.0.tar"
else
    log_warn "kube-rbac-proxy no encontrado en el bundle (Operator funcionará con 1/2 — no es crítico)"
fi

echo ""
log_info "Verificando imágenes en Minikube..."
minikube image ls 2>/dev/null | grep -E 'awx|postgres|redis' | while read -r img; do
    echo -e "    ${GREEN}✔${NC} ${img}"
done
log_success "Todas las imágenes cargadas"

# ═══════════════════════════════════════════════════════════════════════════════
#  PASO 7: Desplegar AWX Operator
# ═══════════════════════════════════════════════════════════════════════════════
next_step "Desplegar AWX Operator y AWX"

# Crear namespace
log_info "Creando namespace 'awx'..."
kubectl create namespace awx 2>/dev/null || log_warn "Namespace 'awx' ya existe"

# Desplegar Operator
log_info "Aplicando AWX Operator con Kustomize..."
kubectl apply -k "${BUNDLE_DIR}/manifests/" 2>&1 | while read -r line; do
    echo -e "    ${DIM}${line}${NC}"
done

# Esperar a que el Operator esté listo
log_info "Esperando que el AWX Operator esté listo..."
TIMEOUT=180
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
    READY=$(kubectl get pods -n awx -l control-plane=controller-manager \
            --no-headers 2>/dev/null | awk '{print $2}' | head -1)
    if [[ "${READY}" == "2/2" ]]; then
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    printf "\r  ${ARROW} Esperando Operator... (${ELAPSED}s / ${TIMEOUT}s) Estado: ${READY:-Pending}  "
done
echo ""

if [[ $ELAPSED -ge $TIMEOUT ]]; then
    log_warn "Timeout esperando al Operator. Continuando de todas formas..."
    log_warn "Verifique con: kubectl get pods -n awx"
else
    log_success "AWX Operator corriendo (${ELAPSED}s)"
fi

# Desplegar AWX
log_info "Aplicando Custom Resource de AWX..."
kubectl apply -f "${BUNDLE_DIR}/manifests/awx-instance.yaml" 2>&1 | while read -r line; do
    echo -e "    ${DIM}${line}${NC}"
done

# ═══════════════════════════════════════════════════════════════════════════════
#  PASO 8: Esperar y verificar despliegue
# ═══════════════════════════════════════════════════════════════════════════════
next_step "Esperando despliegue completo de AWX (esto toma 5-15 minutos)"

AWX_TIMEOUT=900
AWX_ELAPSED=0
ALL_READY=false

while [[ $AWX_ELAPSED -lt $AWX_TIMEOUT ]]; do
    # Contar pods esperados
    TOTAL_PODS=$(kubectl get pods -n awx --no-headers 2>/dev/null | wc -l)
    RUNNING_PODS=$(kubectl get pods -n awx --no-headers 2>/dev/null | grep -c "Running" || true)
    
    # Verificar pods específicos de AWX
    WEB_READY=$(kubectl get pods -n awx -l app.kubernetes.io/name=awx-web \
                --no-headers 2>/dev/null | awk '{print $2}' | head -1)
    TASK_READY=$(kubectl get pods -n awx -l app.kubernetes.io/name=awx-task \
                 --no-headers 2>/dev/null | awk '{print $2}' | head -1)
    PG_READY=$(kubectl get pods -n awx -l app.kubernetes.io/name=awx-postgres \
               --no-headers 2>/dev/null | grep -c "1/1" 2>/dev/null || true)

    printf "\r  ${ARROW} Pods: %s/%s Running | Web: %s | Task: %s | PG: %s | (%ds)       " \
           "${RUNNING_PODS}" "${TOTAL_PODS}" \
           "${WEB_READY:-Pending}" "${TASK_READY:-Pending}" \
           "${PG_READY:-0}/1" "${AWX_ELAPSED}"

    # Verificar si todo está listo
    if [[ "${WEB_READY}" == "3/3" ]] && [[ "${TASK_READY}" == "4/4" ]] && [[ "${PG_READY}" -ge 1 ]]; then
        ALL_READY=true
        break
    fi

    sleep 10
    AWX_ELAPSED=$((AWX_ELAPSED + 10))
done
echo ""
echo ""

if [[ "${ALL_READY}" == true ]]; then
    log_success "¡AWX desplegado exitosamente! (${AWX_ELAPSED}s)"
else
    log_warn "Timeout esperando AWX (${AWX_TIMEOUT}s). Puede que necesite más tiempo."
    log_warn "Monitoree con: kubectl get pods -n awx -w"
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  Crear servicios systemd
# ═══════════════════════════════════════════════════════════════════════════════
log_info "Creando servicios systemd para persistencia..."

cat > /etc/systemd/system/minikube.service << 'SVCEOF'
[Unit]
Description=Minikube Cluster
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/minikube start --force
ExecStop=/usr/local/bin/minikube stop
User=root

[Install]
WantedBy=multi-user.target
SVCEOF

cat > /etc/systemd/system/awx-portforward.service << 'SVCEOF'
[Unit]
Description=AWX Port Forward
After=minikube.service
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStartPre=/usr/local/bin/kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=awx-web -n awx --timeout=300s
ExecStart=/usr/local/bin/kubectl port-forward svc/awx-service 8080:80 -n awx --address 0.0.0.0
Restart=always
RestartSec=15
User=root

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable minikube 2>/dev/null
systemctl enable awx-portforward 2>/dev/null
systemctl start awx-portforward 2>/dev/null || true

log_success "Servicios systemd creados y habilitados"

# ═══════════════════════════════════════════════════════════════════════════════
#  RESUMEN FINAL
# ═══════════════════════════════════════════════════════════════════════════════
END_TIME=$(date +%s)
ELAPSED_TOTAL=$(( END_TIME - START_TIME ))
MINUTES=$(( ELAPSED_TOTAL / 60 ))
SECONDS_R=$(( ELAPSED_TOTAL % 60 ))

# Obtener datos de acceso
MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "<no disponible>")
NODEPORT="30080"
AWX_PASSWORD=""
if kubectl get secret awx-admin-password -n awx &>/dev/null; then
    AWX_PASSWORD=$(kubectl get secret awx-admin-password -n awx \
                   -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode 2>/dev/null || echo "")
fi

SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "<IP del servidor>")

echo ""
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}                                                                      ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}     ${BOLD}${CHECKMARK}  INSTALACIÓN DE AWX COMPLETADA${NC}                                ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                                      ${GREEN}║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}                                                                      ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${BOLD}DATOS DE ACCESO${NC}                                                    ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ─────────────────────────────────────────────────────────────────    ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                                      ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}URL (NodePort):${NC}    http://${MINIKUBE_IP}:${NODEPORT}               ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}URL (Forward):${NC}     http://${SERVER_IP}:8080                        ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                                      ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}Usuario:${NC}           ${BOLD}admin${NC}                                             ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}Contraseña:${NC}        ${BOLD}${AWX_PASSWORD:-<pendiente - revise más abajo>}${NC}   ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                                      ${GREEN}║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}                                                                      ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${BOLD}VERSIONES INSTALADAS${NC}                                               ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ─────────────────────────────────────────────────────────────────    ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  AWX:              ${AWX_VERSION}                                              ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  AWX Operator:     ${AWX_OPERATOR_VERSION}                                             ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Kubernetes:       ${K8S_VERSION}                                            ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  PostgreSQL:       ${POSTGRES_VERSION}                                                ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Redis:            ${REDIS_VERSION}                                                 ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                                      ${GREEN}║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}                                                                      ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${BOLD}ESTADO DE PODS${NC}                                                     ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ─────────────────────────────────────────────────────────────────    ${GREEN}║${NC}"

kubectl get pods -n awx --no-headers 2>/dev/null | while read -r line; do
    POD_NAME=$(echo "$line" | awk '{print $1}')
    POD_STATUS=$(echo "$line" | awk '{print $3}')
    POD_READY=$(echo "$line" | awk '{print $2}')
    if [[ "${POD_STATUS}" == "Running" ]]; then
        ICON="${GREEN}✔${NC}"
    else
        ICON="${YELLOW}⏳${NC}"
    fi
    printf "${GREEN}║${NC}  ${ICON}  %-45s %s (%s)   ${GREEN}║${NC}\n" \
           "${POD_NAME}" "${POD_STATUS}" "${POD_READY}"
done

echo -e "${GREEN}║${NC}                                                                      ${GREEN}║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}                                                                      ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${BOLD}RECURSOS DEL SISTEMA${NC}                                               ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ─────────────────────────────────────────────────────────────────    ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  CPUs Minikube:    ${MK_CPUS}                                                 ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  RAM Minikube:     ${MK_MEMORY}                                             ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Disco Minikube:   ${MK_DISK}                                               ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Tiempo total:     ${MINUTES}m ${SECONDS_R}s                                           ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                                      ${GREEN}║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}                                                                      ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${BOLD}COMANDOS ÚTILES${NC}                                                    ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ─────────────────────────────────────────────────────────────────    ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Ver pods:          kubectl get pods -n awx                            ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Ver logs:          kubectl logs -f deploy/awx-web -n awx -c awx-web   ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Obtener password:  kubectl get secret awx-admin-password -n awx \\     ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                       -o jsonpath='{.data.password}' | base64 -d       ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Estado Minikube:   minikube status                                    ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Reiniciar AWX:     kubectl rollout restart deploy/awx-web -n awx      ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                                      ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [[ -z "${AWX_PASSWORD}" ]]; then
    echo -e "  ${WARN} La contraseña aún no está disponible. AWX puede estar iniciándose."
    echo -e "  ${ARROW} Obténgala cuando los pods estén Ready con:"
    echo -e "    ${DIM}kubectl get secret awx-admin-password -n awx -o jsonpath='{.data.password}' | base64 -d ; echo${NC}"
    echo ""
fi

echo -e "  ${DIM}Log completo: ${INSTALL_LOG}${NC}"
echo ""
