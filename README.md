# Jenkins to Tekton Migration

Migration of a Python Flask CI/CD pipeline from Jenkins to Tekton, adapted from enterprise infrastructure to public container registries with secure GitOps practices.
---
## Project Origin

Based on [restalion/python-jenkins-pipeline](https://github.com/restalion/python-jenkins-pipeline) - an enterprise Jenkinsfile originally configured for ByteDance/Volces infrastructure in China.

---

## What This Project Does

Migrates a complete CI/CD workflow from Jenkins to Kubernetes-native Tekton, including:
- Git repository cloning
- Python environment setup with virtual environments
- Unit and integration testing
- Docker image building with Kaniko
- Push to Docker Hub
- Secure credential management with SealedSecrets
- RBAC-restricted service accounts

---

## Project Structure
```
.
├── app/                          # Flask application
│   ├── module_one/
│   │   ├── controllers.py
│   │   └── models.py
│   └── templates/
├── test/                         # Unit tests
│   └── test_basicfunction.py
├── int_test/                     # Integration tests
│   └── int_test.py
├── tekton/                       # Tekton CI/CD configuration
│   ├── tasks/
│   │   ├── git-clone-task.yaml
│   │   ├── python-environment-public-task.yaml
│   │   ├── python-tests-public-task.yaml
│   │   ├── docker-build-public-task.yaml
│   │   └── integration-tests-public-task.yaml
│   ├── pipeline/
│   │   └── public-python-pipeline.yaml
│   ├── pipelinerun/
│   │   └── public-pipelinerun.yaml
│   └── rbac/
│       ├── public-secrets-setup.yaml      # Basic RBAC configuration
│       └── restricted-rbac.yaml           # Production-restrictive RBAC
├── sealed-secret.yaml                     # Encrypted credentials (safe for Git)
├── sealed-secret-tekton-prod.yaml        # Namespaced encrypted credentials
├── Dockerfile                    # Adapted for public registries
├── Dockerfile.original          # Original (Alibaba Cloud)
├── requirements.txt
├── config.yml
└── Jenkinsfile                  # Original Jenkins configuration
```

---

## Quick Start

### Prerequisites
- Kubernetes cluster (minikube, kind, or cloud)
- kubectl installed
- Docker Hub account

### 1. Install Tekton
```bash
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
kubectl get pods -n tekton-pipelines
```

### 2. Install SealedSecrets and Configure Secure Credentials

```bash
# Install SealedSecrets operator
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/controller.yaml

# Install kubeseal CLI (on your local machine)
# Linux: wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/kubeseal-0.26.0-linux-amd64.tar.gz
# macOS: brew install kubeseal

# Create secure namespace
kubectl create namespace tekton-prod

# Create SealedSecret (replace with your actual credentials)
kubectl create secret generic dockerhub-credentials \
  --namespace=tekton-prod \
  --from-literal=username=YOUR_DOCKERHUB_USER \
  --from-literal=password=YOUR_DOCKERHUB_TOKEN \
  --dry-run=client -o yaml | kubeseal > sealed-dockerhub-secret.yaml

# Apply the encrypted secret
kubectl apply -f sealed-dockerhub-secret.yaml
```

### 3. Apply Tekton Resources
```bash
# Apply restrictive RBAC
kubectl apply -f tekton/rbac/restricted-rbac.yaml

# Apply Tasks
kubectl apply -f tekton/tasks/

# Apply Pipeline
kubectl apply -f tekton/pipeline/public-python-pipeline.yaml
```

### 4. Edit Pipeline Parameters

Edit `tekton/pipelinerun/public-pipelinerun.yaml`:
```yaml
params:
  - name: image-name
    value: "docker.io/YOUR_USERNAME/python-app"  # Change this
```

### 5. Run Pipeline
```bash
kubectl create -n tekton-prod -f tekton/pipelinerun/public-pipelinerun.yaml
kubectl get pipelineruns -n tekton-prod -w
```

---

## Configuration Changes from Original

### Original (Enterprise/China)
```yaml
Base Image: alibaba-cloud-linux-3-registry.cn-hangzhou.cr.aliyuncs.com
Registry: ph-sw-cn-beijing.cr.volces.com
Proxy: http://100.68.169.226:3128
Pip Mirror: mirrors.aliyun.com/pypi
```

### Adapted (Public)
```yaml
Base Image: python:3.11-slim
Registry: docker.io (Docker Hub)
Proxy: None
Pip Mirror: pypi.org (standard)
```

---

## Security Implementation

### SealedSecrets
- Encrypted secrets stored directly in Git
- Cluster-specific decryption (only your cluster can decrypt)
- Eliminates plain-text credentials in version control

### RBAC Restriction
- ServiceAccount: `tekton-restricted-sa`
- Minimal permissions principle:
  - Only read specific secrets (not all)
  - Only create/delete own pods
  - No access to other namespaces
- Namespace isolation: `tekton-prod`

### Secure Task Configuration
Tasks reference secrets securely:
```yaml
env:
  - name: DOCKER_USERNAME
    valueFrom:
      secretKeyRef:
        name: dockerhub-credentials
        key: username
```

---

## Known Issues & Solutions

### OOMKilled During Docker Build

**Symptom:** Kaniko fails with out-of-memory error

**Solution:** Increase memory limits in `docker-build-public-task.yaml`:
```yaml
resources:
  limits:
    memory: "2Gi"
```

### Branch Name Error

**Note:** Original repo uses `master` branch, not `main`:
```yaml
params:
  - name: revision
    value: "master"
```

## Pipeline Stages

1. **git-clone**: Clone source repository using alpine/git
2. **python-environment-setup**: Create venv, install dependencies, compile Python
3. **python-tests-comprehensive**: Run pytest, validate config.yml, check vulnerabilities
4. **docker-build-push**: Build image with Kaniko, push to Docker Hub
5. **integration-tests**: Run container as sidecar, execute integration tests

---

## Key Differences: Jenkins vs Tekton

| Feature | Jenkins | Tekton |
|---------|---------|--------|
| Execution | Jenkins agent | Kubernetes Pods |
| Configuration | Groovy | YAML |
| Docker | Docker-in-Docker | Kaniko (daemonless) |
| Secrets | Jenkins credentials | Kubernetes SealedSecrets |
| Security | Manual credential management | RBAC + namespace isolation |
| Scaling | Manual | Native K8s autoscaling |

---

## Additional Files

- `deploy-public-tekton.sh`: Automated setup script (not used in final implementation)
- `sealed-secret.yaml`: Encrypted secret configuration
- `VOLCES-MIGRATION-GUIDE.md`: Detailed migration documentation
- `QUICKSTART.md`: Quick reference guide

---

## What Was Learned

- Tekton Task and Pipeline architecture
- Workspace management for sharing data between tasks
- Kaniko for building Docker images without Docker daemon
- SealedSecrets for GitOps-compatible credential management
- RBAC restriction for production security
- Kubernetes-native CI/CD patterns
- Migration from enterprise to public infrastructure

---

## Status

**Working:** Pipeline executes successfully  
**Secured:** Encrypted secrets and RBAC implemented  
**Tested:** Docker image builds and pushes to Docker Hub  
**Production-ready:** Secure implementation complete  

---

## Future Enhancements

Possible additions:
- Tekton Triggers for GitHub webhooks
- Automated vulnerability scanning
- Slack/email notifications
- Multi-environment support (dev/staging/prod)
- Cost optimization with resource limits

---

## Resources

- [Tekton Documentation](https://tekton.dev/docs/)
- [Kaniko Documentation](https://github.com/GoogleContainerTools/kaniko)
- [SealedSecrets GitHub](https://github.com/bitnami-labs/sealed-secrets)
- [Original Repository](https://github.com/restalion/python-jenkins-pipeline)

---

**Note:** This is a learning project demonstrating Jenkins to Tekton migration with security best practices. The original Jenkinsfile is preserved for reference. All credentials are encrypted using SealedSecrets for safe Git storage.
