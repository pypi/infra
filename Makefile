default:
	echo "What should this do?"


k8s:
	@$(MAKE) -C k8s


images:
	@$(MAKE) -C images


.PHONY: k8s images
