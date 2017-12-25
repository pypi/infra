path "auth/kubernetes/role/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "cabotage-secrets/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "cabotage-consul/roles" {
  capabilities = ["list"]
}

path "cabotage-consul/roles/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "cabotage-consul/creds/*" {
  capabilities = ["read"]
}

path "sys/policy/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "cabotage-ca/roles" {
  capabilities = ["list"]
}

path "cabotage-ca/roles/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "cabotage-ca/issue/*" {
  capabilities = ["create", "update"]
}
