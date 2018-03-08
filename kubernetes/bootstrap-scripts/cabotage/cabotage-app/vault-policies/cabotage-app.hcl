path "cabotage-app-transit/*" {
  capabilities = ["create", "read", "update", "list"]
}

path "cabotage-ca/issue/cabotage-cabotage-app" {
  capabilities = ["create", "update"]
}

path "cabotage-consul/creds/cabotage-cabotage-app" {
  capabilities = ["read"]
}

path "cabotage-postgresql/roles/cabotage-app" {
  capabilities = ["read"]
}

path "cabotage-secrets/automation" {
  capabilities = ["create", "update", "delete", "list"]
}
