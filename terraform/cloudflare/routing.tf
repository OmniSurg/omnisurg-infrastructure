# OmniSurg Cloudflare Terraform: origin routing and SSL.
#
# Cloudflare connects to a PROXIED HTTPS origin only on a fixed set of ports
# (443, 2053, 2083, 2087, 2096, 8443). The two OmniSurg api origins listen on
# different ports so the two isolated VPS stacks coexist: production Traefik on
# :8443, staging Traefik on :2053. An Origin Rule (the http_request_origin phase)
# overrides the origin port per api host so Cloudflare dials the right one.

resource "cloudflare_ruleset" "api_origin_ports" {
  zone_id     = var.cloudflare_zone_id
  name        = "OmniSurg api origin ports"
  description = "Pin each api host to the VPS Traefik TLS port it listens on."
  kind        = "zone"
  phase       = "http_request_origin"

  # Production: api.omnisurg.app -> VPS Traefik :8443.
  rules {
    ref         = "api_prod_origin_port"
    description = "Route api.omnisurg.app to the production Traefik TLS port."
    expression  = "(http.host eq \"api.${var.root_domain}\")"
    action      = "route"
    enabled     = true
    action_parameters {
      origin {
        port = var.prod_origin_port
      }
    }
  }

  # Staging: api.staging.omnisurg.app -> VPS Traefik :2053.
  rules {
    ref         = "api_staging_origin_port"
    description = "Route api.staging.omnisurg.app to the staging Traefik TLS port."
    expression  = "(http.host eq \"api.staging.${var.root_domain}\")"
    action      = "route"
    enabled     = true
    action_parameters {
      origin {
        port = var.staging_origin_port
      }
    }
  }
}

# SSL mode Full (strict) for the zone. Cloudflare validates the origin
# certificate on the connection to the VPS, so a Cloudflare Origin CA cert must be
# present on the VPS for each api host (spec section 3.1). Strict is applied at
# the zone level; this is safe because the only origin the zone reaches is the VPS
# api host. The web apps are Cloudflare Pages, served with Cloudflare-managed edge
# certificates, so a strict zone posture never breaks them.
resource "cloudflare_zone_settings_override" "omnisurg" {
  zone_id = var.cloudflare_zone_id

  settings {
    ssl = "strict"
  }
}
