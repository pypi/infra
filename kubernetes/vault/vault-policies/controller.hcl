path "auth/kubernetes/role/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secrets/automation/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/policy/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
