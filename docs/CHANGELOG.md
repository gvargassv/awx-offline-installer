# Changelog

Todos los cambios notables de este proyecto se documentan en este archivo.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/).

---

## [1.0.0] — 2026-03-19

### Agregado

- Script `01-prepare-bundle.sh` para preparar el bundle offline desde cualquier SO con Docker
- Script `02-install-awx.sh` para instalación automatizada en servidor air-gapped
- Descarga automática de RPMs de Docker CE para Rocky/RHEL 9 via curl (no requiere `dnf`)
- Auto-detección de CPUs y RAM del servidor para configurar Minikube
- Parámetros opcionales: `--cpus`, `--memory`, `--disk`, `--skip-docker`
- Creación automática de servicios systemd (minikube + port-forward)
- Resumen final con URL, usuario, contraseña y estado de pods
- Verificación del bundle antes de iniciar la instalación
- Guía completa paso a paso en `docs/GUIA-COMPLETA.md`
- Guía de troubleshooting en `docs/TROUBLESHOOTING.md`
- Ejemplo de configuración avanzada en `examples/`

### Versiones incluidas

- AWX: 24.6.1
- AWX Operator: 2.19.1
- Kubernetes: v1.30.0 (via Minikube)
- PostgreSQL: 15
- Redis: 7
- Docker CE: 27.x
