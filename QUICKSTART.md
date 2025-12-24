# Quick Start - Sin Credenciales Enterprise

Versión **adaptada** del proyecto original: uso de infraestructura **pública y gratuita**.

## Cambios principales vs original

| Original (Enterprise) | Esta Versión (Pública) |
|----------------------|------------------------|
| Volces CR (Beijing) | Docker Hub / GHCR (gratis) |
| Proxy corporativo chino | Sin proxy (internet directo) |
| Aliyun mirrors | PyPI estándar |
| Credenciales enterprise | Tu cuenta gratuita |
| Red corporativa | Internet público |

---

## Requisitos

### Obligatorios:
- **Kubernetes cluster** (minikube, kind, o cualquier cluster)
- **kubectl** instalado
- Conexión a internet

### Opcionales:
- **Cuenta de Docker Hub** (gratis) → https://hub.docker.com
- **Tekton CLI (tkn)** (recomendado)
- **Cuenta de GitHub** (para GHCR)

---

## Quick Installation

### Clonar el repo (tu fork)

```bash
git clone https://github.com/TU-USUARIO/tu-fork.git
cd tu-fork
```

### Ejecutar script de setup

```bash
chmod +x deploy-public-tekton.sh
./deploy-public-tekton.sh
```

El script te preguntará:
- ¿Instalar Dashboard? → **Sí** (recomendado)
- ¿Qué registry usar? → **Docker Hub** (opción 1)
- Credenciales → Introduce las tuyas

### Editar el PipelineRun

```bash
nano public-pipelinerun.yaml
```

Cambiar esta línea:
```yaml
- name: image-name
  value: "docker.io/YOUR_USERNAME/python-app"  # TU USUARIO 
```

Por ejemplo:
```yaml
- name: image-name
  value: "docker.io/juanita/python-app"
```

### Ejecutar el pipeline

```bash
kubectl create -f public-pipelinerun.yaml
```

---

### Ver el progreso

**Opción A: Con Tekton CLI**
```bash
tkn pipelinerun logs -f -L
```

**Opción B: Con kubectl**
```bash
# Ver PipelineRuns
kubectl get pipelineruns -w

# Ver logs de un pod específico
kubectl get pods
kubectl logs -f <nombre-del-pod>
```

**Opción C: Con Dashboard**
```bash
kubectl port-forward -n tekton-pipelines svc/tekton-dashboard 9097:9097
# Abrir: http://localhost:9097
```

## Qué hace el pipeline

```
1. fetch-source          → Clona el repo de GitHub
2. setup-environment     → Crea venv, instala dependencias
3. run-tests-and-config  → Tests unitarios + config.yml + safety check
4. build-and-push-image  → Build Docker con Kaniko + Push a registry
5. integration-tests     → Corre el container + tests de integración
```

---

## Troubleshooting

### Error: "ImagePullBackOff"

**Causa:** Credenciales incorrectas o imagen no existe

**Solución:**
```bash
# Verificar secret
kubectl get secret dockerhub-credentials -o yaml

# Recrear secret
kubectl delete secret dockerhub-credentials
kubectl create secret docker-registry dockerhub-credentials \
  --docker-server=docker.io \
  --docker-username=TU_USUARIO \
  --docker-password=TU_PASSWORD \
  --docker-email=TU_EMAIL
```

### Error: "PVC pending"

**Causa:** Sin storage class disponible

**Solución:**
```bash
# Ver storage classes disponibles
kubectl get storageclass

# Si usas minikube:
minikube addons enable storage-provisioner

# Si usas kind, ya tiene uno por defecto
```

### Error: "Tests failing"

**Causa:** El repo original puede tener tests que requieren setup específico

**Solución:**
```bash
# Ver qué tests hay
git clone https://github.com/restalion/python-jenkins-pipeline.git temp
ls temp/test/
ls temp/int_test/

# Si no existen o están rotos:
# 1. Comentar los steps de tests en las tasks
# 2. O crear tests básicos 
```

### Pipeline toma mucho tiempo

**Causa:** Descargando dependencias por primera vez

**Solución:** Normal en la primera ejecución. Las siguientes serán más rápidas por cache.

## Tiempo estimado de ejecución

| Etapa | Primera vez | Subsecuentes |
|-------|-------------|--------------|
| Git clone | 10s | 10s |
| Environment setup | 2-3 min | 1-2 min |
| Tests | 30s-1min | 30s-1min |
| Docker build | 2-4 min | 1-2 min (cache) |
| Integration tests | 1-2 min | 1-2 min |
| **TOTAL** | **7-10 min** | **4-6 min** |

## Diferencias con Jenkins

### Jenkins (original):
```groovy
stage('Build Docker image') {
    steps {
        sh 'docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .'
    }
}
```

### Tekton (adaptado):
```yaml
- name: build-and-push-image
  taskRef:
    name: docker-build-push
  params:
    - name: image-name
      value: $(params.image-name)
```

**Ventajas de Tekton:**
- No necesita Docker daemon 
- Más seguro (Kaniko)
- Native en Kubernetes
- Declarativo (YAML en Git)

## Próximos pasos

### 1. Automatizar con Triggers

Configura webhooks para que el pipeline se ejecute automáticamente al hacer push:

```bash
kubectl apply -f tekton-triggers.yaml
```

### 2. Añadir más tests

Crea tus propios tests en el repo:

```python
# test/test_app.py
def test_home():
    assert True
```

### 3. Deploy a Kubernetes

Agrega una task de deploy:

```yaml
- name: deploy-to-k8s
  taskRef:
    name: kubernetes-deploy
  params:
    - name: manifest-dir
      value: "k8s/"
```

### 4. Multi-environment

Crea pipelines separados para dev/staging/prod.

## Recursos

- **Tekton Docs:** https://tekton.dev/docs/
- **Repo original:** https://github.com/restalion/python-jenkins-pipeline
- **Docker Hub:** https://hub.docker.com
- **Kaniko:** https://github.com/GoogleContainerTools/kaniko

## ˗ˏˋ✩ˎˊ˗ Contribuir

Si mejoras este setup:
1. Fork el repo
2. Crea una rama con tu feature
3. Haz un PR!!

---

**¿Problemas?** Abre un issue en el repo o consulta la documentación completa en `VOLCES-MIGRATION-GUIDE.md`.
