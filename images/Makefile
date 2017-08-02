CONSUL_VERSION = 0.9.0


all: consul

consul:
	gcloud docker -- pull gcr.io/the-psf/consul -a
	docker build -t gcr.io/the-psf/consul:v$(CONSUL_VERSION) --build-arg CONSUL_VERSION=$(CONSUL_VERSION) consul/
	gcloud docker -- push gcr.io/the-psf/consul:v$(CONSUL_VERSION)

.PHONY: consul
