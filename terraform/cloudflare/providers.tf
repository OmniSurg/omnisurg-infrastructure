# OmniSurg Cloudflare Terraform: provider and version pins.
#
# This configuration is VALIDATE-ONLY in this plan (plan-aa, Chunk 2). Nothing is
# applied here: it is authored, `terraform validate` and `terraform fmt -check`
# gate it, and the real apply happens during the gated bootstrap (plan-ab) once
# the user supplies the Cloudflare API token and the account/zone ids.
#
# It provisions, for BOTH environments, the Cloudflare edge in front of OmniSurg:
#   - the two proxied `api.*` DNS records that reach the VPS Traefik origin,
#   - an Origin Rule that pins each api host to the VPS TLS port it listens on
#     (production :8443, staging :2053, both Cloudflare-supported proxied-origin
#     HTTPS ports),
#   - zone SSL mode Full (strict) so Cloudflare validates the VPS Origin CA cert,
#   - the two Cloudflare Pages projects (staff-web, provider-portal),
#   - the provider-portal fixed custom domains (admin[.staging].omnisurg.app), and
#   - the staff-web Cloudflare for SaaS fallback origin for the per-practice
#     wildcard.
#
# The staff web and provider portal are served entirely from Cloudflare Pages and
# never touch the VPS; only `api.*` is proxied to the origin.

terraform {
  # Terraform 1.9+ (the repo pins 1.9; the local toolchain is newer and compatible).
  required_version = ">= 1.9"

  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
      # Pinned to the 4.x line. `terraform validate` checks the config against
      # this provider's real schema, so the pin is load-bearing.
      version = "~> 4.52"
    }
  }

  # No remote backend block: this config is validate-only and is never applied
  # from CI, so `terraform init -backend=false` initializes it fully offline.
  # When the deploy slice goes live (plan-ab), a remote backend (Cloudflare R2 via
  # the S3-compatible backend) can be added here; state is never committed.
}

# The API token is the only provider credential. It is supplied at apply time
# from a gitignored terraform.tfvars (or a CI secret), never committed.
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
