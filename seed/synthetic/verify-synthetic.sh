#!/usr/bin/env bash
#
# verify-synthetic.sh is the public counterpart of the internal demo verifier. It
# proves the synthetic seed lined up: every fixture patient resolves through the
# live patient API for the synthetic tenant. It reads the ids from
# seed/synthetic/fixtures.json (one source of truth) and authenticates with the
# operator supplied synthetic admin credentials (never committed).
#
# It carries none of the demo customer name, documented password, or fixed
# secret. Run it after seed-synthetic.sh against the running stack.
#
# Runtime configuration (never committed):
#   OMNISURG_SYNTHETIC_ADMIN_EMAIL / OMNISURG_SYNTHETIC_ADMIN_PASSWORD
#   OMNISURG_IDENTITY_URL / OMNISURG_PATIENT_URL
#
# Requires: bash, curl, jq.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$DIR/fixtures.json"

IDENTITY="${OMNISURG_IDENTITY_URL:-http://localhost:8081}"
PATIENTSVC="${OMNISURG_PATIENT_URL:-http://localhost:8083}"
ADMIN_EMAIL="${OMNISURG_SYNTHETIC_ADMIN_EMAIL:-}"
ADMIN_PASSWORD="${OMNISURG_SYNTHETIC_ADMIN_PASSWORD:-}"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "  ok: $*"; }

for tool in curl jq; do command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"; done
[ -f "$FIXTURES" ] || fail "fixtures.json is missing"
[ -n "$ADMIN_EMAIL" ] || fail "OMNISURG_SYNTHETIC_ADMIN_EMAIL is required (operator supplied)"
[ -n "$ADMIN_PASSWORD" ] || fail "OMNISURG_SYNTHETIC_ADMIN_PASSWORD is required (operator supplied)"

TENANT_ID="$(jq -r '.tenant.id' "$FIXTURES")"

echo "== verify-synthetic: authenticate as the synthetic tenant admin =="
LOGIN_BODY=$(jq -nc --arg e "$ADMIN_EMAIL" --arg p "$ADMIN_PASSWORD" '{email:$e,password:$p}')
LOGIN_RESP=$(curl -sf -X POST "$IDENTITY/api/v1/identity/login" \
  -H "Content-Type: application/json" -H "X-Tenant-ID: $TENANT_ID" \
  -d "$LOGIN_BODY") || fail "login failed (is the synthetic tenant seeded and the stack up?)"
TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.token // .token // empty')
[ -n "$TOKEN" ] || fail "login returned no token"
AUTH=(-H "Authorization: Bearer $TOKEN")
pass "login 200"

echo "== verify-synthetic: fixture patients resolve =="
COUNT=$(jq -r '.patients | length' "$FIXTURES")
for i in $(seq 0 $((COUNT - 1))); do
  NID=$(jq -r ".patients[$i].national_id" "$FIXTURES")
  FOUND=$(curl -sf "${AUTH[@]}" "$PATIENTSVC/api/v1/patient/patients?query=$NID" \
    | jq -r --arg n "$NID" '[.data.patients[]? | select(.national_id == $n)] | length') || fail "patient list failed for $NID"
  [ "$FOUND" -ge 1 ] 2>/dev/null || fail "synthetic patient $NID not found"
  pass "synthetic patient $NID present"
done

echo
echo "PASS: every synthetic fixture patient resolves for tenant $(jq -r '.tenant.subdomain' "$FIXTURES")."
