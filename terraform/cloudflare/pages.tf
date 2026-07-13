# OmniSurg Cloudflare Terraform: Cloudflare Pages projects.
#
# One Pages project per web app. Production branch is `main`. The build is driven
# from each repo's GitHub Actions via Wrangler (NOT the Pages Git integration), so
# the same CI gate controls the deploy and the environment-specific VITE_* values
# come from the GitHub Environment (spec section 6). Because deploys are by
# Wrangler, no git-integration `source` block is declared here; the `develop`
# branch publishes the staging preview alias through the Wrangler `--branch
# develop` deploy in CI, so the preview branch is controlled at deploy time. What
# this IaC settles is the project itself and its production branch.

# staff-web: served at the per-practice wildcard through Cloudflare for SaaS
# (see forsaas.tf). One project, both environments.
resource "cloudflare_pages_project" "staff_web" {
  account_id        = var.cloudflare_account_id
  name              = "staff-web"
  production_branch = "main"
}

# provider-portal: served at the fixed admin[.staging] custom domains (below).
resource "cloudflare_pages_project" "provider_portal" {
  account_id        = var.cloudflare_account_id
  name              = "provider-portal"
  production_branch = "main"
}

# provider-portal fixed custom domains. The production domain resolves the main
# branch; the staging domain resolves the develop preview alias. Adding a custom
# domain to the Pages project provisions the CNAME automatically, so no explicit
# DNS record is declared for these hosts.
resource "cloudflare_pages_domain" "provider_portal_prod" {
  account_id   = var.cloudflare_account_id
  project_name = cloudflare_pages_project.provider_portal.name
  domain       = "admin.${var.root_domain}"
}

resource "cloudflare_pages_domain" "provider_portal_staging" {
  account_id   = var.cloudflare_account_id
  project_name = cloudflare_pages_project.provider_portal.name
  domain       = "admin.staging.${var.root_domain}"
}
