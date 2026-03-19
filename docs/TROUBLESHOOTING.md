# Troubleshooting — AWX Offline Installer

Guía de solución de problemas comunes durante la instalación offline de AWX 24.6.1.

---

## Índice

- [Problemas con Docker](#problemas-con-docker)
- [Problemas con Minikube](#problemas-con-minikube)
- [Problemas con imágenes (ImagePullBackOff)](#problemas-con-imágenes)
- [Problemas con el AWX Operator](#problemas-con-el-awx-operator)
- [Problemas con los pods de AWX](#problemas-con-los-pods-de-awx)
- [Problemas de recursos (OOMKilled / Pending)](#problemas-de-recursos)
- [Problemas de acceso a la interfaz web](#problemas-de-acceso-a-la-interfaz-web)
- [Problemas con Jobs y Execution Environments](#problemas-con-jobs-y-execution-environments)
- [Comandos de diagnóstico general](#comandos-de-diagnóstico-general)
- [Reinstalación completa](#reinstalación-completa)

---

## Problemas con Docker

### RPMs no se instalan: dependencias faltantes

```
Error: Problem: conflicting requests
  - nothing provides libXXX needed by docker-ce-...
```

**Causa:** El servidor no tiene todas las dependencias base instaladas.

**Solución:** En la máquina con internet, re-descargar los RPMs incluyendo todas las dependencias:

```bash
# En una máquina Rocky/RHEL 9 CON internet
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf download --resolve --alldeps --destdir=rpms/ \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
```

Transferir nuevamente la carpeta `rpms/` al servidor.

### Docker no inicia: conflicto con Podman

```
Error: Unit docker.service entered failed state
```

**Solución:**

```bash
dnf remove -y podman buildah containers-common
```

```bash
systemctl daemon-reload
systemctl start docker
```

### Docker no inicia: problema con storage driver

```bash
# Verificar logs
journalctl -u docker --no-pager -n 50
```

```bash
# Si es problema de overlay2, verificar filesystem
df -Th /var/lib/docker
# Debe ser xfs o ext4
```

---

## Problemas con Minikube

### Minikube no inicia: imagen kicbase no encontrada

```
! Unable to find image 'gcr.io/k8s-minikube/kicbase:v0.0.45'
```

**Solución:**

```bash
# Verificar que la imagen está en Docker
docker images | grep kicbase
```

```bash
# Si no aparece, recargar
docker load -i images/kicbase-v0.0.45.tar
```

### Minikube no inicia: Docker socket no accesible

```
Exiting due to DRV_NOT_HEALTHY
```

**Solución:**

```bash
systemctl status docker
```

```bash
# Si no está corriendo
systemctl start docker
```

### Minikube no inicia después de un reinicio del servidor

```bash
# Verificar que Docker está corriendo primero
systemctl start docker
```

```bash
# Luego iniciar Minikube
minikube start
```

```bash
# Si no funciona, verificar estado
minikube status
```

```bash
# Si está corrupto, borrar y recrear
minikube delete
# Repetir desde Fase 4 de la guía
```

### Error: insufficient memory

```
Requested memory allocation (2048MB) is less than the minimum allowed (2200MB)
```

**Solución:** Aumentar la memoria al iniciar:

```bash
minikube start --memory=4g ...
```

---

## Problemas con Imágenes

### Pods en ImagePullBackOff o ErrImagePull

Este es el error **más común** en instalaciones offline. Significa que Kubernetes intenta descargar la imagen de internet.

```bash
# Ver qué imagen falta
kubectl describe pod <nombre-del-pod> -n awx | grep -A3 "Events"
```

```bash
# Listar imágenes disponibles en Minikube
minikube image ls
```

```bash
# Recargar la imagen faltante
minikube image load images/<imagen>.tar
```

**Imágenes que necesita cada pod:**

| Pod | Imágenes necesarias |
|-----|-------------------|
| `awx-operator-controller-manager` | `awx-operator:2.19.1` |
| `awx-postgres-15-0` | `postgres:15` |
| `awx-web-*` | `awx:24.6.1`, `redis:7` |
| `awx-task-*` | `awx:24.6.1`, `redis:7`, `awx-ee:24.6.1` |

### Método alternativo si `minikube image load` falla

```bash
# Conectar al Docker interno de Minikube
eval $(minikube docker-env)
```

```bash
# Cargar directamente
docker load -i images/awx-24.6.1.tar
docker load -i images/awx-ee-24.6.1.tar
# ... etc
```

```bash
# Verificar
docker images | grep awx
```

```bash
# IMPORTANTE: volver al Docker del host
eval $(minikube docker-env -u)
```

---

## Problemas con el AWX Operator

### Operator en CrashLoopBackOff

```bash
# Ver logs del operator
kubectl logs deployment/awx-operator-controller-manager -n awx -c awx-manager
```

```bash
# Ver eventos
kubectl get events -n awx --sort-by='.lastTimestamp' | head -20
```

**Causas comunes:**
- Imagen del operator no cargada → ver sección de imágenes arriba
- Error de RBAC → verificar que el namespace `awx` existe con `kubectl get ns awx`

### Kustomize falla al aplicar

```
error: unable to find one of 'kustomization.yaml'...
```

**Solución:** Verificar que la estructura de manifiestos es correcta:

```bash
ls -la manifests/
# Debe tener: kustomization.yaml, awx-instance.yaml, awx-operator-2.19.1/
```

```bash
ls manifests/awx-operator-2.19.1/config/default/
# Debe tener: kustomization.yaml y otros archivos
```

---

## Problemas con los Pods de AWX

### awx-postgres en Pending: StorageClass no encontrada

```bash
kubectl describe pod awx-postgres-15-0 -n awx
# Buscar: "no persistent volumes available for this claim"
```

**Solución:**

```bash
# Verificar StorageClass
kubectl get sc
```

```bash
# Si no hay ninguna, Minikube debería tener "standard" por defecto
# Si falta, crear una:
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: k8s.io/minikube-hostpath
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF
```

### awx-web o awx-task en CrashLoopBackOff

```bash
# Verificar logs del contenedor específico
kubectl logs <pod-name> -n awx -c awx-web
kubectl logs <pod-name> -n awx -c awx-task
```

```bash
# Ver estado anterior (si ya se reinició)
kubectl logs <pod-name> -n awx -c awx-web --previous
```

**Causa frecuente:** PostgreSQL no está listo todavía. AWX necesita que postgres esté Running antes de iniciar. Espere unos minutos.

### awx-task tiene solo 3/4 contenedores Ready

El cuarto contenedor es el `awx-ee` (execution environment). Si falta la imagen:

```bash
minikube image load images/awx-ee-24.6.1.tar
```

```bash
# Reiniciar el deployment
kubectl rollout restart deployment/awx-task -n awx
```

---

## Problemas de Recursos

### Pods en estado OOMKilled

Los pods se reinician constantemente porque el servidor no tiene suficiente RAM.

```bash
# Verificar qué pod fue killed
kubectl get pods -n awx
```

```bash
# Ver detalle
kubectl describe pod <pod-name> -n awx | grep -A5 "Last State"
```

**Soluciones:**
1. **Mejor opción:** Aumentar RAM del servidor (mínimo 8 GB, ideal 16 GB)
2. Reiniciar Minikube con menos memoria reservada:
   ```bash
   minikube stop
   minikube start --memory=4g
   ```

### Pods en Pending: insufficient cpu/memory

```bash
kubectl describe pod <pod-name> -n awx | grep -A3 "Conditions"
```

El nodo no tiene suficientes recursos libres para el pod.

```bash
# Ver recursos disponibles
kubectl describe node | grep -A10 "Allocated resources"
```

---

## Problemas de Acceso a la Interfaz Web

### No se puede acceder por NodePort

```bash
# Verificar la IP de Minikube
minikube ip
```

```bash
# Verificar que el servicio tiene NodePort asignado
kubectl get svc -n awx
```

```bash
# Si la IP de Minikube no es accesible desde tu red, use port-forward
kubectl port-forward svc/awx-service 8080:80 -n awx --address 0.0.0.0 &
```

### Port-forward se desconecta

```bash
# Verificar el servicio systemd
systemctl status awx-portforward
```

```bash
# Reiniciar si está caído
systemctl restart awx-portforward
```

```bash
# O ejecutar manualmente
kubectl port-forward svc/awx-service 8080:80 -n awx --address 0.0.0.0 &
```

### AWX muestra pantalla en blanco o error 502

AWX puede tardar **varios minutos** después de que los pods muestren Running. Especialmente en servidores con poca RAM.

```bash
# Verificar logs
kubectl logs -f deploy/awx-web -n awx -c awx-web
```

Espere hasta que vea mensajes indicando que el servicio está escuchando en el puerto.

### No recuerdo la contraseña de admin

```bash
kubectl get secret awx-admin-password -n awx \
  -o jsonpath='{.data.password}' | base64 --decode ; echo
```

---

## Problemas con Jobs y Execution Environments

### Jobs fallan con ErrImagePull en Execution Environment

AWX intenta descargar `quay.io/ansible/awx-ee:latest` de internet.

**Solución:**

```bash
# Recargar imagen del EE
minikube image load images/awx-ee-24.6.1.tar
```

En la interfaz de AWX:
1. Ir a **Administration → Execution Environments**
2. Editar o crear el EE
3. Cambiar la imagen a: `quay.io/ansible/awx-ee:24.6.1` (con tag específico, no `latest`)
4. Pull policy: **IfNotPresent** o **Never**

### Jobs se quedan en "Pending" indefinidamente

```bash
# Verificar si hay pods de ejecución creándose
kubectl get pods -n awx | grep -i receptor
```

```bash
# Ver logs del task runner
kubectl logs deploy/awx-task -n awx -c awx-task | tail -30
```

---

## Comandos de Diagnóstico General

```bash
# Estado completo del namespace AWX
kubectl get all -n awx
```

```bash
# Detalle de un pod problemático
kubectl describe pod <nombre-del-pod> -n awx
```

```bash
# Logs de un contenedor específico
kubectl logs <pod> -n awx -c <container>
```

```bash
# Logs del contenedor anterior (si se reinició)
kubectl logs <pod> -n awx -c <container> --previous
```

```bash
# Eventos recientes ordenados por tiempo
kubectl get events -n awx --sort-by='.lastTimestamp'
```

```bash
# Uso de recursos
kubectl top nodes
kubectl top pods -n awx
```

```bash
# Shell dentro de Minikube
minikube ssh
```

```bash
# Estado de Minikube
minikube status
```

```bash
# Log del instalador
cat /var/log/awx-offline-install.log
```

---

## Reinstalación Completa

Si necesita empezar de cero:

```bash
# 1. Eliminar AWX y el Operator
kubectl delete -f manifests/awx-instance.yaml 2>/dev/null
kubectl delete -k manifests/ 2>/dev/null
kubectl delete namespace awx
```

```bash
# 2. Eliminar Minikube
minikube delete
```

```bash
# 3. Re-ejecutar el instalador
cd /root/awx-offline-bundle
sudo bash scripts/02-install-awx.sh
```

Si quiere eliminar absolutamente todo (incluyendo Docker):

```bash
minikube delete
systemctl stop docker
dnf remove -y docker-ce docker-ce-cli containerd.io
rm -rf /var/lib/docker /var/lib/containerd ~/.minikube ~/.kube
```
