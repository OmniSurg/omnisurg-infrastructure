#!/bin/sh
# OmniSurg deploy Postgres init (shared by the production and staging stacks).
#
# Runs ONCE on a fresh data volume (docker-entrypoint-initdb.d). Creates one
# login role plus one database per Phase 1 service, each role owning only its own
# database with its OWN password (one role per service; least privilege). The
# per-service passwords are read from the container environment (the rendered
# postgres env file), so no password is hardcoded and none is shared.
#
# The database names are IDENTICAL to local and across environments; isolation is
# by container and network, not by name suffix (spec section 3).
#
# NOTE: passwords are interpolated into CREATE ROLE and must be alphanumeric (no
# single quote); deploy/render-env.sh and the operator generate them that way.
set -eu

create_service() {
  svc="$1"
  pw="$2"
  if [ -z "$pw" ]; then
    echo "init: missing password for role omnisurg_${svc} (set OMNISURG_$(echo "$svc" | tr '[:lower:]' '[:upper:]')_DB_PASSWORD)" >&2
    exit 1
  fi
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    -c "CREATE ROLE omnisurg_${svc} LOGIN PASSWORD '${pw}';" \
    -c "CREATE DATABASE omnisurg_${svc} OWNER omnisurg_${svc};"
}

create_service identity     "${OMNISURG_IDENTITY_DB_PASSWORD:-}"
create_service tenant       "${OMNISURG_TENANT_DB_PASSWORD:-}"
create_service patient      "${OMNISURG_PATIENT_DB_PASSWORD:-}"
create_service clinical     "${OMNISURG_CLINICAL_DB_PASSWORD:-}"
create_service referral     "${OMNISURG_REFERRAL_DB_PASSWORD:-}"
create_service billing      "${OMNISURG_BILLING_DB_PASSWORD:-}"
create_service payment      "${OMNISURG_PAYMENT_DB_PASSWORD:-}"
create_service claims       "${OMNISURG_CLAIMS_DB_PASSWORD:-}"
create_service notification "${OMNISURG_NOTIFICATION_DB_PASSWORD:-}"
create_service scheduling   "${OMNISURG_SCHEDULING_DB_PASSWORD:-}"
create_service audit        "${OMNISURG_AUDIT_DB_PASSWORD:-}"
create_service currency     "${OMNISURG_CURRENCY_DB_PASSWORD:-}"

echo "init: created 12 service roles and databases"
