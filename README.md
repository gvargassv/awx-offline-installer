# AWX Offline Installer

[![AWX Version](https://img.shields.io/badge/AWX-24.6.1-blue)](https://github.com/ansible/awx/releases/tag/24.6.1)
[![Operator Version](https://img.shields.io/badge/AWX_Operator-2.19.1-blue)](https://github.com/ansible/awx-operator/releases/tag/2.19.1)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.30.0-326CE5)](https://kubernetes.io)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

Instalador automatizado y completamente offline (air-gapped) de **Ansible AWX 24.6.1** sobre **Minikube** para servidores **Rocky Linux 9.x / RHEL 9.x / AlmaLinux 9.x** sin acceso a internet.

## ¿Cómo funciona?

Dos scripts. Uno descarga todo, el otro instala todo.

| Script | Dónde se ejecuta | Qué hace |
|--------|------------------|----------|
| `01-prepare-bundle.sh` | Máquina **con** internet | Descarga binarios, imágenes, RPMs y manifiestos |
| `02-install-awx.sh` | Servidor **sin** internet | Instala Docker, Minikube, K8s y AWX automáticamente |

Al finalizar, el instalador muestra la **URL de acceso**, **usuario**, **contraseña** y **estado de todos los pods**.

---

## Guía Rápida (3 pasos)

### Paso 1 — Preparar el bundle (máquina con internet)

> Funciona desde **cualquier SO** con Docker: Linux, macOS, Windows (WSL2).
> No necesita ser Rocky Linux. Los RPMs se descargan vía curl.

```bash
git clone https://github.com/<tu-usuario>/awx-offline-installer.git
cd awx-offline-installer

sudo bash scripts/01-prepare-bundle.sh
```

Genera `awx-offline-bundle.tar.gz` (~5-6 GB) con todo lo necesario.

### Paso 2 — Transferir al servidor sin internet

```bash
# SCP por red interna
scp awx-offline-bundle.tar.gz root@<IP_SERVIDOR>:/root/

# O por USB
cp awx-offline-bundle.tar.gz /media/usb/
```

### Paso 3 — Instalar AWX (servidor sin internet)

```bash
cd /root
tar xzf awx-offline-bundle.tar.gz
cd awx-offline-bundle

sudo bash scripts/02-install-awx.sh
```

Eso es todo. Al finalizar verá:

```
╔══════════════════════════════════════════════════════════════════════╗
║     ✔  INSTALACIÓN DE AWX COMPLETADA                                ║
╠══════════════════════════════════════════════════════════════════════╣
║  URL (NodePort):    http://192.168.49.2:30080                        ║
║  URL (Forward):     http://10.0.0.50:8080                            ║
║  Usuario:           admin                                            ║
║  Contraseña:        xK9m2pL7qR4w                                    ║
╠══════════════════════════════════════════════════════════════════════╣
║  ✔  awx-operator-controller-manager-xxx    Running (2/2)             ║
║  ✔  awx-postgres-15-0                      Running (1/1)             ║
║  ✔  awx-task-xxx                           Running (4/4)             ║
║  ✔  awx-web-xxx                            Running (3/3)             ║
╚══════════════════════════════════════════════════════════════════════╝
```

---

## Requisitos

### Máquina con internet (preparar bundle)

- **Cualquier SO** con Docker instalado (Linux, macOS, WSL2)
- ~15 GB de espacio libre en disco
- Acceso a internet

### Servidor destino (air-gapped)

| Recurso | Mínimo | Recomendado |
|---------|--------|-------------|
| CPU | 4 vCPUs | 4+ vCPUs |
| RAM | 8 GB | 16 GB |
| Disco libre | 40 GB | 60+ GB |
| SO | Rocky Linux 9.x / RHEL 9.x / AlmaLinux 9.x | x86_64 |

---

## Opciones del Instalador

```bash
sudo bash 02-install-awx.sh [opciones]
```

| Opción | Default | Descripción |
|--------|---------|-------------|
| `--cpus N` | Auto-detecta | CPUs para Minikube |
| `--memory NNg` | Auto-calcula | RAM para Minikube |
| `--disk NNg` | 40g | Disco virtual de Minikube |
| `--skip-docker` | false | Omite instalación de Docker |

---

## Qué se Instala

| Componente | Versión | Imagen |
|-----------|---------|--------|
| AWX | 24.6.1 | `quay.io/ansible/awx:24.6.1` |
| AWX Operator | 2.19.1 | `quay.io/ansible/awx-operator:2.19.1` |
| AWX EE | 24.6.1 | `quay.io/ansible/awx-ee:24.6.1` |
| PostgreSQL | 15 | `docker.io/library/postgres:15` |
| Redis | 7 | `docker.io/library/redis:7` |
| Kubernetes | v1.30.0 | Minikube single-node |
| Docker CE | 27.x | RPMs del repo oficial para RHEL 9 |

---

## Estructura del Repositorio

```
awx-offline-installer/
├── README.md                          ← Estás aquí
├── LICENSE
├── .gitignore
├── scripts/
│   ├── 01-prepare-bundle.sh           ← Máquina con internet
│   └── 02-install-awx.sh             ← Servidor air-gapped
├── docs/
│   ├── GUIA-COMPLETA.md              ← Guía detallada paso a paso
│   ├── TROUBLESHOOTING.md            ← Solución de problemas
│   └── CHANGELOG.md                  ← Historial de cambios
└── examples/
    └── awx-instance-custom.yaml      ← Ejemplo de configuración avanzada
```

---

## Documentación

| Documento | Descripción |
|-----------|-------------|
| [Guía Completa](docs/GUIA-COMPLETA.md) | Explicación detallada de cada fase con todos los comandos |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | Problemas comunes y cómo resolverlos |
| [Changelog](docs/CHANGELOG.md) | Historial de versiones y cambios |

---

## Comandos de Referencia Rápida

```bash
kubectl get pods -n awx                    # Ver pods
kubectl get svc -n awx                     # Ver servicios
minikube status                            # Estado del cluster

# Obtener contraseña de admin
kubectl get secret awx-admin-password -n awx \
  -o jsonpath='{.data.password}' | base64 -d ; echo

# Logs
kubectl logs -f deploy/awx-web -n awx -c awx-web
kubectl logs -f deploy/awx-task -n awx -c awx-task

# Reiniciar
kubectl rollout restart deploy/awx-web -n awx
```

---

## Contribuir

PRs bienvenidos. Si encuentras un bug o quieres mejorar los scripts, abre un Issue o envía un Pull Request.

## Licencia

[MIT](LICENSE)
