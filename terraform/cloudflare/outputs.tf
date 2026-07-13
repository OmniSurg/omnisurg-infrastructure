# OmniSurg Cloudflare Terraform: outputs.
#
# Convenience references for the bootstrap runbook and any composing config.
# No secret values are emitted (the api token and vps_host are never output).

output "api_prod_hostname" {
  description = "The production BFF hostname proxied to the VPS origin."
  value       = cloudflare_record.api_prod.hostname
}

output "api_staging_hostname" {
  description = "The staging BFF hostname proxied to the VPS origin."
  value       = cloudflare_record.api_staging.hostname
}

output "staff_web_pages_project" {
  description = "The staff-web Cloudflare Pages project name."
  value       = cloudflare_pages_project.staff_web.name
}

output "provider_portal_pages_project" {
  description = "The provider-portal Cloudflare Pages project name."
  value       = cloudflare_pages_project.provider_portal.name
}

output "provider_portal_domains" {
  description = "The provider-portal fixed custom domains (production and staging)."
  value = [
    cloudflare_pages_domain.provider_portal_prod.domain,
    cloudflare_pages_domain.provider_portal_staging.domain,
  ]
}
