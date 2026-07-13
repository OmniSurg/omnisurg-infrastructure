# OmniSurg Cloudflare Terraform: DNS records.
#
# ONLY the two BFF `api.*` hosts point at the VPS, and both are PROXIED (orange
# cloud) so Cloudflare terminates the public TLS and reaches the origin over the
# port pinned by the Origin Rule in routing.tf.
#
# admin.omnisurg.app / admin.staging.omnisurg.app and the per-practice wildcards
# *.omnisurg.app / *.staging.omnisurg.app are served by Cloudflare Pages and
# Cloudflare for SaaS (see pages.tf and forsaas.tf); they are NOT VPS records and
# are intentionally not declared here.

# Production BFF: api.omnisurg.app proxied to the VPS origin.
resource "cloudflare_record" "api_prod" {
  zone_id = var.cloudflare_zone_id
  name    = "api"
  type    = "A"
  content = var.vps_host
  # Proxied so Cloudflare fronts the origin (Full strict TLS + the origin-port rule).
  proxied = true
  # TTL is forced to automatic (1) for a proxied record.
  ttl     = 1
  comment = "OmniSurg production BFF origin (VPS Traefik)."
}

# Staging BFF: api.staging.omnisurg.app proxied to the VPS origin.
resource "cloudflare_record" "api_staging" {
  zone_id = var.cloudflare_zone_id
  name    = "api.staging"
  type    = "A"
  content = var.vps_host
  proxied = true
  ttl     = 1
  comment = "OmniSurg staging BFF origin (VPS Traefik)."
}
