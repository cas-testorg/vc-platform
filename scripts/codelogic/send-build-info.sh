#!/usr/bin/env bash
# Send build log and repository metadata to CodeLogic (send_build_info).
set -euo pipefail

REPO_ROOT="${GITHUB_WORKSPACE:?}"
BUILD_LOG="${REPO_ROOT}/logs/build.log"
BUILD_STATUS="${1:-SUCCESS}"

if [[ -z "${CODELOGIC_HOST:-}" || -z "${AGENT_UUID:-}" || -z "${AGENT_PASSWORD:-}" ]]; then
  echo "CodeLogic credentials not configured; skipping send_build_info."
  exit 0
fi

mkdir -p "${REPO_ROOT}/logs"
if [[ ! -s "$BUILD_LOG" ]]; then
  {
    echo "WARNING: logs/build.log was missing or empty when send_build_info ran."
    echo "Job status: ${BUILD_STATUS}"
    echo "Check earlier steps (checkout, SDK setup, or a cancelled job)."
  } > "$BUILD_LOG"
fi

# shellcheck source=docker-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/docker-common.sh"
trap codelogic_cleanup EXIT

IMAGE_HOST="${CODELOGIC_HOST#http://}"
IMAGE_HOST="${IMAGE_HOST#https://}"
IMAGE_HOST="${IMAGE_HOST%%/*}"
IMAGE="${IMAGE_HOST}/codelogic_dotnet:latest"
JOB_NAME="${GITHUB_REPOSITORY:-unknown} — ${GITHUB_WORKFLOW:-CI}"

echo "  agent home (container): ${CODELOGIC_CONTAINER_HOME} (host: ${CODELOGIC_AGENT_HOME})"

docker run --pull always --rm \
  "${CODELOGIC_DOCKER_USER[@]}" \
  "${CODELOGIC_DOCKER_ENV[@]}" \
  "${CODELOGIC_DOCKER_VOLUMES[@]}" \
  "$IMAGE" send_build_info \
    --agent-uuid="${AGENT_UUID}" \
    --agent-password="${AGENT_PASSWORD}" \
    --server="${CODELOGIC_HOST}" \
    --path=/scan \
    --build-number="${GITHUB_RUN_NUMBER:-0}" \
    --pipeline-system="GitHub Actions" \
    --job-name="${JOB_NAME}" \
    --build-status="${BUILD_STATUS}" \
    --log-file=/scan/logs/build.log \
    --log-lines=50000 \
    --timeout=300 \
    --verbose
