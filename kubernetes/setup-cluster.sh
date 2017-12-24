kubectl apply -f certificate-approver/manifests
kubectl apply -f certificate-requestor/manifests
kubectl create ns vault
kubectl apply -f consul/manifests
pushd consul
./bootstrap-acls 
popd
pushd vault
export CONSUL_MANAGEMENT_TOKEN=55961ec2-3290-ab00-45e2-a73274f69022
./bootstrap-acls 
kubectl apply -f manifests/vault.yaml 
./bootstrap-vault 
export VAULT_TOKEN=55c52460-23ad-42d5-5b62-81724fe17b2f
popd
pushd vault-enrollment-controller/
kubectl apply -f manifests
./bootstrap-vault-kubernetes-auth 
popd
pushd goldfish/
./boostrap-vault-goldfish 
kubectl apply -f manifests
popd
