# OmniSurg Cloudflare Terraform: input variables.
#
# EVERY secret and account-specific id is a variable. No token, account id, zone
# id, or origin host is ever hard-coded in a committed file. Real values live in a
# gitignored terraform.tfvars at apply time; terraform.tfvars.example carries only
# names and placeholders.

# ---- Cloudflare account credentials ----

variable "cloudflare_api_token" {
  description = "Cloudflare API token scoped to DNS edit, Pages, and Cloudflare for SaaS custom hostnames. Supplied at apply time; never committed."
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account id that owns the omnisurg.app zone and the Pages projects."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone id for omnisurg.app."
  type        = string
}

# ---- Zone ----

variable "root_domain" {
  description = "The apex domain served by this zone."
  type        = string
  default     = "omnisurg.app"
}

# ---- VPS origin ----

variable "vps_host" {
  description = "The VPS origin the proxied api.* records resolve to (the value of the A records). Supplied at apply time from the gitignored tfvars so the literal origin address never lives in a committed file."
  type        = string
  sensitive   = true
}

variable "prod_origin_port" {
  description = "The VPS Traefik TLS port for the PRODUCTION api origin. Cloudflare only connects to a proxied HTTPS origin on 443/2053/2083/2087/2096/8443; production Traefik listens on 8443."
  type        = number
  default     = 8443

  validation {
    condition     = contains([443, 2053, 2083, 2087, 2096, 8443], var.prod_origin_port)
    error_message = "prod_origin_port must be a Cloudflare-supported proxied-origin HTTPS port (443, 2053, 2083, 2087, 2096, or 8443)."
  }
}

variable "staging_origin_port" {
  description = "The VPS Traefik TLS port for the STAGING api origin. Staging Traefik listens on 2053, another Cloudflare-supported proxied-origin HTTPS port, so production (:8443) and staging (:2053) stay isolated."
  type        = number
  default     = 2053

  validation {
    condition     = contains([443, 2053, 2083, 2087, 2096, 8443], var.staging_origin_port)
    error_message = "staging_origin_port must be a Cloudflare-supported proxied-origin HTTPS port (443, 2053, 2083, 2087, 2096, or 8443)."
  }
}

# ---- Cloudflare Pages: staff-web for-SaaS fallback origins ----
# The staff-web per-practice wildcard is served by Cloudflare for SaaS. Every
# custom hostname routes to a fallback origin when no per-hostname origin is set;
# that fallback is the staff-web Pages project's default *.pages.dev domain. It is
# a hostname (no scheme), for example "staff-web.pages.dev".

variable "staff_web_pages_fallback_hostname" {
  description = "The PRODUCTION staff-web Pages project default *.pages.dev hostname, used as the Cloudflare for SaaS zone fallback origin for the *.omnisurg.app wildcard."
  type        = string
}

variable "staff_web_staging_pages_fallback_hostname" {
  description = "The STAGING (preview) staff-web Pages alias *.pages.dev hostname, used as the fallback origin for the *.staging.omnisurg.app wildcard. Kept as a variable for the bootstrap runbook and the staging custom-hostname provisioning; Cloudflare allows one fallback origin per zone, so only the production value is set at the zone level here."
  type        = string
}
