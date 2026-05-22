#!/usr/bin/env bash
# Scan dotnet publish output with the CodeLogic .NET agent (Docker).
# Usage: run-dotnet-analyze.sh <publish_dir> [ref_path] [dotnet_shared_path]
set -euo pipefail

PUBLISH_DIR="${1:?publish directory required}"
REF_PATH="${2:-}"
DOTNET_PATH="${3:-}"

if [[ -z "${CODELOGIC_HOST:-}" || -z "${AGENT_UUID:-}" || -z "${AGENT_PASSWORD:-}" ]]; then
  echo "CodeLogic credentials not configured (CODELOGIC_HOST, AGENT_UUID, AGENT_PASSWORD); skipping analyze."
  exit 0
fi

if [[ ! -d "$PUBLISH_DIR" ]]; then
  echo "ERROR: Publish directory does not exist: $PUBLISH_DIR"
  exit 1
fi

REPO_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "$PUBLISH_DIR")/.." && pwd)}"
REL_PUBLISH="${PUBLISH_DIR#"$REPO_ROOT"/}"
CONTAINER_PUBLISH="/scan/${REL_PUBLISH}"

APPLICATION_NAME="${CODELOGIC_APPLICATION_NAME:-vc-platform}"
SCAN_SPACE_NAME="${CODELOGIC_SCAN_SPACE_NAME:-Development}"
IMAGE="${CODELOGIC_HOST%/}/codelogic_dotnet:latest"

REF_ARGS=()
if [[ -n "$REF_PATH" ]]; then
  REF_ARGS+=(--ref-path="$REF_PATH")
fi
if [[ -n "$DOTNET_PATH" && -d "$DOTNET_PATH" ]]; then
  REF_ARGS+=(--ref-path="$DOTNET_PATH")
fi

DB_ARGS=()
if [[ -n "${CODELOGIC_DATABASE_IDENTITIES:-}" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//$'\r'/}"
    [[ -z "${line// }" ]] && continue
    DB_ARGS+=(-d "$line")
  done <<< "$CODELOGIC_DATABASE_IDENTITIES"
fi

echo "CodeLogic analyze: application=${APPLICATION_NAME} scan-space=${SCAN_SPACE_NAME}"
echo "  artifact path (container): ${CONTAINER_PUBLISH}"

docker run --pull always --rm \
  -e CODELOGIC_HOST \
  -e AGENT_UUID \
  -e AGENT_PASSWORD \
  -v "${REPO_ROOT}:/scan" \
  "$IMAGE" analyze \
    --application="$APPLICATION_NAME" \
    --path="$CONTAINER_PUBLISH" \
    --scan-space-name="$SCAN_SPACE_NAME" \
    "${REF_ARGS[@]}" \
    "${DB_ARGS[@]}" \
    --rescan \
    --expunge-scan-sessions
