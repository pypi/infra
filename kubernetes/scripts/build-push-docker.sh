eval $(minikube docker-env)
docker build -t gcr.io/the-psf/"$(basename "$(pwd)")":v1.0.0a1 .
gcloud docker -- push gcr.io/the-psf/"$(basename "$(pwd)")":v1.0.0a1
