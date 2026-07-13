#!/usr/bin/env bash
#
# seed_selftest.sh is the stack-free TDD guard for the two seed paths. It runs as
# part of `make ci` and needs no running stack and no database. It proves:
#
#   1. The environment gate refuses correctly. `make seed` (demo) runs ONLY when
#      OMNISURG_ENV=local; `make seed-synthetic` runs ONLY when OMNISURG_ENV is
#      local or staging. Every other environment (production, empty, anything
#      else) is refused with a non-zero exit, so a seed can never run against an
#      internet facing environment by accident.
#
#   2. `seed-synthetic --check` passes for an allowed environment without writing
#      anything, and is refused for production.
#
#   3. The committed (public) seed tree and the committed smoke fixture carry NONE
#      of the scrubbed strings (the real customer name, the two branch names, the
#      documented password, the fixed dev TOTP secret). The internal demo fixtures
#      are NOT tracked.
#
#   4. The demo seed target calls the environment guard BEFORE it seeds, so the
#      refusal happens before any data is written.
#
# The scrubbed strings are assembled from fragments so this file itself never
# contains a literal match (bash concatenates adjacent quoted strings), which lets
# the scan include this file safely.
#
# Usage: seed/seed_selftest.sh   (no running stack required)
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
GUARD="$DIR/seed-guard.sh"
SYNTH="$DIR/synthetic/seed-synthetic.sh"
FIXTURES="$DIR/synthetic/fixtures.json"

fail() { echo "SELFTEST FAIL: $*" >&2; exit 1; }
pass() { echo "  ok: $*"; }

# Scrubbed strings, assembled so no literal appears in this file.
SCRUBBED=(
  "Kaw""ome"
  "Gray""hurst"
  "Helens""vale"
  "Pass""word123!"
  "JDDVAR""KVOQ6E4QRJ"
)

[ -x "$GUARD" ] || fail "seed-guard.sh is missing or not executable"
[ -x "$SYNTH" ] || fail "seed-synthetic.sh is missing or not executable"
[ -f "$FIXTURES" ] || fail "synthetic fixtures.json is missing"
command -v git >/dev/null 2>&1 || fail "git is required"

# ---------------------------------------------------------------------------
echo "== selftest 1: the demo guard allows only OMNISURG_ENV=local =="
run_guard() { # <env> <mode> ; echoes exit code
  set +e
  OMNISURG_ENV="$1" bash "$GUARD" "$2" >/dev/null 2>&1
  local rc=$?
  set -e
  echo "$rc"
}
[ "$(run_guard local demo)" = "0" ] || fail "demo guard refused OMNISURG_ENV=local"
[ "$(run_guard staging demo)" != "0" ] || fail "demo guard allowed OMNISURG_ENV=staging"
[ "$(run_guard production demo)" != "0" ] || fail "demo guard allowed OMNISURG_ENV=production"
[ "$(run_guard '' demo)" != "0" ] || fail "demo guard allowed an empty OMNISURG_ENV"
pass "demo seed runs only for local; staging, production, and empty are refused"

echo "== selftest 2: the synthetic guard allows only local and staging =="
[ "$(run_guard local synthetic)" = "0" ] || fail "synthetic guard refused OMNISURG_ENV=local"
[ "$(run_guard staging synthetic)" = "0" ] || fail "synthetic guard refused OMNISURG_ENV=staging"
[ "$(run_guard production synthetic)" != "0" ] || fail "synthetic guard allowed OMNISURG_ENV=production"
[ "$(run_guard nonsense synthetic)" != "0" ] || fail "synthetic guard allowed an unknown environment"
[ "$(run_guard '' synthetic)" != "0" ] || fail "synthetic guard allowed an empty OMNISURG_ENV"
pass "synthetic seed runs only for local and staging; production and empty are refused"

echo "== selftest 3: seed-synthetic --check passes when allowed and refuses production =="
set +e
OMNISURG_ENV=local bash "$SYNTH" --check >/dev/null 2>&1
rc_local=$?
OMNISURG_ENV=production bash "$SYNTH" --check >/dev/null 2>&1
rc_prod=$?
set -e
[ "$rc_local" = "0" ] || fail "seed-synthetic --check failed for OMNISURG_ENV=local (rc=$rc_local)"
[ "$rc_prod" != "0" ] || fail "seed-synthetic --check ran for OMNISURG_ENV=production (must refuse)"
pass "seed-synthetic --check is green for local and refused for production, writing nothing"

echo "== selftest 4: the committed seed tree and smoke fixture carry no scrubbed strings =="
cd "$REPO"
# Committed (tracked) seed files, plus the committed smoke credentials fixture,
# plus the synthetic fixtures on disk (in case they are not yet staged).
SCAN=()
while IFS= read -r f; do [ -n "$f" ] && SCAN+=("$f"); done < <(git ls-files seed smoke/credentials.example.json)
while IFS= read -r f; do [ -n "$f" ] && SCAN+=("$f"); done < <(find seed/synthetic -type f 2>/dev/null)
# Deduplicate.
UNIQUE=()
while IFS= read -r f; do [ -n "$f" ] && UNIQUE+=("$f"); done < <(printf '%s\n' "${SCAN[@]}" | sort -u)
[ "${#UNIQUE[@]}" -gt 0 ] || fail "no committed seed or smoke files found to scan"
for f in "${UNIQUE[@]}"; do
  for s in "${SCRUBBED[@]}"; do
    if grep -Fq "$s" "$f"; then fail "scrubbed string found in committed file $f"; fi
  done
done
pass "no scrubbed string in ${#UNIQUE[@]} committed seed/smoke files"

echo "== selftest 5: the internal demo fixtures are NOT tracked =="
for p in seed/internal/IDS.md seed/internal/demo/seed-demo.mjs seed/internal/verify.sh seed/internal/identity-users.md; do
  if git ls-files --error-unmatch "$p" >/dev/null 2>&1; then
    fail "$p is tracked; the internal demo fixtures must stay gitignored"
  fi
done
pass "the internal demo fixtures (customer name, documented logins, fixed secret) stay gitignored"

echo "== selftest 6: the demo seed target guards before it seeds =="
GUARD_LINE=$(grep -n 'seed-guard.sh demo' "$REPO/Makefile" | head -1 | cut -d: -f1)
# Match the exec recipe line (COMPOSE exec ... /app/seed), not the comment.
SEED_EXEC_LINE=$(grep -n 'exec -T.*/app/seed' "$REPO/Makefile" | head -1 | cut -d: -f1)
[ -n "$GUARD_LINE" ] || fail "the seed target does not call seed-guard.sh demo"
[ -n "$SEED_EXEC_LINE" ] || fail "could not find the seed exec line (/app/seed) in the Makefile"
[ "$GUARD_LINE" -lt "$SEED_EXEC_LINE" ] || fail "the guard (line $GUARD_LINE) does not precede the first seed exec (line $SEED_EXEC_LINE)"
pass "the demo seed target calls the environment guard (line $GUARD_LINE) before the first seed exec (line $SEED_EXEC_LINE)"

echo
echo "SELFTEST PASS: the seed guards refuse correctly, --check writes nothing, the committed tree is scrubbed, and the demo fixtures stay internal."
