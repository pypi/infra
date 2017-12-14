minikube start \
  --memory=4096 \
  --kubernetes-version v1.8.4 \
  --bootstrapper kubeadm \
  --extra-config=controller-manager.cluster-signing-cert-file="/var/lib/localkube/certs/ca.crt" \
  --extra-config=controller-manager.cluster-signing-key-file="/var/lib/localkube/certs/ca.key"
