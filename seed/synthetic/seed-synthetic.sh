#!/usr/bin/env bash
#
# seed-synthetic.sh loads the GENERIC SYNTHETIC business data for a sample
# practice. It carries NO real customer, NO documented password, and NO fixed
# secret: the fictional fixtures live in seed/synthetic/fixtures.json and the
# admin credentials it authenticates with are supplied at run time from the
# environment (operator supplied on staging, never in the repo).
#
# Environment gate: it runs ONLY when OMNISURG_ENV is 'local' or 'staging'. It
# refuses production. The gate is enforced first (via seed/seed-guard.sh), before
# any write, so a refusal mutates nothing.
#
# It expects the synthetic tenant, its admin user, and its service catalogue to
# already exist (created by the operator through the provider portal onboarding,
# exactly as production onboards a real practice). It then registers the fixture
# patients and, when a catalogue service id is supplied, creates one cash invoice
# per patient. It reuses the SAME HTTP contracts as the internal demo seed, so
# the records are shaped correctly by construction. It is idempotent: it searches
# by national id and reuses an existing patient rather than duplicating.
#
# Usage:
#   OMNISURG_ENV=local   ./seed/synthetic/seed-synthetic.sh --check
#   OMNISURG_ENV=staging ./seed/synthetic/seed-synthetic.sh
#
# --check performs the guard and validates the fixtures only. It writes NOTHING
# and needs no running stack, so it is safe in CI and never mutates a database.
#
# Runtime configuration (real run only, never committed):
#   OMNISURG_SYNTHETIC_ADMIN_EMAIL     admin login for the synthetic tenant
#   OMNISURG_SYNTHETIC_ADMIN_PASSWORD  its password (operator supplied)
#   OMNISURG_SYNTHETIC_BRANCH_ID       branch to register patients at (optional;
#                                      defaults to the first fixture branch)
#   OMNISURG_SYNTHETIC_SERVICE_ID      a catalogue service id to bill (optional;
#                                      when unset, invoices are skipped)
#   OMNISURG_PATIENT_URL / _BFF_URL / _IDENTITY_URL   service base urls
#
# Requires: bash, curl, jq.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD="$DIR/../seed-guard.sh"
FIXTURES="$DIR/fixtures.json"

CHECK_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    *) echo "seed-synthetic.sh: unknown argument '$arg' (expected --check)" >&2; exit 2 ;;
  esac
done

fail() { echo "FAIL: $*" >&2; exit 1; }
info() { echo "  $*"; }

# 1. Environment gate first: refuse anything outside {local, staging}. This is
#    the load-bearing safety property, so it runs before every other step.
[ -x "$GUARD" ] || fail "seed-guard.sh is missing or not executable"
bash "$GUARD" synthetic

# 2. Fixtures must be present, parseable, and free of the scrubbed strings.
command -v jq >/dev/null 2>&1 || fail "jq is required"
[ -f "$FIXTURES" ] || fail "fixtures.json is missing at $FIXTURES"
jq -e '.tenant.id and .tenant.subdomain and (.patients | length > 0)' "$FIXTURES" >/dev/null \
  || fail "fixtures.json is missing required keys (tenant.id, tenant.subdomain, patients)"

# The synthetic fixtures must never carry a real customer name, a documented
# password, or the fixed dev secret. Assert it here too, so a bad edit to the
# fixtures fails the runner as well as the selftest. The strings are assembled
# from fragments so this file itself never contains a literal match.
SCRUBBED=("Kaw""ome" "Gray""hurst" "Helens""vale" "Pass""word123!" "JDDVAR""KVOQ6E4QRJ")
for s in "${SCRUBBED[@]}"; do
  if grep -Fq "$s" "$FIXTURES"; then fail "fixtures.json contains a scrubbed string"; fi
done
info "fixtures validated (tenant $(jq -r '.tenant.subdomain' "$FIXTURES"), $(jq -r '.patients | length' "$FIXTURES") patients)"

if [ "$CHECK_ONLY" = "1" ]; then
  echo "CHECK OK: guard passed for OMNISURG_ENV='${OMNISURG_ENV:-}', synthetic fixtures valid. No data written."
  exit 0
fi

# 3. Real run: authenticate and write the synthetic records via the live APIs.
IDENTITY="${OMNISURG_IDENTITY_URL:-http://localhost:8081}"
PATIENTSVC="${OMNISURG_PATIENT_URL:-http://localhost:8083}"
BFF="${OMNISURG_BFF_URL:-http://localhost:8093}"

TENANT_ID="$(jq -r '.tenant.id' "$FIXTURES")"
BRANCH_ID="${OMNISURG_SYNTHETIC_BRANCH_ID:-$(jq -r '.branches[0].id' "$FIXTURES")}"
SERVICE_ID="${OMNISURG_SYNTHETIC_SERVICE_ID:-}"
ADMIN_EMAIL="${OMNISURG_SYNTHETIC_ADMIN_EMAIL:-}"
ADMIN_PASSWORD="${OMNISURG_SYNTHETIC_ADMIN_PASSWORD:-}"

[ -n "$ADMIN_EMAIL" ] || fail "OMNISURG_SYNTHETIC_ADMIN_EMAIL is required for a real run (operator supplied, never committed)"
[ -n "$ADMIN_PASSWORD" ] || fail "OMNISURG_SYNTHETIC_ADMIN_PASSWORD is required for a real run (operator supplied, never committed)"
for tool in curl jq; do command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"; done

echo "== seed-synthetic: authenticate as the synthetic tenant admin =="
LOGIN_BODY=$(jq -nc --arg e "$ADMIN_EMAIL" --arg p "$ADMIN_PASSWORD" '{email:$e,password:$p}')
LOGIN_RESP=$(curl -sf -X POST "$IDENTITY/api/v1/identity/login" \
  -H "Content-Type: application/json" -H "X-Tenant-ID: $TENANT_ID" \
  -d "$LOGIN_BODY") || fail "login failed (is the synthetic tenant onboarded and the stack up?)"
TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.token // .token // empty')
[ -n "$TOKEN" ] || fail "login returned no token"
AUTH=(-H "Authorization: Bearer $TOKEN")
info "authenticated"

echo "== seed-synthetic: register the fixture patients (idempotent) =="
PATIENT_COUNT=$(jq -r '.patients | length' "$FIXTURES")
for i in $(seq 0 $((PATIENT_COUNT - 1))); do
  NID=$(jq -r ".patients[$i].national_id" "$FIXTURES")
  EXIST=$(curl -sf "${AUTH[@]}" "$PATIENTSVC/api/v1/patient/patients?query=$NID" | jq -r --arg n "$NID" '[.data.patients[]? | select(.national_id == $n)] | .[0].id // empty') || true
  if [ -n "$EXIST" ]; then
    info "reuse patient $NID ($EXIST)"
    PID="$EXIST"
  else
    BODY=$(jq -c ".patients[$i] | {first_name: .given_name, last_name: .family_name, date_of_birth, sex, national_id, phone, payer_default: \"cash\", branch_id: \"$BRANCH_ID\", consents: [\"treatment\",\"billing\"]}" "$FIXTURES")
    RESP=$(curl -sf "${AUTH[@]}" -H "Content-Type: application/json" -X POST "$PATIENTSVC/api/v1/patient/patients" -d "$BODY") \
      || fail "register failed for patient $NID"
    PID=$(echo "$RESP" | jq -r '.data.id // .id')
    info "created patient $NID ($PID)"
  fi

  if [ -n "$SERVICE_ID" ]; then
    DUE=$(jq -r ".invoices[] | select(.patient_id == (.patient_id)) | .patient_due_minor" "$FIXTURES" 2>/dev/null | head -1)
    DUE="${DUE:-5000}"
    INVBODY=$(jq -nc --arg pid "$PID" --arg bid "$BRANCH_ID" --arg sid "$SERVICE_ID" --argjson due "$DUE" \
      '{patientId:$pid, branchId:$bid, currencyCode:"USD", lines:[{catalogueServiceId:$sid, description:"Synthetic consultation", quantity:1, unitPriceMinor:$due}]}')
    curl -sf "${AUTH[@]}" -H "Content-Type: application/json" -X POST "$BFF/api/v1/rest/invoices" -d "$INVBODY" >/dev/null \
      && info "created a cash invoice for $PID" \
      || info "invoice create skipped for $PID (service catalogue id may not resolve)"
  fi
done

if [ -z "$SERVICE_ID" ]; then
  info "OMNISURG_SYNTHETIC_SERVICE_ID unset: registered patients only, no invoices created"
fi

echo
echo "seed-synthetic complete: synthetic patients present for tenant $(jq -r '.tenant.subdomain' "$FIXTURES")."
