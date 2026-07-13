#!/usr/bin/env bash
#
# deploy-service.sh: pull and roll ONE OmniSurg service on the VPS to a pinned
# image tag, then health-gate the stack. Run on the VPS by the gated GitHub
# Actions deploy job (reusable-deploy.yml), which scp's this file to the host and
# invokes it over SSH. The reusable-deploy.yml deploy jobs are the SOLE callers.
#
# Usage:  deploy-service.sh <env_dir> <compose_service> <image_tag> <ghcr_user>
#   env_dir         /opt/omnisurg (production) or /opt/omnisurg-staging (staging)
#   compose_service the service name INSIDE that env's docker-compose.yml
#                   (e.g. identity-service), NOT the repo name.
#   image_tag       the immutable commit sha to pin this rollout to.
#   ghcr_user       the GitHub user that owns the read-only ghcr pull token.
# The ghcr read-only pull token is read from STDIN (never argv, never a log).
#
# Deploy is scoped to the single named service (docker compose pull/up -d
# <service>), so overriding the shared IMAGE_TAG only re-pins THIS service; the
# other running services keep their own already-resolved images. Each service
# repo deploys independently with its own commit sha; a global tag is never
# assumed across services.
#
# ROLLBACK is a redeploy of the previous <image_tag> (the prior :sha). It is
# always schema-safe because migrations are expand-and-contract: no release drops
# or renames a column or table it still reads, so the older image runs against
# the newer schema. A container that dies mid-migration leaves golang-migrate in
# a `dirty` state that blocks the next boot; recover per docs/runbook/ (inspect
# schema_migrations, `migrate force <last-good>`, redeploy).
#
# HEALTH GATE (harvested gate HG-B2): after the roll, wait for the stack to
# settle, then FAIL if ANY container in this project is unhealthy. An unwired
# admin-bff gRPC peer surfaces as an unhealthy or restarting admin-bff, because
# its healthcheck plus depends_on require every peer to be up, so this gate also
# catches an unwired peer.
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "usage: deploy-service.sh <env_dir> <compose_service> <image_tag> <ghcr_user>" >&2
  exit 2
fi

ENV_DIR="$1"
SERVICE="$2"
IMAGE_TAG="$3"
GHCR_USER="$4"

# The read-only ghcr pull token arrives on stdin so it is never in argv or the
# process table.
IFS= read -r GHCR_TOKEN

cd "$ENV_DIR"

cleanup() {
  docker logout ghcr.io >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf '%s' "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin

export IMAGE_TAG
docker compose pull "$SERVICE"
docker compose up -d "$SERVICE"

# Poll the project's containers. `--format json` emits one compact JSON object
# per line (compose v2); we strip whitespace and grep, so no jq is needed.
deadline=$(( $(date +%s) + 180 ))
while true; do
  ps_json="$(docker compose ps -a --format json | tr -d ' \t')"

  if printf '%s\n' "$ps_json" | grep -qi '"health":"unhealthy"'; then
    echo "deploy failed: an unhealthy container is present" >&2
    docker compose ps >&2
    exit 1
  fi

  target_health="$(printf '%s\n' "$ps_json" \
    | grep -i "\"service\":\"${SERVICE}\"" \
    | grep -oi '"health":"[a-z]*"' | head -n1 || true)"
  still_starting="$(printf '%s\n' "$ps_json" | grep -ci '"health":"starting"' || true)"

  if printf '%s' "$target_health" | grep -qi 'healthy' && [ "$still_starting" -eq 0 ]; then
    echo "deploy healthy: ${SERVICE} at ${IMAGE_TAG}, no unhealthy peers"
    break
  fi

  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "deploy failed: timed out waiting for ${SERVICE} to become healthy" >&2
    docker compose ps >&2
    exit 1
  fi
  sleep 5
done
