# Python Jenkins to Tekton Migration

 *Este repositorio contiene la migración completa de un pipeline de Jenkins a Tekton para aplicaciones Python.*

## Descripción

Proyecto de ejemplo que demuestra cómo migrar pipelines de CI/CD desde Jenkins a Tekton, aprovechando las capacidades nativas de Kubernetes para:

- Mayor portabilidad entre clústeres
- Ejecución basada en contenedores
- Escalado automático
- Mejor integración con ecosistema CNCF
- Pipelines como código (GitOps ready)

## Arquitectura

```
┌─────────────┐
│   GitHub    │
│  (Webhook)  │
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│ EventListener   │
│   (Triggers)    │
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│   Pipeline      │
│  ┌───────────┐  │
│  │Git Clone  │  │
│  └─────┬─────┘  │
│        ▼        │
│  ┌───────────┐  │
│  │   Test    │  │
│  └─────┬─────┘  │
│        ▼        │
│  ┌───────────┐  │
│  │   Build   │  │
│  └─────┬─────┘  │
│        ▼        │
│  ┌───────────┐  │
│  │  Deploy   │  │
│  └───────────┘  │
└─────────────────┘
       │
       ▼
┌─────────────────┐
│   Kubernetes    │
│    Cluster      │
└─────────────────┘
```

## Prerequisitos

- Kubernetes 1.24+
- `kubectl` instalado y configurado
- `tkn` CLI (Tekton CLI) - opcional pero recomendado
- Cuenta de Docker Hub (o registry de imágenes alternativo)
- Acceso al cluster con permisos de administrador

## Quickstart

### 1. Clonar el repositorio

```bash
git clone https://github.com/restalion/python-jenkins-pipeline.git
cd python-jenkins-pipeline
```

### 2. Instalar Tekton (automático)

```bash
chmod +x deploy-tekton.sh
./deploy-tekton.sh
```

### 3. Configurar credenciales

```bash
# Docker Hub
kubectl create secret docker-registry docker-credentials \
  --docker-server=docker.io \
  --docker-username=TU_USUARIO \
  --docker-password=TU_PASSWORD \
  --docker-email=TU_EMAIL \
  -n default
```

### 4. Ejecutar el pipeline

```bash
# Editar python-pipelinerun.yaml con tus valores
# Luego ejecutar:
kubectl create -f tekton/pipelinerun/python-pipelinerun.yaml

# Ver logs en tiempo real
tkn pipelinerun logs -f -L
```

## Estructura del Proyecto

```
.
├── tekton/
│   ├── tasks/                  # Definiciones de Tasks
│   │   ├── git-clone-task.yaml
│   │   ├── python-test-task.yaml
│   │   ├── docker-build-task.yaml
│   │   └── kubernetes-deploy-task.yaml
│   ├── pipeline/               # Definición del Pipeline
│   │   └── python-pipeline.yaml
│   ├── pipelinerun/           # Ejecuciones del Pipeline
│   │   └── python-pipelinerun.yaml
│   ├── triggers/              # Configuración de Triggers
│   │   └── tekton-triggers.yaml
│   ├── rbac/                  # Permisos y Secrets
│   │   └── rbac-and-secrets.yaml
│   └── scripts/               # Scripts de utilidad
│       └── deploy-tekton.sh
├── k8s/                       # Manifiestos de Kubernetes
│   └── deployment.yaml
├── src/                       # Código fuente Python
├── tests/                     # Tests unitarios
├── Dockerfile
├── requirements.txt
├── MIGRATION-GUIDE.md         # Guía detallada de migración
└── README.md
```

## Etapas del Pipeline

### 1. **Git Clone**
- Clona el repositorio
- Checkout a la rama específica
- Prepara el workspace compartido

### 2. **Python Test**
- Instala dependencias (`requirements.txt`)
- Ejecuta tests con pytest
- Genera reporte de cobertura
- Ejecuta linters (flake8, black)

### 3. **Docker Build & Push**
- Construye imagen Docker usando Kaniko
- Optimiza capas con cache
- Push a Docker Hub
- Tag con commit SHA o nombre de PipelineRun

### 4. **Kubernetes Deploy**
- Aplica manifiestos de Kubernetes
- Actualiza deployment con nueva imagen
- Espera rollout exitoso
- Valida salud de pods

## Configuración Detallada

### Parámetros del Pipeline

Edita `python-pipelinerun.yaml` para ajustar:

```yaml
params:
  - name: repo-url
    value: "https://github.com/tu-usuario/tu-repo.git"
  - name: revision
    value: "main"
  - name: image-name
    value: "tu-usuario/python-app"
  - name: image-tag
    value: "latest"
  - name: deploy-namespace
    value: "default"
```

### Webhooks de GitHub

Para CI automático al hacer push:

1. **En GitHub:**
   - Settings → Webhooks → Add webhook
   - Payload URL: `http://tu-cluster-url:8080`
   - Content type: `application/json`
   - Secret: (generado en el paso anterior)
   - Events: Just the push event

2. **Exponer EventListener:**

```bash
# Port-forward para testing local
kubectl port-forward svc/el-github-listener 8080:8080

# O crear Ingress para producción
kubectl apply -f tekton/triggers/tekton-triggers.yaml
```

## Monitoreo

### Tekton Dashboard

```bash
# Instalar
kubectl apply -f https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml

# Acceder
kubectl port-forward -n tekton-pipelines svc/tekton-dashboard 9097:9097

# Abrir en navegador
open http://localhost:9097
```

### Comandos útiles

```bash
# Ver todos los PipelineRuns
tkn pipelinerun list

# Ver logs del último PipelineRun
tkn pipelinerun logs -f -L

# Describir un Pipeline
tkn pipeline describe python-ci-cd

# Ver Tasks disponibles
tkn task list

# Cancelar un PipelineRun en ejecución
tkn pipelinerun cancel <nombre>

# Limpiar PipelineRuns completados
tkn pipelinerun delete --all-completed
```

## Testing Local

### Ejecutar tests manualmente

```bash
# Instalar dependencias
pip install -r requirements.txt

# Ejecutar tests
pytest tests/ -v --cov=.

# Linting
flake8 .
black --check .
```

### Build local de Docker

```bash
# Build
docker build -t python-app:dev .

# Run
docker run -p 8000:8000 python-app:dev

# Test
curl http://localhost:8000/health
```

## Troubleshooting

### Pipeline falla en Git Clone

```bash
# Verificar URL del repositorio
kubectl get pipeline python-ci-cd -o yaml | grep url

# Verificar conectividad
kubectl run -it --rm debug --image=alpine --restart=Never -- sh
/ # apk add git
/ # git clone https://github.com/restalion/python-jenkins-pipeline.git
```

### Error al hacer push a Docker Hub

```bash
# Verificar secret
kubectl get secret docker-credentials -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d

# Recrear secret
kubectl delete secret docker-credentials
kubectl create secret docker-registry docker-credentials \
  --docker-server=docker.io \
  --docker-username=TU_USUARIO \
  --docker-password=TU_PASSWORD \
  --docker-email=TU_EMAIL
```

### Pipeline se queda en Pending

```bash
# Verificar PVC
kubectl get pvc

# Ver eventos
kubectl describe pipelinerun <nombre>

# Verificar recursos del cluster
kubectl top nodes
```

Ver [MIGRATION-GUIDE.md](MIGRATION-GUIDE.md) para más detalles de troubleshooting.

## Comparación Jenkins vs Tekton

| Aspecto | Jenkins | Tekton |
|---------|---------|--------|
| **Ejecución** | VM/Container agent | Pods nativos de K8s |
| **Configuración** | Groovy (Jenkinsfile) | YAML (CRDs de K8s) |
| **Escalabilidad** | Manual/plugins | Auto-scaling nativo |
| **Portabilidad** | Depende de plugins | 100% Kubernetes |
| **Almacenamiento** | Workspace en disco | PVC/Workspaces |
| **Observabilidad** | Plugins variados | Dashboard + K8s tools |
| **Triggers** | Webhooks propios | Tekton Triggers |
| **GitOps** | Limitado | Nativo (YAML en Git) |

## Recursos Adicionales

- [Documentación de Tekton](https://tekton.dev/docs/)
- [Tekton Catalog](https://hub.tekton.dev/) - Tasks reutilizables
- [Guía de Migración Completa](MIGRATION-GUIDE.md)
- [Mejores Prácticas](https://tekton.dev/docs/pipelines/tasks/#best-practices)

## Contribuir

Las contribuciones son bienvenidas. Por favor:

1. Fork el proyecto
2. Crea una rama para tu feature (`git checkout -b feature/amazing-feature`)
3. Commit tus cambios (`git commit -m 'Add amazing feature'`)
4. Push a la rama (`git push origin feature/amazing-feature`)
5. Abre un Pull Request

## License

Este proyecto está bajo la licencia MIT. Ver `LICENSE` para más detalles.

## Autora de la migración: 
Luciana Cristaldo.
Diciembre, 2025.

---

 Si este proyecto te ayudó, considera darle una estrella en GitHub!

**¿Preguntas?** Abre un issue en el repositorio.
