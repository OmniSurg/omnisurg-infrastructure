#!/bin/sh
# render-env.sh: render the per-service, least-privilege env files for a deploy
# environment from its single deploy/<env>/.env.
#
# Usage: deploy/render-env.sh <production|staging> [OUT_DIR]
#
# Run on the VPS at bootstrap (and on every deploy that changes secrets). It reads
# deploy/<env>/.env (gitignored; the operator fills it from .env.example) and
# writes one env file per container under OUT_DIR (default /opt/omnisurg/env for
# production, /opt/omnisurg-staging/env for staging), each file mode 0600.
#
# LEAST PRIVILEGE: every service file carries ONLY the secrets that service needs.
# No app container ever holds another service's database password. Postgres is the
# one container that holds all 12 role passwords (it creates the roles at init).
#
# Which keys each service receives:
#   postgres.env      POSTGRES_USER/PASSWORD/DB + the 12 per-service role passwords
#   redis.env         REDIS_PASSWORD
#   identity.env      DB DSN, JWT, KEK, INTERNAL_API_KEY, [Sentry]
#   tenant.env        DB DSN, JWT, [Sentry]
#   patient.env       DB DSN, JWT, KEK, INTERNAL_API_KEY, [Sentry]
#   clinical.env      DB DSN, JWT, INTERNAL_API_KEY, [Sentry]
#   referral.env      DB DSN, JWT, INTERNAL_API_KEY, [Sentry]
#   billing.env       DB DSN, JWT, INTERNAL_API_KEY, [Sentry]
#   payment.env       DB DSN, JWT, [Sentry]
#   claims.env        DB DSN, JWT, [Sentry]
#   notification.env  DB DSN, JWT, INTERNAL_API_KEY, AFROSOFT_BASE_URL, AFROSOFT_API_KEY, [Sentry]
#   scheduling.env    DB DSN, JWT, INTERNAL_API_KEY, [Sentry]
#   audit.env         DB DSN, JWT, [Sentry]
#   currency.env      DB DSN, JWT, REDIS_PASSWORD, ZIMRATE_URL, [Sentry]
#   admin-bff.env     JWT, R2 credentials, [Sentry]   (no database of its own)
#
# The host-level GHCR_READ_TOKEN is NOT rendered into any service file: it is used
# once by `docker login ghcr.io` at bootstrap and never handed to a container.
set -eu

ENVIRONMENT="${1:-}"
case "$ENVIRONMENT" in
  production) DEFAULT_OUT="/opt/omnisurg/env" ;;
  staging)    DEFAULT_OUT="/opt/omnisurg-staging/env" ;;
  *) echo "Usage: deploy/render-env.sh <production|staging> [OUT_DIR]" >&2; exit 2 ;;
esac

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENV_FILE="$SCRIPT_DIR/$ENVIRONMENT/.env"
OUT_DIR="${2:-${OUT_DIR:-$DEFAULT_OUT}}"

if [ ! -f "$ENV_FILE" ]; then
  echo "render-env: $ENV_FILE not found (copy $ENVIRONMENT/.env.example to $ENVIRONMENT/.env and fill it)" >&2
  exit 1
fi

# Load the environment definition (KEY=value lines).
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

require() { # require VARNAME
  eval "v=\${$1:-}"
  if [ -z "${v:-}" ]; then
    echo "render-env: required variable $1 is empty in $ENV_FILE" >&2
    exit 1
  fi
}

require OMNISURG_JWT_SECRET
require OMNISURG_KEK_BASE64

mkdir -p "$OUT_DIR"
umask 077   # secrets: files are created owner read/write only

dsn() { # dsn <svc> <password>
  printf 'postgres://omnisurg_%s:%s@postgres:5432/omnisurg_%s?sslmode=disable' "$1" "$2" "$1"
}

emit() { # emit KEY VALUE  -> print KEY=VALUE only when VALUE is non-empty
  if [ -n "${2:-}" ]; then printf '%s=%s\n' "$1" "$2"; fi
}

# ---- postgres.env: superuser + the 12 role passwords (init.sh reads these) ----
{
  printf 'POSTGRES_USER=%s\n' "${POSTGRES_USER:-omnisurg}"
  printf 'POSTGRES_PASSWORD=%s\n' "$POSTGRES_PASSWORD"
  printf 'POSTGRES_DB=%s\n' "${POSTGRES_DB:-omnisurg_meta}"
  printf 'OMNISURG_IDENTITY_DB_PASSWORD=%s\n' "$OMNISURG_IDENTITY_DB_PASSWORD"
  printf 'OMNISURG_TENANT_DB_PASSWORD=%s\n' "$OMNISURG_TENANT_DB_PASSWORD"
  printf 'OMNISURG_PATIENT_DB_PASSWORD=%s\n' "$OMNISURG_PATIENT_DB_PASSWORD"
  printf 'OMNISURG_CLINICAL_DB_PASSWORD=%s\n' "$OMNISURG_CLINICAL_DB_PASSWORD"
  printf 'OMNISURG_REFERRAL_DB_PASSWORD=%s\n' "$OMNISURG_REFERRAL_DB_PASSWORD"
  printf 'OMNISURG_BILLING_DB_PASSWORD=%s\n' "$OMNISURG_BILLING_DB_PASSWORD"
  printf 'OMNISURG_PAYMENT_DB_PASSWORD=%s\n' "$OMNISURG_PAYMENT_DB_PASSWORD"
  printf 'OMNISURG_CLAIMS_DB_PASSWORD=%s\n' "$OMNISURG_CLAIMS_DB_PASSWORD"
  printf 'OMNISURG_NOTIFICATION_DB_PASSWORD=%s\n' "$OMNISURG_NOTIFICATION_DB_PASSWORD"
  printf 'OMNISURG_SCHEDULING_DB_PASSWORD=%s\n' "$OMNISURG_SCHEDULING_DB_PASSWORD"
  printf 'OMNISURG_AUDIT_DB_PASSWORD=%s\n' "$OMNISURG_AUDIT_DB_PASSWORD"
  printf 'OMNISURG_CURRENCY_DB_PASSWORD=%s\n' "$OMNISURG_CURRENCY_DB_PASSWORD"
} > "$OUT_DIR/postgres.env"

# ---- redis.env ----
{
  printf 'REDIS_PASSWORD=%s\n' "$OMNISURG_REDIS_PASSWORD"
} > "$OUT_DIR/redis.env"

# ---- per-service files (JWT everywhere; DB DSN for the 12 stateful services) ----
{
  printf 'OMNISURG_DATABASE_URL=%s\n' "$(dsn identity "$OMNISURG_IDENTITY_DB_PASSWORD")"
  printf 'OMNISURG_JWT_SECRET=%s\n' "$OMNISURG_JWT_SECRET"
  printf 'OMNISURG_KEK_BASE64=%s\n' "$OMNISURG_KEK_BASE64"
  printf 'OMNISURG_INTERNAL_API_KEY=%s\n' "$OMNISURG_INTERNAL_API_KEY"
  emit OMNISURG_SENTRY_DSN "${OMNISURG_IDENTITY_SENTRY_DSN:-}"
} > "$OUT_DIR/identity.env"

{
  printf 'OMNISURG_DATABASE_URL=%s\n' "$(dsn tenant "$OMNISURG_TENANT_DB_PASSWORD")"
  printf 'OMNISURG_JWT_SECRET=%s\n' "$OMNISURG_JWT_SECRET"
  emit OMNISURG_SENTRY_DSN "${OMNISURG_TENANT_SENTRY_DSN:-}"
} > "$OUT_DIR/tenant.env"

{
  printf 'OMNISURG_DATABASE_URL=%s\n' "$(dsn patient "$OMNISURG_PATIENT_DB_PASSWORD")"
  printf 'OMNISURG_JWT_SECRET=%s\n' "$OMNISURG_JWT_SECRET"
  printf 'OMNISURG_KEK_BASE64=%s\n' "$OMNISURG_KEK_BASE64"
  printf 'OMNISURG_INTERNAL_API_KEY=%s\n' "$OMNISURG_INTERNAL_API_KEY"
  emit OMNISURG_SENTRY_DSN "${OMNISURG_PATIENT_SENTRY_DSN:-}"
} > "$OUT_DIR/patient.env"

{
  printf 'OMNISURG_DATABASE_URL=%s\n' "$(dsn clinical "$OMNISURG_CLINICAL_DB_PASSWORD")"
  printf 'OMNISURG_JWT_SECRET=%s\n' "$OMNISURG_JWT_SECRET"
  printf 'OMNISURG_INTERNAL_API_KEY=%s\n' "$OMNISURG_INTERNAL_API_KEY"
  emit OMNISURG_SENTRY_DSN "${OMNISURG_CLINICAL_SENTRY_DSN:-}"
} > "$OUT_DIR/clinical.env"

{
  printf 'OMNISURG_DATABASE_URL=%s\n' "$(dsn referral "$OMNISURG_REFERRAL_DB_PASSWORD")"
  printf 'OMNISURG_JWT_SECRET=%s\n' "$OMNISURG_JWT_SECRET"
  printf 'OMNISURG_INTERNAL_API_KEY=%s\n' "$OMNISURG_INTERNAL_API_KEY"
  emit OMNISURG_SENTRY_DSN "${OMNISURG_REFERRAL_SENTRY_DSN:-}"
} > "$OUT_DIR/referral.env"

{
  printf 'OMNISURG_DATABASE_URL=%s\n' "$(dsn billing "$OMNISURG_BILLING_DB_PASSWORD")"
  printf 'OMNISURG_JWT_SECRET=%s\n' "$OMNISURG_JWT_SECRET"
  printf 'OMNISURG_INTERNAL_API_KEY=%s\n' "$OMNISURG_INTERNAL_API_KEY"
  emit OMNISURG_SENTRY_DSN "${OMNISURG_BILLING_SENTRY_DSN:-}"
} > "$OUT_DIR/billing.env"

{
  printf 'OMNISURG_DATABASE_URL=%s\n' "$(dsn payment "$OMNISURG_PAYMENT_DB_PASSWORD")"
  printf 'OMNISURG_JWT_SECRET=%s\n' "$OMNISURG_JWT_SECRET"
  emit OMNISURG_SENTRY_DSN "${OMNISURG_PAYMENT_SENTRY_DSN:-}"
} > "$OUT_DIR/payment.env"

{
  printf 'OMNISURG_DATABASE_URL=%s\n' "$(dsn claims "$OMNISURG_CLAIMS_DB_PASSWORD")"
  printf 'OMNISURG_JWT_SECRET=%s\n' "$OMNISURG_JWT_SECRET"
  emit OMNISURG_SENTRY_DSN "${OMNISURG_CLAIMS_SENTRY_DSN:-}"
} > "$OUT_DIR/claims.env"

{
  printf 'OMNISURG_DATABASE_URL=%s\n' "$(dsn notification "$OMNISURG_NOTIFICATION_DB_PASSWORD")"
  printf 'OMNISURG_JWT_SECRET=%s\n' "$OMNISURG_JWT_SECRET"
  printf 'OMNISURG_INTERNAL_API_KEY=%s\n' "$OMNISURG_INTERNAL_API_KEY"
  printf 'OMNISURG_AFROSOFT_BASE_URL=%s\n' "$OMNISURG_AFROSOFT_BASE_URL"
  printf 'OMNISURG_AFROSOFT_API_KEY=%s\n' "$OMNISURG_AFROSOFT_API_KEY"
  emit OMNISURG_SENTRY_DSN "${OMNISURG_NOTIFICATION_SENTRY_DSN:-}"
} > "$OUT_DIR/notification.env"

{
  printf 'OMNISURG_DATABASE_URL=%s\n' "$(dsn scheduling "$OMNISURG_SCHEDULING_DB_PASSWORD")"
  printf 'OMNISURG_JWT_SECRET=%s\n' "$OMNISURG_JWT_SECRET"
  printf 'OMNISURG_INTERNAL_API_KEY=%s\n' "$OMNISURG_INTERNAL_API_KEY"
  emit OMNISURG_SENTRY_DSN "${OMNISURG_SCHEDULING_SENTRY_DSN:-}"
} > "$OUT_DIR/scheduling.env"

{
  printf 'OMNISURG_DATABASE_URL=%s\n' "$(dsn audit "$OMNISURG_AUDIT_DB_PASSWORD")"
  printf 'OMNISURG_JWT_SECRET=%s\n' "$OMNISURG_JWT_SECRET"
  emit OMNISURG_SENTRY_DSN "${OMNISURG_AUDIT_SENTRY_DSN:-}"
} > "$OUT_DIR/audit.env"

{
  printf 'OMNISURG_DATABASE_URL=%s\n' "$(dsn currency "$OMNISURG_CURRENCY_DB_PASSWORD")"
  printf 'OMNISURG_JWT_SECRET=%s\n' "$OMNISURG_JWT_SECRET"
  printf 'OMNISURG_REDIS_PASSWORD=%s\n' "$OMNISURG_REDIS_PASSWORD"
  printf 'OMNISURG_ZIMRATE_URL=%s\n' "$OMNISURG_CURRENCY_ZIMRATE_URL"
  emit OMNISURG_SENTRY_DSN "${OMNISURG_CURRENCY_SENTRY_DSN:-}"
} > "$OUT_DIR/currency.env"

# admin-bff owns no database; it holds the JWT secret and the R2 credentials it
# uses to issue tenant-scoped signed URLs.
{
  printf 'OMNISURG_JWT_SECRET=%s\n' "$OMNISURG_JWT_SECRET"
  emit OMNISURG_R2_ACCOUNT_ID "${OMNISURG_R2_ACCOUNT_ID:-}"
  emit OMNISURG_R2_ACCESS_KEY_ID "${OMNISURG_R2_ACCESS_KEY_ID:-}"
  emit OMNISURG_R2_SECRET_ACCESS_KEY "${OMNISURG_R2_SECRET_ACCESS_KEY:-}"
  emit OMNISURG_R2_BUCKET "${OMNISURG_R2_BUCKET:-}"
  emit OMNISURG_SENTRY_DSN "${OMNISURG_ADMIN_BFF_SENTRY_DSN:-}"
} > "$OUT_DIR/admin-bff.env"

echo "render-env: wrote 15 env files to $OUT_DIR (postgres, redis, and 13 services)"
