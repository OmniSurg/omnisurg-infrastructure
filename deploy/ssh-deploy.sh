#!/usr/bin/env bash
#
# ssh-deploy.sh: runner-side wrapper invoked by the gated deploy jobs in
# .github/workflows/reusable-deploy.yml. It writes the SSH deploy key and pinned
# known_hosts, ships deploy-service.sh to the VPS, and runs it over SSH with the
# ghcr read-only pull token on stdin (never argv). All inputs arrive as env vars
# set by the workflow step; the VPS host is a secret, never a literal here.
set -euo pipefail

: "${VPS_HOST:?VPS_HOST is required}"
: "${VPS_USER:?VPS_USER is required}"
: "${VPS_PORT:?VPS_PORT is required}"
: "${VPS_SSH_KEY:?VPS_SSH_KEY is required}"
: "${VPS_KNOWN_HOSTS:?VPS_KNOWN_HOSTS is required}"
: "${GHCR_READ_USER:?GHCR_READ_USER is required}"
: "${GHCR_READ_TOKEN:?GHCR_READ_TOKEN is required}"
: "${COMPOSE_SERVICE:?COMPOSE_SERVICE is required}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"
: "${ENV_DIR:?ENV_DIR is required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_DIR="$(mktemp -d)"
KEY_FILE="$SSH_DIR/deploy_key"
KNOWN_HOSTS="$SSH_DIR/known_hosts"

cleanup() { rm -rf "$SSH_DIR"; }
trap cleanup EXIT

install -m 600 /dev/null "$KEY_FILE"
printf '%s\n' "$VPS_SSH_KEY" >"$KEY_FILE"
printf '%s\n' "$VPS_KNOWN_HOSTS" >"$KNOWN_HOSTS"

# -o Port= is honoured by both ssh and scp (scp uses -P, ssh uses -p, so we avoid
# the flag mismatch by using the option form). StrictHostKeyChecking=yes with a
# pinned known_hosts prevents a man-in-the-middle on the deploy channel.
SSH_OPTS=(
  -i "$KEY_FILE"
  -o "UserKnownHostsFile=$KNOWN_HOSTS"
  -o StrictHostKeyChecking=yes
  -o "Port=$VPS_PORT"
)

scp "${SSH_OPTS[@]}" "$SCRIPT_DIR/deploy-service.sh" \
  "$VPS_USER@$VPS_HOST:/tmp/omnisurg-deploy-service.sh"

# ENV_DIR / COMPOSE_SERVICE / IMAGE_TAG / GHCR_READ_USER are our own controlled,
# non-secret values, interpolated into the remote command. The pull token is
# piped on stdin and read by deploy-service.sh, so it never appears in argv.
# shellcheck disable=SC2029  # client-side expansion of these controlled values is intended.
printf '%s' "$GHCR_READ_TOKEN" | ssh "${SSH_OPTS[@]}" "$VPS_USER@$VPS_HOST" \
  "bash /tmp/omnisurg-deploy-service.sh '$ENV_DIR' '$COMPOSE_SERVICE' '$IMAGE_TAG' '$GHCR_READ_USER'; rc=\$?; rm -f /tmp/omnisurg-deploy-service.sh; exit \$rc"
