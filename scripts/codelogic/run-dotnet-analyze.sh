#!/usr/bin/env bash
# Scan dotnet publish output with the CodeLogic .NET agent (Docker).
# Usage: run-dotnet-analyze.sh <publish_dir>
set -euo pipefail

PUBLISH_DIR="${1:?publish directory required}"

if [[ -z "${CODELOGIC_HOST:-}" || -z "${AGENT_UUID:-}" || -z "${AGENT_PASSWORD:-}" ]]; then
  echo "CodeLogic credentials not configured (CODELOGIC_HOST, AGENT_UUID, AGENT_PASSWORD); skipping analyze."
  exit 0
fi

if [[ ! -d "$PUBLISH_DIR" ]]; then
  echo "ERROR: Publish directory does not exist: $PUBLISH_DIR"
  exit 1
fi

_append_multi_spec() {
  local -n _out=$1
  local _flag=$2
  local _env_val=${3:-}
  local _line _item _old_ifs

  [[ -z "$_env_val" ]] && return 0

  while IFS= read -r _line || [[ -n "$_line" ]]; do
    _line="${_line//$'\r'/}"
    [[ -z "${_line// }" ]] && continue
    _old_ifs=$IFS
    IFS=',' read -ra _items <<< "$_line"
    IFS=$_old_ifs
    for _item in "${_items[@]}"; do
      _item="${_item#"${_item%%[![:space:]]*}"}"
      _item="${_item%"${_item##*[![:space:]]}"}"
      [[ -z "$_item" ]] && continue
      _out+=("${_flag}=${_item}")
    done
  done <<< "$_env_val"
}

REPO_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "$PUBLISH_DIR")/.." && pwd)}"
REL_PUBLISH="${PUBLISH_DIR#"$REPO_ROOT"/}"
CONTAINER_PUBLISH="/scan/${REL_PUBLISH}"

# shellcheck source=docker-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/docker-common.sh"
trap codelogic_cleanup EXIT

APPLICATION_NAME="${CODELOGIC_APPLICATION_NAME:-vc-platform}"
SCAN_SPACE_NAME="${CODELOGIC_SCAN_SPACE_NAME:-Development}"
IMAGE_HOST="${CODELOGIC_HOST#http://}"
IMAGE_HOST="${IMAGE_HOST#https://}"
IMAGE_HOST="${IMAGE_HOST%%/*}"
IMAGE="${IMAGE_HOST}/codelogic_dotnet:latest"

DOCKER_VOLUMES=("${CODELOGIC_DOCKER_VOLUMES[@]}")

REF_ARGS=()
_add_ref_path() {
  REF_ARGS+=(--ref-path="$1")
  echo "  ref-path: $1"
}

_add_ref_path /scan

DOTNET_ROOT="${DOTNET_ROOT:-/usr/share/dotnet}"
if [[ -d "${DOTNET_ROOT}/shared" ]]; then
  DOCKER_VOLUMES+=(-v "${DOTNET_ROOT}:/dotnet:ro")
  _add_ref_path /dotnet/shared
  if [[ -d "${DOTNET_ROOT}/packs" ]]; then
    _add_ref_path /dotnet/packs
  fi
fi

NUGET_PACKAGES="${NUGET_PACKAGES:-${HOME}/.nuget/packages}"
if [[ -d "${NUGET_PACKAGES}" ]]; then
  DOCKER_VOLUMES+=(-v "${NUGET_PACKAGES}:/nuget:ro")
  _add_ref_path /nuget
fi

FILTER_ARGS=()
_append_multi_spec FILTER_ARGS --filter "${CODELOGIC_ASSEMBLY_FILTERS:-}"

METHOD_FILTER_ARGS=()
_append_multi_spec METHOD_FILTER_ARGS --method-filter "${CODELOGIC_METHOD_FILTERS:-}"

DB_ARGS=()
if [[ -n "${CODELOGIC_DATABASE_IDENTITIES:-}" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//$'\r'/}"
    [[ -z "${line// }" ]] && continue
    DB_ARGS+=(-d "$line")
  done <<< "$CODELOGIC_DATABASE_IDENTITIES"
fi

REG_ARGS=()
if [[ "${CODELOGIC_FORCE_REGISTRATION:-}" == "true" ]]; then
  REG_ARGS+=(--force-registration)
  echo "  registration: --force-registration"
fi

echo "CodeLogic analyze: application=${APPLICATION_NAME} scan-space=${SCAN_SPACE_NAME}"
echo "  artifact path (container): ${CONTAINER_PUBLISH}"
echo "  agent home (container): ${CODELOGIC_CONTAINER_HOME} (host: ${CODELOGIC_AGENT_HOME})"

docker run --pull always --rm \
  "${CODELOGIC_DOCKER_USER[@]}" \
  "${CODELOGIC_DOCKER_ENV[@]}" \
  -w "${CODELOGIC_CONTAINER_HOME}/work" \
  "${DOCKER_VOLUMES[@]}" \
  "$IMAGE" analyze \
    --application "$APPLICATION_NAME" \
    --path "$CONTAINER_PUBLISH" \
    --scan-space-name "$SCAN_SPACE_NAME" \
    "${REF_ARGS[@]}" \
    "${FILTER_ARGS[@]}" \
    "${METHOD_FILTER_ARGS[@]}" \
    "${DB_ARGS[@]}" \
    "${REG_ARGS[@]}" \
    --rescan \
    --expunge-scan-sessions
