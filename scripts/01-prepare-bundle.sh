#!/usr/bin/env bash
#===============================================================================
#  AWX OFFLINE INSTALLER — FASE 1: PREPARACIÓN (Máquina CON internet)
#===============================================================================
#  Este script descarga todos los binarios, imágenes de contenedor, RPMs
#  y manifiestos necesarios para instalar AWX 24.6.1 de forma offline.
#
#  Uso:  sudo bash 01-prepare-bundle.sh
#
#  Requisitos:
#    - Acceso a internet
#    - Docker instalado y corriendo (cualquier SO: Linux, Mac, WSL2)
#    - ~15 GB de espacio libre en disco
#    - Ejecutar como root o con sudo
#
#  NOTA: Este script puede ejecutarse desde CUALQUIER máquina con Docker
#        e internet. No necesita ser Rocky Linux. Los RPMs de Docker CE
#        para Rocky/RHEL 9 se descargan directamente del repositorio
#        oficial de Docker vía curl.
#===============================================================================

set -euo pipefail

# ─── Versiones ────────────────────────────────────────────────────────────────
AWX_VERSION="24.6.1"
AWX_OPERATOR_VERSION="2.19.1"
K8S_VERSION="v1.30.0"
# Minikube - VERSIÓN FIJA para garantizar compatibilidad con kicbase
MINIKUBE_VERSION="v1.34.0"
KICBASE_VERSION="v0.0.45"
POSTGRES_VERSION="15"
REDIS_VERSION="7"
COREDNS_VERSION="v1.11.1"
ETCD_VERSION="3.5.12-0"
PAUSE_VERSION="3.9"
STORAGE_PROVISIONER_VERSION="v5"

# Docker CE RPMs para RHEL/Rocky 9 x86_64
# Se descargan directo del repo de Docker — funciona desde cualquier SO
DOCKER_REPO_URL="https://download.docker.com/linux/centos/9/x86_64/stable/Packages"
# Las versiones se detectan automáticamente del repositorio (ver paso 3)

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

# ─── Funciones ───────────────────────────────────────────────────────────────
banner() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  ${BOLD}AWX ${AWX_VERSION} — Offline Bundle Preparation${NC}                    ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  AWX Operator ${AWX_OPERATOR_VERSION} | Minikube | Kubernetes ${K8S_VERSION}      ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}                                                              ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${DIM}Se puede ejecutar desde cualquier SO con Docker${NC}              ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log_step() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${ARROW} ${BOLD}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

log_info()    { echo -e "  ${ARROW} $1"; }
log_success() { echo -e "  ${CHECKMARK} $1"; }
log_warn()    { echo -e "  ${WARN} $1"; }
log_error()   { echo -e "  ${CROSS} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script debe ejecutarse como ${BOLD}root${NC} o con ${BOLD}sudo${NC}"
        exit 1
    fi
}

check_docker() {
    if ! command -v docker &>/dev/null; then
        log_error "Docker no está instalado."
        echo ""
        echo -e "  Este script necesita Docker para descargar las imágenes de contenedor."
        echo -e "  Instale Docker en esta máquina primero:"
        echo ""
        echo -e "    ${DIM}# Ubuntu/Debian:${NC}"
        echo -e "    ${DIM}curl -fsSL https://get.docker.com | sh${NC}"
        echo ""
        echo -e "    ${DIM}# RHEL/Rocky/Alma/CentOS:${NC}"
        echo -e "    ${DIM}dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo${NC}"
        echo -e "    ${DIM}dnf install -y docker-ce && systemctl start docker${NC}"
        echo ""
        echo -e "    ${DIM}# Mac:${NC}"
        echo -e "    ${DIM}brew install --cask docker   (o instalar Docker Desktop)${NC}"
        echo ""
        echo -e "    ${DIM}# Windows (WSL2):${NC}"
        echo -e "    ${DIM}Instalar Docker Desktop con integración WSL2${NC}"
        echo ""
        exit 1
    fi
    if ! docker info &>/dev/null; then
        log_error "Docker no está corriendo."
        echo ""
        echo -e "  Inícielo con:"
        echo -e "    ${DIM}sudo systemctl start docker${NC}   (Linux)"
        echo -e "    ${DIM}Abrir Docker Desktop${NC}          (Mac/Windows)"
        echo ""
        exit 1
    fi
    log_success "Docker detectado: $(docker --version | head -1)"
}

check_disk_space() {
    local available_gb
    available_gb=$(df -BG . | tail -1 | awk '{print $4}' | tr -d 'G')
    if [[ "$available_gb" -lt 15 ]]; then
        log_warn "Solo ${available_gb}GB disponibles. Se recomiendan al menos 15GB."
        read -rp "  ¿Desea continuar de todas formas? (s/N): " respuesta
        [[ "$respuesta" != "s" && "$respuesta" != "S" ]] && exit 1
    else
        log_success "Espacio en disco disponible: ${available_gb}GB"
    fi
}

pull_and_save() {
    local image="$1"
    local filename="$2"

    log_info "Descargando: ${BOLD}${image}${NC}"
    if docker pull "$image" 2>&1 | tail -1; then
        log_info "Exportando a: ${filename}"
        docker save "$image" -o "images/${filename}"
        log_success "OK — $(du -h "images/${filename}" | cut -f1)"
    else
        log_error "Falló la descarga de: ${image}"
        ERRORS=$((ERRORS + 1))
    fi
}

download_rpm() {
    local url="$1"
    local filename
    filename=$(basename "$url")

    log_info "  ${DIM}${filename}${NC}"
    if curl -sSLf -o "rpms/${filename}" "$url"; then
        log_success "  ${filename} — $(du -h "rpms/${filename}" | cut -f1)"
    else
        log_error "  Falló descarga: ${filename}"
        log_warn "  URL: ${url}"
        ERRORS=$((ERRORS + 1))
    fi
}

# ─── Variables de control ────────────────────────────────────────────────────
ERRORS=0
BUNDLE_DIR="awx-offline-bundle"
START_TIME=$(date +%s)

# ─── INICIO ──────────────────────────────────────────────────────────────────
banner
check_root
check_docker

log_step "PASO 1/7 — Verificar requisitos"

log_info "SO de esta máquina: ${BOLD}$(uname -s) $(uname -m)${NC}"
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    log_info "Distribución: ${BOLD}${PRETTY_NAME:-Desconocida}${NC}"
fi
log_info "El servidor DESTINO debe ser Rocky Linux 9.x / RHEL 9.x / AlmaLinux 9.x"
check_disk_space

# ─── PASO 2: Estructura ─────────────────────────────────────────────────────
log_step "PASO 2/7 — Crear estructura de directorios"

rm -rf "${BUNDLE_DIR}"
mkdir -p "${BUNDLE_DIR}"/{binaries,images,manifests,rpms,scripts}
cd "${BUNDLE_DIR}"

log_success "Estructura creada: $(pwd)"

# ─── PASO 3: RPMs de Docker CE ──────────────────────────────────────────────
log_step "PASO 3/7 — Descargar RPMs de Docker CE para Rocky/RHEL 9"

log_info "Detectando últimas versiones desde el repositorio oficial de Docker..."
log_info "Fuente: ${DIM}${DOCKER_REPO_URL}${NC}"
echo ""

# Obtener listado del repositorio y detectar la última versión de cada paquete
REPO_LISTING=$(curl -sSL "${DOCKER_REPO_URL}/")

find_latest_rpm() {
    local pkg_prefix="$1"
    # Buscar todos los RPMs que coincidan, extraer nombre, ordenar por versión, tomar el último
    echo "$REPO_LISTING" | grep -oP "${pkg_prefix}-[0-9][^\"]*.x86_64\.rpm" | sort -V | tail -1
}

RPMS_TO_DOWNLOAD=(
    "$(find_latest_rpm 'containerd.io')"
    "$(find_latest_rpm 'docker-ce-cli')"
    "$(find_latest_rpm 'docker-ce-rootless-extras')"
    "$(find_latest_rpm 'docker-ce')"
    "$(find_latest_rpm 'docker-buildx-plugin')"
    "$(find_latest_rpm 'docker-compose-plugin')"
)

for rpm_file in "${RPMS_TO_DOWNLOAD[@]}"; do
    if [[ -n "$rpm_file" ]]; then
        download_rpm "${DOCKER_REPO_URL}/${rpm_file}"
    fi
done

RPM_COUNT=$(ls rpms/*.rpm 2>/dev/null | wc -l)
if [[ $RPM_COUNT -eq 0 ]]; then
    log_error "No se pudieron descargar RPMs. Verifique la conexión a internet."
    ERRORS=$((ERRORS + 1))
else
    log_success "${RPM_COUNT} RPMs descargados para Rocky/RHEL 9 x86_64"
    log_info "Versiones detectadas:"
    ls rpms/*.rpm 2>/dev/null | while read -r f; do echo -e "    ${DIM}$(basename "$f")${NC}"; done
fi

# ─── PASO 4: Binarios ───────────────────────────────────────────────────────
log_step "PASO 4/7 — Descargar binarios (Minikube + kubectl)"

log_info "Descargando Minikube ${MINIKUBE_VERSION} (versión fija para compatibilidad offline)..."
curl -sSL -o binaries/minikube \
    "https://github.com/kubernetes/minikube/releases/download/${MINIKUBE_VERSION}/minikube-linux-amd64"
chmod +x binaries/minikube
log_success "Minikube ${MINIKUBE_VERSION} descargado — $(du -h binaries/minikube | cut -f1)"

log_info "Descargando kubectl..."
KUBECTL_VER=$(curl -sSL https://dl.k8s.io/release/stable.txt)
curl -sSL -o binaries/kubectl \
    "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/amd64/kubectl"
chmod +x binaries/kubectl
log_success "kubectl ${KUBECTL_VER} descargado — $(du -h binaries/kubectl | cut -f1)"

# ─── PASO 5: Imágenes de contenedor ─────────────────────────────────────────
log_step "PASO 5/7 — Descargar y exportar imágenes de contenedor"
echo -e "  ${WARN} ${YELLOW}Este es el paso más largo. Puede tomar 15-30 minutos.${NC}"
echo ""

# AWX images
log_info "${BOLD}--- Imágenes AWX ---${NC}"
pull_and_save "quay.io/ansible/awx-operator:${AWX_OPERATOR_VERSION}" \
              "awx-operator-${AWX_OPERATOR_VERSION}.tar"

pull_and_save "quay.io/ansible/awx:${AWX_VERSION}" \
              "awx-${AWX_VERSION}.tar"

pull_and_save "quay.io/ansible/awx-ee:${AWX_VERSION}" \
              "awx-ee-${AWX_VERSION}.tar"

# Database & cache
log_info "${BOLD}--- Base de datos y cache ---${NC}"
pull_and_save "docker.io/library/postgres:${POSTGRES_VERSION}" \
              "postgres-${POSTGRES_VERSION}.tar"

pull_and_save "docker.io/library/redis:${REDIS_VERSION}" \
              "redis-${REDIS_VERSION}.tar"

# Minikube base
log_info "${BOLD}--- Minikube ---${NC}"
pull_and_save "gcr.io/k8s-minikube/kicbase:${KICBASE_VERSION}" \
              "kicbase-${KICBASE_VERSION}.tar"

# Kubernetes system images
log_info "${BOLD}--- Kubernetes ${K8S_VERSION} ---${NC}"
for comp in kube-apiserver kube-controller-manager kube-scheduler kube-proxy; do
    pull_and_save "registry.k8s.io/${comp}:${K8S_VERSION}" \
                  "${comp}-${K8S_VERSION}.tar"
done

pull_and_save "registry.k8s.io/pause:${PAUSE_VERSION}" \
              "pause-${PAUSE_VERSION}.tar"

pull_and_save "registry.k8s.io/coredns/coredns:${COREDNS_VERSION}" \
              "coredns-${COREDNS_VERSION}.tar"

pull_and_save "registry.k8s.io/etcd:${ETCD_VERSION}" \
              "etcd-${ETCD_VERSION}.tar"

# storage-provisioner es una imagen de Minikube, no de registry.k8s.io
# Se intenta descargar pero no es crítico — Minikube la incluye internamente
log_info "Descargando: ${BOLD}gcr.io/k8s-minikube/storage-provisioner:${STORAGE_PROVISIONER_VERSION}${NC}"
if docker pull "gcr.io/k8s-minikube/storage-provisioner:${STORAGE_PROVISIONER_VERSION}" 2>&1 | tail -1; then
    docker save "gcr.io/k8s-minikube/storage-provisioner:${STORAGE_PROVISIONER_VERSION}" \
        -o "images/storage-provisioner-${STORAGE_PROVISIONER_VERSION}.tar"
    log_success "OK — $(du -h "images/storage-provisioner-${STORAGE_PROVISIONER_VERSION}.tar" | cut -f1)"
else
    log_warn "No se pudo descargar storage-provisioner (Minikube la incluye internamente, no es crítico)"
fi

# kube-rbac-proxy — sidecar del AWX Operator (sin esta imagen, el Operator queda en 1/2)
# La imagen original gcr.io/kubebuilder/kube-rbac-proxy fue removida de GCR.
# Se descarga de Docker Hub y se re-tagea en el servidor destino.
log_info "Descargando: ${BOLD}kubebuilder/kube-rbac-proxy:v0.15.0${NC}"
if docker pull "kubebuilder/kube-rbac-proxy:v0.15.0" 2>&1 | tail -1; then
    docker save "kubebuilder/kube-rbac-proxy:v0.15.0" \
        -o "images/kube-rbac-proxy-v0.15.0.tar"
    log_success "OK — $(du -h "images/kube-rbac-proxy-v0.15.0.tar" | cut -f1)"
else
    log_warn "No se pudo descargar kube-rbac-proxy (el Operator funciona sin él, no es crítico)"
fi

# ─── PASO 6: Manifiestos y configuración ─────────────────────────────────────
log_step "PASO 6/7 — Descargar AWX Operator y crear manifiestos"

log_info "Descargando AWX Operator ${AWX_OPERATOR_VERSION}..."
curl -sSL -o manifests/awx-operator-${AWX_OPERATOR_VERSION}.tar.gz \
    "https://github.com/ansible/awx-operator/archive/refs/tags/${AWX_OPERATOR_VERSION}.tar.gz"

cd manifests
tar xzf awx-operator-${AWX_OPERATOR_VERSION}.tar.gz
rm -f awx-operator-${AWX_OPERATOR_VERSION}.tar.gz
cd ..
log_success "AWX Operator extraído"

# Crear kustomization.yaml
log_info "Creando manifiestos de despliegue..."

cat > manifests/kustomization.yaml << KUSTOMEOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - awx-operator-${AWX_OPERATOR_VERSION}/config/default

images:
  - name: quay.io/ansible/awx-operator
    newTag: ${AWX_OPERATOR_VERSION}

namespace: awx
KUSTOMEOF

# Crear AWX Custom Resource
cat > manifests/awx-instance.yaml << AWXEOF
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx
  namespace: awx
spec:
  service_type: NodePort
  nodeport_port: 30080

  image: quay.io/ansible/awx
  image_version: "${AWX_VERSION}"
  image_pull_policy: IfNotPresent

  ee_images:
    - name: AWX EE (${AWX_VERSION})
      image: quay.io/ansible/awx-ee:${AWX_VERSION}
  control_plane_ee_image: quay.io/ansible/awx-ee:${AWX_VERSION}

  postgres_image: docker.io/library/postgres
  postgres_image_version: "${POSTGRES_VERSION}"
  postgres_storage_class: standard
  postgres_storage_requirements:
    requests:
      storage: 8Gi

  redis_image: docker.io/library/redis
  redis_image_version: "${REDIS_VERSION}"
AWXEOF

log_success "Manifiestos creados"

# Crear archivo de versiones (lo usa el script de instalación)
cat > versions.env << VEREOF
AWX_VERSION="${AWX_VERSION}"
AWX_OPERATOR_VERSION="${AWX_OPERATOR_VERSION}"
K8S_VERSION="${K8S_VERSION}"
MINIKUBE_VERSION="${MINIKUBE_VERSION}"
KICBASE_VERSION="${KICBASE_VERSION}"
POSTGRES_VERSION="${POSTGRES_VERSION}"
REDIS_VERSION="${REDIS_VERSION}"
COREDNS_VERSION="${COREDNS_VERSION}"
ETCD_VERSION="${ETCD_VERSION}"
PAUSE_VERSION="${PAUSE_VERSION}"
STORAGE_PROVISIONER_VERSION="${STORAGE_PROVISIONER_VERSION}"
VEREOF

log_success "Archivo de versiones creado"

# ─── PASO 7: Empaquetar ─────────────────────────────────────────────────────
log_step "PASO 7/7 — Empaquetar bundle final"

cd ..

# Copiar el script de instalación al bundle
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/02-install-awx.sh" ]]; then
    cp "${SCRIPT_DIR}/02-install-awx.sh" "${BUNDLE_DIR}/scripts/"
    log_success "Script de instalación incluido en el bundle"
else
    log_warn "No se encontró 02-install-awx.sh junto a este script."
    log_warn "Deberá copiarlo manualmente al servidor destino."
fi

log_info "Creando archivo comprimido (esto puede tomar unos minutos)..."
tar czf awx-offline-bundle.tar.gz "${BUNDLE_DIR}"/

BUNDLE_SIZE=$(du -h awx-offline-bundle.tar.gz | cut -f1)
log_success "Bundle creado: ${BOLD}awx-offline-bundle.tar.gz${NC} (${BUNDLE_SIZE})"

# ─── RESUMEN ─────────────────────────────────────────────────────────────────
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
MINUTES=$(( ELAPSED / 60 ))
SECONDS_R=$(( ELAPSED % 60 ))

IMAGE_COUNT=$(ls "${BUNDLE_DIR}"/images/*.tar 2>/dev/null | wc -l)
TOTAL_IMAGES_SIZE=$(du -sh "${BUNDLE_DIR}/images/" | cut -f1)

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}                                                              ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${BOLD}${CHECKMARK} BUNDLE COMPLETADO EXITOSAMENTE${NC}                          ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                              ${GREEN}║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}                                                              ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}Archivo:${NC}      ${BOLD}awx-offline-bundle.tar.gz${NC}                    ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}Tamaño:${NC}       ${BUNDLE_SIZE}                                           ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}Imágenes:${NC}     ${IMAGE_COUNT} archivos (${TOTAL_IMAGES_SIZE} total)                   ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}RPMs:${NC}         ${RPM_COUNT} paquetes Docker CE (Rocky/RHEL 9)         ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}Tiempo:${NC}       ${MINUTES}m ${SECONDS_R}s                                        ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${CYAN}Errores:${NC}      ${ERRORS}                                                ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                              ${GREEN}║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}                                                              ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  ${BOLD}SIGUIENTE PASO:${NC}                                              ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                              ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  1. Copie estos archivos al servidor Rocky/RHEL 9:           ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}     ${BOLD}awx-offline-bundle.tar.gz${NC}                                  ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                              ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  2. En el servidor destino:                                  ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}     ${DIM}tar xzf awx-offline-bundle.tar.gz${NC}                        ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}     ${DIM}cd awx-offline-bundle${NC}                                     ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}     ${BOLD}sudo bash scripts/02-install-awx.sh${NC}                      ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                              ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [[ $ERRORS -gt 0 ]]; then
    log_warn "Hubo ${ERRORS} error(es) durante la descarga. Revise los mensajes anteriores."
    log_warn "Los componentes faltantes causarán fallos en la instalación."
    exit 1
fi

# ─── Contenido del bundle ────────────────────────────────────────────────────
echo -e "${CYAN}Contenido del bundle:${NC}"
echo ""
echo "  binaries/"
ls -lh "${BUNDLE_DIR}/binaries/" | tail -n +2 | awk '{printf "    %-45s %s\n", $NF, $5}'
echo ""
echo "  rpms/"
ls -lh "${BUNDLE_DIR}/rpms/" | tail -n +2 | awk '{printf "    %-45s %s\n", $NF, $5}'
echo ""
echo "  images/"
ls -lh "${BUNDLE_DIR}/images/" | tail -n +2 | awk '{printf "    %-45s %s\n", $NF, $5}'
echo ""
echo "  manifests/"
echo "    kustomization.yaml"
echo "    awx-instance.yaml"
echo "    awx-operator-${AWX_OPERATOR_VERSION}/"
echo ""
echo "  scripts/"
ls "${BUNDLE_DIR}/scripts/" 2>/dev/null | while read -r f; do echo "    ${f}"; done
echo ""
