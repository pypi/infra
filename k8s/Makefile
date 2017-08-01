all: cluster-admins kcm vault

cluster-admins:
	kubectl apply -f cluster-admins

kcm:
	kubectl apply -f kcm

vault:
	kubectl apply -f vault

.PHONY: all cluster-admins kcm vault
