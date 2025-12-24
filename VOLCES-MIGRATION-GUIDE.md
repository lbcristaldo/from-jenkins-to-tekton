# Guía de Migración Jenkins → Tekton (Volces/ByteDance Infrastructure)

## Resumen de la Migración

Esta guía documenta la migración del pipeline de Jenkins a Tekton para un proyecto Python Flask que utiliza la infraestructura de Volces (ByteDance) con:

- Proxy corporativo chino
- Mirrors de Aliyun para pip
- Python 3.11 con venv
- Volces Container Registry
- Tests completos (unit, integration, vulnerability)
- Docker-in-Docker para integration tests

## Comparación Jenkinsfile → Tekton

| Etapa Jenkins | Task Tekton | Cambios Principales |
|--------------|-------------|---------------------|
| Environment preparation | `python-environment-setup` | Mismo venv, mismo proxy, mirrors Aliyun |
| Compile | `python-environment-setup` (step 2) | Integrado en la misma task |
| Unit tests | `python-tests-comprehensive` (step 1) | Ejecuta pytest exactamente igual |
| Create config | `python-tests-comprehensive` (step 2) | Mismo printf para evitar caracteres ocultos |
| Validate config | `python-tests-comprehensive` (step 3) | Validación idéntica con YAML |
| Build Docker image | `docker-build-volces` | Usa Kaniko en lugar de Docker |
| Run Docker image | `docker-integration-tests` (sidecar) | Usa sidecars de Tekton |
| Integration tests | `docker-integration-tests` | Tests contra sidecar en lugar de contenedor externo |
| Performance tests | `docker-integration-tests` (placeholder) | Comentado como en original |
| Dependency vulnerability | `python-tests-comprehensive` (step 4) | Safety check igual |
| Push Docker image | `docker-build-volces` | Kaniko hace build+push atómico |

## Diferencias Clave

### 1. **Docker-in-Docker → Sidecars**

**Jenkins:**
```groovy
docker run --name ${CONTAINER_NAME} --detach --rm --network ci -p 5001:5000 ${IMAGE_NAME}:${IMAGE_TAG}
```

**Tekton:**
```yaml
sidecars:
  - name: app-container
    image: $(params.image-url)
    ports:
      - containerPort: 5000
```

**Ventajas:**
- No necesita privilegios de Docker
- Más seguro (no socket de Docker expuesto)
- Cleanup automático
- Networking más simple (localhost)

### 2. **Credenciales de Volces CR**

**Jenkins:** Usa credential `crrobot_for_jenkins`

**Tekton:** Necesitas crear un Secret de Kubernetes

```bash
# Extraer credenciales de Jenkins primero
# Luego crear en Kubernetes:
kubectl create secret docker-registry volces-cr-credentials \
  --docker-server=ph-sw-cn-beijing.cr.volces.com \
  --docker-username=YOUR_USERNAME \
  --docker-password=YOUR_PASSWORD \
  --docker-email=YOUR_EMAIL \
  -n default
```

### 3. **Docker Build → Kaniko**

**Por qué Kaniko:**
- No requiere Docker daemon
- Más seguro (no privilegios root)
- Funciona nativamente en Kubernetes
- Build desde Dockerfile igual que Docker

**Configuración de proxy en Kaniko:**
```yaml
env:
  - name: HTTPS_PROXY
    value: "http://100.68.169.226:3128"
  - name: NO_PROXY
    value: "*.ivolces.com,*.volces.com"
```

## Pasos de Instalación

### 1. Preparar el Cluster

```bash
# Verificar acceso al cluster
kubectl cluster-info

# Verificar que puedes alcanzar el proxy corporativo
curl -x http://100.68.169.226:3128 https://www.google.com
```

### 2. Instalar Tekton

```bash
# Instalar Tekton Pipelines
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# Verificar instalación
kubectl get pods -n tekton-pipelines
kubectl wait --for=condition=Ready pods --all -n tekton-pipelines --timeout=300s
```

### 3. Configurar Credenciales de Volces CR

**Opción A: Si tienes acceso a Jenkins**

1. Acceder a Jenkins → Credentials → `crrobot_for_jenkins`
2. Extraer username y password
3. Crear secret:

```bash
kubectl create secret docker-registry volces-cr-credentials \
  --docker-server=ph-sw-cn-beijing.cr.volces.com \
  --docker-username=EXTRACTED_USERNAME \
  --docker-password=EXTRACTED_PASSWORD \
  --docker-email=your-email@company.com \
  -n default
```

**Opción B: Obtener credenciales del equipo de DevOps**

```bash
# Formato del secret
kubectl create secret docker-registry volces-cr-credentials \
  --docker-server=ph-sw-cn-beijing.cr.volces.com \
  --docker-username=YOUR_CR_USERNAME \
  --docker-password=YOUR_CR_PASSWORD \
  --docker-email=YOUR_EMAIL \
  -n default
```

### 4. Aplicar Recursos de Tekton

```bash
# Crear estructura de directorios
mkdir -p tekton/{tasks,pipeline,pipelinerun,rbac}

# Aplicar en orden:
kubectl apply -f tekton/rbac/volces-secrets-and-rbac.yaml
kubectl apply -f tekton/tasks/git-clone-task.yaml
kubectl apply -f tekton/tasks/python-environment-task.yaml
kubectl apply -f tekton/tasks/python-tests-comprehensive-task.yaml
kubectl apply -f tekton/tasks/docker-build-volces-task.yaml
kubectl apply -f tekton/tasks/integration-tests-task.yaml
kubectl apply -f tekton/pipeline/volces-python-pipeline.yaml

# Verificar
kubectl get tasks,pipelines
```

### 5. Ejecutar el Pipeline

```bash
# Primera ejecución (manual)
kubectl create -f tekton/pipelinerun/volces-pipelinerun.yaml

# Ver progreso
tkn pipelinerun logs -f -L

# O con kubectl
kubectl get pipelineruns -w
```

## Troubleshooting Específico

### Problema: "Failed to pull image" desde Volces CR

**Diagnóstico:**
```bash
# Verificar secret
kubectl get secret volces-cr-credentials -o yaml

# Test manual de pull
kubectl run test-pull --image=ph-sw-cn-beijing.cr.volces.com/jenkins/python-jenkins-pipeline:latest --dry-run=client
```

**Solución:**
```bash
# Recrear secret con credenciales correctas
kubectl delete secret volces-cr-credentials
kubectl create secret docker-registry volces-cr-credentials \
  --docker-server=ph-sw-cn-beijing.cr.volces.com \
  --docker-username=CORRECT_USERNAME \
  --docker-password=CORRECT_PASSWORD \
  -n default

# Vincular al ServiceAccount
kubectl patch serviceaccount tekton-pipeline-sa \
  -p '{"imagePullSecrets": [{"name": "volces-cr-credentials"}]}'
```

### Problema: Timeout en pip install (proxy issues)

**Diagnóstico:**
```bash
# Ver logs de la task
tkn taskrun logs setup-environment-xxxxx -f

# Buscar errores de proxy
```

**Solución:**
Si el proxy corporativo está bloqueando:

```yaml
# Agregar a la task:
env:
  - name: PIP_PROXY
    value: "http://100.68.169.226:3128"
  - name: PIP_TRUSTED_HOST
    value: "mirrors.aliyun.com pypi.org files.pythonhosted.org"
```

### Problema: Kaniko no puede hacer push

**Error común:**
```
error pushing image: denied: requested access to the resource is denied
```

**Verificación:**
```bash
# 1. Verificar que el secret existe y está bien formado
kubectl get secret volces-cr-credentials -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq .

# 2. Verificar que el workspace está configurado
kubectl describe pipelinerun volces-python-run-xxxxx | grep -A5 "docker-credentials"

# 3. Test manual de push
kubectl run kaniko-test --rm -it --restart=Never \
  --image=gcr.io/kaniko-project/executor:latest \
  --env="DOCKER_CONFIG=/kaniko/.docker" \
  -- sh
```

### Problema: Integration tests fallan con "Connection refused"

**Causa:** El sidecar no está listo

**Solución:** Ya incluida en la task con `wait-for-app` step

Si sigue fallando:
```yaml
# Aumentar timeout en wait-for-app step
for i in $(seq 1 120); do  # De 60 a 120 segundos
```

### Problema: Virtual environment no se encuentra

**Error:**
```
venv/bin/activate: No such file or directory
```

**Causa:** El workspace no se está compartiendo correctamente

**Solución:**
```bash
# Verificar PVC
kubectl get pvc

# Verificar que todas las tasks usan el mismo workspace
kubectl get pipeline volces-python-ci-cd -o yaml | grep -A3 workspaces
```

## Checklist de Migración

### Pre-Migración
- [ ] Backup del Jenkinsfile original
- [ ] Documentar credenciales necesarias
- [ ] Verificar acceso a Volces CR
- [ ] Confirmar proxy corporativo funcional
- [ ] Listar todas las dependencias del proyecto

### Instalación
- [ ] Tekton Pipelines instalado
- [ ] Tasks creadas y verificadas
- [ ] Pipeline creado
- [ ] RBAC configurado
- [ ] Secrets de Volces CR creados
- [ ] ServiceAccount configurado

### Testing
- [ ] Primera ejecución manual exitosa
- [ ] Unit tests pasando
- [ ] Integration tests pasando
- [ ] Docker image en Volces CR
- [ ] Verificar que el proxy funciona en todos los steps
- [ ] Safety check ejecutándose

### Post-Migración
- [ ] Configurar triggers (si aplica)
- [ ] Documentar diferencias con Jenkins
- [ ] Entrenar al equipo en Tekton
- [ ] Configurar monitoreo/alertas
- [ ] Plan de rollback si es necesario

## Flujo Completo del Pipeline

```
┌─────────────────┐
│   Git Clone     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Env Setup +    │
│    Compile      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Unit Tests +   │
│  Config + Val + │
│  Vuln Check     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Docker Build +  │
│  Push (Kaniko)  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Integration     │
│ Tests (Sidecar) │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│    Summary      │
└─────────────────┘
```

## 🎓 Diferencias Conceptuales Importantes

### Jenkins → Tekton

1. **Agente (`agent any`)** → **Pod (automático)**
   - Jenkins: Define agente en pipeline
   - Tekton: Cada Task corre en su propio pod

2. **Workspace compartido** → **PVC Workspace**
   - Jenkins: Directorio en agente
   - Tekton: PersistentVolumeClaim compartido

3. **Docker socket** → **Kaniko o Buildah**
   - Jenkins: Monta `/var/run/docker.sock`
   - Tekton: No requiere Docker daemon

4. **Post actions** → **Finally tasks**
   - Jenkins: `post { always { ... } }`
   - Tekton: `finally: [ ... ]`

5. **Credentials** → **Kubernetes Secrets**
   - Jenkins: Jenkins Credentials Store
   - Tekton: Native K8s Secrets

## Próximos Pasos

1. **Triggers para CI automático**
   - Configurar EventListener para webhooks
   - Integrar con GitHub/GitLab

2. **Optimización**
   - Cache de dependencias pip
   - Multi-stage Dockerfile
   - Parallel tasks donde sea posible

3. **Monitoreo**
   - Integrar con Prometheus
   - Alertas en Slack/WeChat
   - Dashboard personalizado

4. **Ambientes**
   - Pipeline para dev/staging/prod
   - Diferentes configuraciones por ambiente

## Recursos

- [Tekton Documentation](https://tekton.dev/docs/)
- [Kaniko Documentation](https://github.com/GoogleContainerTools/kaniko)
- [Volces Documentation](https://www.volcengine.com/docs/6396/74861)

## Validación Final

Después de completar la migración, valida:

```bash
# 1. Pipeline ejecuta correctamente
kubectl create -f tekton/pipelinerun/volces-pipelinerun.yaml

# 2. Imagen aparece en Volces CR
# Verificar en: https://console.volcengine.com/cr

# 3. Todos los tests pasan
tkn pipelinerun logs -f | grep "✅"

# 4. Tiempos de ejecución comparables a Jenkins
# Documentar diferencias si las hay
```

---

**¡Migración completada!** 
