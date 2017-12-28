minikube start \
  --memory=4096 \
  --kubernetes-version v1.8.4 \
  --bootstrapper kubeadm \
  --docker-opt="default-ulimit=nofile=102400:102400" \
  --extra-config=controller-manager.cluster-signing-cert-file="/var/lib/localkube/certs/ca.crt" \
  --extra-config=controller-manager.cluster-signing-key-file="/var/lib/localkube/certs/ca.key"

minikube addons enable ingress
