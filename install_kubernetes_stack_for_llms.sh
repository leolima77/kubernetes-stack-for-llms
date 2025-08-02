#!/bin/bash

# run this command
#chmod +x install_kubernetes_stack_for_llms.sh

# update and intall dependencies
export DEBIAN_FRONTEND=noninteractive
apt update && apt install -y apt-transport-https ca-certificates curl software-properties-common

# update package list
apt-get update

# install snapd if not installed
if ! command -v snap &> /dev/null
then
    apt-get install -y snapd
fi

# install MicroK8s with classic confinement
snap install microk8s --classic

# configure kubectl to the final user
mkdir -p $HOME/.kube
microk8s config > $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# alias to use microk8s kubectl as kubectl
echo "alias kubectl='microk8s kubectl'" >> ~/.bashrc
source ~/.bashrc

# create cattle-system namespace
microk8s kubectl create namespace cattle-system

# install cert-manager
microk8s kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.5.3/cert-manager.yaml

# waiting initialization of cert-manager pods
echo "Waiting initialization of cert-manager pods..."
sleep 60

# check if cert-manager pods are running
microk8s kubectl get pods --namespace cert-manager

# install the NVIDIA GPU Operator
microk8s kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
spec:
  restartPolicy: Never
  containers:
    - name: cuda-container
      image: nvidia/cuda:12.2.0-base-ubuntu22.04
      command: ["nvidia-smi"]
      resources:
        limits:
          nvidia.com/gpu: 1
EOF

# install helm
echo "=== Instalando Helm ==="
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version

# add the Rancher Helm repository
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update

# install rancher with Helm. Replace "rancher.domain.com" with your domain pointing to the server IP.
helm install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --set hostname="rancher.domain.com" \ 
  --set ingress.enabled=false \
  --set service.type=NodePort \
  --set replicas=1 \
  --set ports.https.nodePort=7744 \
  --set ports.http.nodePort=7745 \
  --set bootstrapPassword="{your_bootstrap_password}" \

# add metrics-server Helm repository
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --create-namespace \
  --set "args={--kubelet-insecure-tls,--kubelet-preferred-address-types=InternalIP}"

# setup NVIDIA Container Toolkit repository
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor --batch --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# update the package list
apt-get update
apt-get install -y nvidia-container-toolkit

# enable the GPU operator
microk8s enable gpu
microk8s kubectl logs -n gpu-operator-resources -l app=nvidia-operator-validator -c nvidia-operator-validator

# check if NVIDIA runtime is configured correctly
ctr --namespace k8s.io plugins ls | grep nvidia

# install NVIDIA drivers
apt-get install -y ubuntu-drivers-common
add-apt-repository -y ppa:graphics-drivers/ppa
ubuntu-drivers autoinstall

# check nvidia driver installation
nvidia-smi

# describe kubernetes node 
microk8s kubectl describe node $(hostname)

# creates the NVIDIA Device Plugin DaemonSet
microk8s kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.12.3/nvidia-device-plugin.yml

# add local-path storageclass
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

# install ollama
curl -fsSL https://ollama.com/install.sh | sh
ollama --version
ollama pull gemma3:27b

# setting up firewall rules to allow traffic on port 11434
ufw allow 11434/tcp

echo "Access rancher at https://rancher.domain.com:7744"
# check if rancher is running
microk8s kubectl get services --all-namespaces | grep rancher

# create namespace for postgres
microk8s kubectl create namespace postgres --dry-run=client -o yaml | microk8s kubectl apply -f -

# add Bitnami Helm repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# install PostgreSQL with Helm
helm upgrade --install ai-knowledge bitnami/postgresql \
  --namespace postgres \
  --set auth.postgresPassword={your_postgres_password} \
  --set auth.database=ai-knowledge \
  --set primary.service.type=NodePort \
  --set primary.service.nodePorts.postgresql=32092 \
  --set primary.containerPorts.postgresql=5432 \
  --set primary.resources.requests.memory=2Gi \
  --set primary.resources.requests.cpu=1 \
  --set primary.resources.limits.memory=5Gi \
  --set primary.resources.limits.cpu=3 \
  --set primary.persistence.enabled=true \
  --set primary.persistence.size=50Gi

# wait for PostgreSQL pod to be ready
microk8s kubectl wait --namespace postgres \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=postgresql \
  --timeout=180s

# get pod name of PostgreSQL
POD_NAME=$(microk8s kubectl get pods -n postgres -l app.kubernetes.io/name=postgresql -o jsonpath="{.items[0].metadata.name}")

# setting up the vector extension in PostgreSQL
microk8s kubectl exec -n postgres $POD_NAME -- bash -c "PGPASSWORD={your_postgres_password} psql -U postgres -d ai-knowledge -c 'CREATE EXTENSION IF NOT EXISTS vector;'"

# testing Ollama with a sample prompt
curl -X POST "http://localhost:11434/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma3:27b",
    "messages": [
      { "role": "system", "content": "Você é um assistente útil." },
      { "role": "user", "content": "Olá, como vai?" }
    ]
  }'

# reboot system
reboot
