# OmniSurg Cloudflare Terraform: Cloudflare for SaaS (staff-web wildcard).
#
# staff-web is ONE Pages project served at the per-practice wildcard,
# *.omnisurg.app (production) and *.staging.omnisurg.app (staging), through
# Cloudflare for SaaS custom hostnames. Subdomain-based tenant resolution and
# runtime branding are unchanged; the SAME mechanism is used in both environments.
#
# Each practice subdomain is provisioned as a custom hostname at ONBOARD time by
# the provider-portal flow (runtime), so individual per-practice hostnames are not
# declared here. What IS settled in IaC (spec section 6) is the zone-level
# fallback origin every custom hostname routes to when it has no per-hostname
# origin: the staff-web Pages project's default *.pages.dev domain.
#
# Cloudflare allows exactly ONE fallback origin per zone. omnisurg.app is a single
# zone, so the PRODUCTION staff-web pages.dev is set as the zone fallback here. The
# staging staff-web wildcard rides the same Pages project through its develop
# preview alias; its fallback hostname is kept as the
# staff_web_staging_pages_fallback_hostname variable for the bootstrap runbook and
# the staging custom-hostname provisioning, and is not declared as a second
# zone-level fallback (which the API would reject).
resource "cloudflare_custom_hostname_fallback_origin" "staff_web" {
  zone_id = var.cloudflare_zone_id
  origin  = var.staff_web_pages_fallback_hostname
}
