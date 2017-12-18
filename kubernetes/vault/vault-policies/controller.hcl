path "auth/kubernetes/role/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secrets/automation/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "consul/roles" {
  capabilities = ["list"]
}

path "consul/roles/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "consul/creds/*" {
  capabilities = ["read"]
}

path "sys/policy/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
