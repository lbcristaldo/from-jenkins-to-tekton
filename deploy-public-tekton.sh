#!/bin/bash

set -e

echo "=========================================="
echo "Public Infrastructure Tekton Setup"
echo "Migration from Jenkins (Palma's repo)"
echo "=========================================="
echo ""

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Verificar kubectl
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl no está instalado"
    exit 1
fi

print_info "Verificando conexión al cluster..."
if ! kubectl cluster-info &> /dev/null; then
    print_error "No se puede conectar al cluster de Kubernetes"
    print_info "Si no tienes un cluster, instala minikube o kind:"
    print_info "  minikube: https://minikube.sigs.k8s.io/docs/start/"
    print_info "  kind: https://kind.sigs.k8s.io/docs/user/quick-start/"
    exit 1
fi

print_info "Conectado a cluster: $(kubectl config current-context)"

# Paso 1: Instalar Tekton
print_step "Paso 1: Instalando Tekton Pipelines..."
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

print_info "Esperando a que Tekton Pipelines esté listo..."
kubectl wait --for=condition=Ready pods --all -n tekton-pipelines --timeout=300s || {
    print_warning "Timeout esperando Tekton. Puede que tome más tiempo."
}

# Paso 2: Instalar Tekton CLI (opcional)
if ! command -v tkn &> /dev/null; then
    print_warning "Tekton CLI (tkn) no está instalado"
    print_info "Para instalarlo:"
    print_info "  macOS: brew install tektoncd-cli"
    print_info "  Linux: https://github.com/tektoncd/cli#installing-tkn"
else
    print_info "Tekton CLI instalado: $(tkn version)"
fi

# Paso 3: Instalar Dashboard (opcional)
read -p "¿Deseas instalar Tekton Dashboard? (s/n): " install_dashboard
if [[ $install_dashboard == "s" ]]; then
    print_step "Instalando Tekton Dashboard..."
    kubectl apply -f https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml
    
    print_info "Para acceder al dashboard:"
    print_info "  kubectl port-forward -n tekton-pipelines svc/tekton-dashboard 9097:9097"
    print_info "  URL: http://localhost:9097"
fi

# Paso 4: Configurar credenciales
print_step "Paso 2: Configurando credenciales de container registry..."
echo ""
print_info "Opciones disponibles:"
echo "  1. Docker Hub (gratis, más popular)"
echo "  2. GitHub Container Registry (gratis, integrado con GitHub)"
echo "  3. Omitir por ahora (solo testing local)"
echo ""
read -p "Elige una opción (1/2/3): " registry_option

case $registry_option in
    1)
        print_info "Configurando Docker Hub..."
        print_info "Si no tienes cuenta, créala en: https://hub.docker.com"
        echo ""
        read -p "Docker Hub Username: " docker_username
        read -sp "Docker Hub Password: " docker_password
        echo ""
        read -p "Email: " docker_email
        
        kubectl create secret docker-registry dockerhub-credentials \
            --docker-server=docker.io \
            --docker-username="$docker_username" \
            --docker-password="$docker_password" \
            --docker-email="$docker_email" \
            -n default \
            --dry-run=client -o yaml | kubectl apply -f -
        
        print_info "Docker Hub credentials configuradas"
        print_warning "Recuerda actualizar 'image-name' en public-pipelinerun.yaml:"
        print_warning "  docker.io/$docker_username/python-app"
        ;;
    2)
        print_info "Configurando GitHub Container Registry..."
        print_info "Necesitas un Personal Access Token con permisos: write:packages"
        print_info "Créalo en: https://github.com/settings/tokens"
        echo ""
        read -p "GitHub Username: " github_username
        read -sp "GitHub Personal Access Token: " github_token
        echo ""
        read -p "Email: " github_email
        
        kubectl create secret docker-registry dockerhub-credentials \
            --docker-server=ghcr.io \
            --docker-username="$github_username" \
            --docker-password="$github_token" \
            --docker-email="$github_email" \
            -n default \
            --dry-run=client -o yaml | kubectl apply -f -
        
        print_info "GHCR credentials configuradas"
        print_warning "Recuerda actualizar 'image-name' en public-pipelinerun.yaml:"
        print_warning "  ghcr.io/$github_username/python-app"
        ;;
    3)
        print_warning "Omitiendo credenciales. Recuerda:"
        print_warning "  - No podrás hacer push de imágenes"
        print_warning "  - Los integration tests fallarán si requieren la imagen"
        ;;
    *)
        print_error "Opción inválida"
        exit 1
        ;;
esac

# Paso 5: Aplicar RBAC
print_step "Paso 3: Aplicando configuración de RBAC..."
kubectl apply -f public-secrets-setup.yaml 2>/dev/null || {
    print_warning "Archivo public-secrets-setup.yaml no encontrado"
    print_info "Creando RBAC básico..."
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tekton-pipeline-sa
  namespace: default
EOF
}

# Paso 6: Aplicar Tasks
print_step "Paso 4: Aplicando Tekton Tasks..."
for task in git-clone-task.yaml python-environment-public-task.yaml python-tests-public-task.yaml docker-build-public-task.yaml integration-tests-public-task.yaml; do
    if [ -f "$task" ]; then
        kubectl apply -f "$task"
        print_info "Aplicado: $task"
    else
        print_warning "No encontrado: $task"
    fi
done

# Paso 7: Aplicar Pipeline
print_step "Paso 5: Aplicando Tekton Pipeline..."
if [ -f "public-python-pipeline.yaml" ]; then
    kubectl apply -f public-python-pipeline.yaml
    print_info "Pipeline aplicado"
else
    print_warning "Pipeline no encontrado"
fi

# Verificar instalación
print_step "Verificando recursos creados..."
echo ""
print_info "Tasks disponibles:"
kubectl get tasks -n default 2>/dev/null || print_warning "No tasks found"
echo ""
print_info "Pipelines disponibles:"
kubectl get pipelines -n default 2>/dev/null || print_warning "No pipelines found"
echo ""

# Resumen final
print_info "=========================================="
print_info "¡Setup completado!"
print_info "=========================================="
echo ""
print_warning "IMPORTANTE: Antes de ejecutar el pipeline:"
echo ""
print_info "1. Edita 'public-pipelinerun.yaml' y cambia:"
echo "   image-name: docker.io/YOUR_USERNAME/python-app"
echo ""
print_info "2. Ejecuta el pipeline:"
echo "   kubectl create -f public-pipelinerun.yaml"
echo ""
print_info "3. Ver logs:"
if command -v tkn &> /dev/null; then
    echo "   tkn pipelinerun logs -f -L"
else
    echo "   kubectl get pipelineruns -w"
    echo "   kubectl logs -f <pod-name>"
fi
echo ""
print_info "4. Ver recursos:"
echo "   kubectl get tasks,pipelines,pipelineruns"
echo ""
if [[ $install_dashboard == "s" ]]; then
    print_info "5. Dashboard:"
    echo "   kubectl port-forward -n tekton-pipelines svc/tekton-dashboard 9097:9097"
    echo "   http://localhost:9097"
    echo ""
fi
print_info "¡Listo para migrar de Jenkins a Tekton!"
