eval $(minikube docker-env)
docker pull gcr.io/the-psf/certificate-requestor:v1.0.0a1
docker pull gcr.io/the-psf/certificate-approver:v1.0.0a1
docker pull gcr.io/the-psf/vault-enrollment-controller:v1.0.0a1
docker pull gcr.io/the-psf/secure-sidecar:v1.0.0a1
docker pull gcr.io/the-psf/goldfish:v1.0.0a1
