provider "sigsci" {
  # if i dont add this it errors: Provider configuration not present
  alias      = "firewall"
  corp       = "python"
  email      = "infrastructure-staff@python.org"
  auth_token = var.ngwaf_token
}

resource "fastly_service_dictionary_items" "edge_security_dictionary_items" {
  count         = var.activate_ngwaf_service ? 1 : 0
  service_id    = fastly_service_vcl.pypi.id
  dictionary_id = one([for d in fastly_service_vcl.pypi.dictionary : d.dictionary_id if d.name == var.edge_security_dictionary])
  items = {
    Enabled : "100"
  }
}

resource "fastly_service_dynamic_snippet_content" "ngwaf_config_snippets" {
  for_each        = var.activate_ngwaf_service ? toset(["init", "miss", "pass", "deliver"]) : []
  service_id      = fastly_service_vcl.pypi.id
  snippet_id      = one([for d in fastly_service_vcl.pypi.dynamicsnippet : d.snippet_id if d.name == "ngwaf_config_${each.key}"])
  content         = "### Terraform managed ngwaf_config_${each.key}"
  manage_snippets = false
}

# NGWAF Edge Deployment on SignalSciences.net
resource "sigsci_edge_deployment" "ngwaf_edge_site_service" {
  count           = var.activate_ngwaf_service ? 1 : 0
  provider        = sigsci.firewall
  site_short_name = var.ngwaf_site_name
}

resource "sigsci_edge_deployment_service" "ngwaf_edge_service_link" {
  count            = var.activate_ngwaf_service ? 1 : 0
  provider         = sigsci.firewall
  site_short_name  = var.ngwaf_site_name
  fastly_sid       = fastly_service_vcl.pypi.id
  activate_version = var.activate_ngwaf_service
  percent_enabled  = 100
  depends_on = [
    sigsci_edge_deployment.ngwaf_edge_site_service,
    fastly_service_vcl.pypi,
    fastly_service_dictionary_items.edge_security_dictionary_items,
    fastly_service_dynamic_snippet_content.ngwaf_config_snippets,
  ]
}

resource "sigsci_edge_deployment_service_backend" "ngwaf_edge_service_backend_sync" {
  count                             = var.activate_ngwaf_service ? 1 : 0
  provider                          = sigsci.firewall
  site_short_name                   = var.ngwaf_site_name
  fastly_sid                        = fastly_service_vcl.pypi.id
  fastly_service_vcl_active_version = fastly_service_vcl.pypi.active_version
  depends_on = [
    sigsci_edge_deployment_service.ngwaf_edge_service_link,
  ]
}
