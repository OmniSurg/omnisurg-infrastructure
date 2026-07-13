#!/usr/bin/env bash
#
# seed-guard.sh is the environment gate shared by the two seed paths. It reads
# OMNISURG_ENV from the environment and refuses (non-zero, with a plain message)
# when the current environment is not allowed for the requested seed mode. It
# performs NO database work: it is the first thing each seed runner calls, so a
# refusal exits before any data is written.
#
# Modes:
#   demo       the internal demo seed (real customer name, documented test
#              logins, fixed dev TOTP secret). ALLOWED only when OMNISURG_ENV=local.
#              It must never touch staging or production, even by accident.
#   synthetic  the public synthetic seed (fictional practice, no documented
#              password, no fixed secret). ALLOWED when OMNISURG_ENV is local or
#              staging. It never runs against production.
#
# Usage:
#   OMNISURG_ENV=local ./seed/seed-guard.sh demo
#   OMNISURG_ENV=staging ./seed/seed-guard.sh synthetic
#
# Exit codes: 0 allowed, 1 refused, 2 usage error.
set -euo pipefail

mode="${1:-}"
env="${OMNISURG_ENV:-}"

case "$mode" in
  demo)
    if [ "$env" != "local" ]; then
      echo "REFUSED: 'make seed' loads demo data with a real customer name and documented test logins." >&2
      echo "It only runs when OMNISURG_ENV=local. Current OMNISURG_ENV='${env}'." >&2
      echo "This path must never touch staging or production. Use 'make seed-synthetic' for staging." >&2
      exit 1
    fi
    ;;
  synthetic)
    case "$env" in
      local|staging)
        : # allowed
        ;;
      *)
        echo "REFUSED: 'make seed-synthetic' loads generic synthetic business data." >&2
        echo "It only runs when OMNISURG_ENV is 'local' or 'staging'. Current OMNISURG_ENV='${env}'." >&2
        echo "It never runs against production. Production is onboarded through the provider portal, never a seed." >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "seed-guard.sh: unknown mode '${mode}' (expected 'demo' or 'synthetic')" >&2
    exit 2
    ;;
esac
