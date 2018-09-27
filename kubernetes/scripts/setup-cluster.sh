#!/bin/bash

echo "not quite ready for direct execution yet..."
exit 1

./scripts/start-minikube
./scripts/pull-private
kubectl apply -f manifests/kube-system/certificate-approver
kubectl apply -f manifests/kube-system/certificate-requestor
kubectl apply -f manifests/cabotage/00-namespace.yml
kubectl apply -f manifests/cabotage/consul
unset CONSUL_MANAGEMENT_TOKEN
./bootstrap-scripts/cabotage/consul/bootstrap-acls
export CONSUL_MANAGEMENT_TOKEN=2dd53a07-1c6c-8e64-8c9e-50f273e25a1f
./bootstrap-scripts/cabotage/vault/bootstrap-acls
kubectl apply -f manifests/cabotage/vault
unset VAULT_TOKEN
./bootstrap-scripts/cabotage/vault/bootstrap-vault
export VAULT_TOKEN=69f5a390-a444-abe4-605f-5a4831140588
./bootstrap-scripts/cabotage/enrollment-controller/bootstrap-vault-kubernetes-auth
./bootstrap-scripts/cabotage/enrollment-controller/bootstrap-vault-ca-minikube
kubectl apply -f manifests/cabotage/enrollment-controller
./bootstrap-scripts/cabotage/goldfish/boostrap-vault-goldfish
kubectl apply -f manifests/cabotage/goldfish
