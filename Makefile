ROOT_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

default:
	echo "What should this do?"


k8s:
	@$(MAKE) -C k8s

terraform:
	cd terraform; terraform init
	cd terraform; terraform plan


.PHONY: k8s terraform
