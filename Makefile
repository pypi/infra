ROOT_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

default:
	echo "What should this do?"


k8s:
	@$(MAKE) -C k8s

lambda-deployer.zip:
	docker build -t lambda-deployer-build lambda-deployer
	docker run --rm -v $(ROOT_DIR)/lambda-deployer:/usr/local/src/lambda-deployer -it lambda-deployer-build \
		cargo build --release --target x86_64-unknown-linux-musl
	zip -j lambda-deployer/target/x86_64-unknown-linux-musl/release/lambda-deployer.zip \
			 lambda-deployer/target/x86_64-unknown-linux-musl/release/bootstrap

terraform: lambda-deployer.zip
	cd terraform; terraform init
	cd terraform; terraform apply


.PHONY: k8s terraform lambda-deployer.zip
