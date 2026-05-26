#!/usr/bin/env bash
# Scan dotnet publish output with the CodeLogic .NET agent (Docker).
# Usage: run-dotnet-analyze.sh <publish_dir> [ref_path] [dotnet_shared_path]
#
# Optional env (multiline or comma-separated per entry):
#   CODELOGIC_ASSEMBLY_FILTERS  -> -f|--filter (DLL / filename substrings)
#   CODELOGIC_METHOD_FILTERS    -> -m|--method-filter (namespace prefixes)
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

# Append analyze flags from a multiline/comma-separated env value.
# Usage: _append_multi_spec FILTER_ARGS --filter "$CODELOGIC_ASSEMBLY_FILTERS"
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

echo "CodeLogic analyze: application=${APPLICATION_NAME} scan-space=${SCAN_SPACE_NAME}"
echo "  artifact path (container): ${CONTAINER_PUBLISH}"
if ((${#FILTER_ARGS[@]})); then
  echo "  assembly filters (-f): ${FILTER_ARGS[*]}"
else
  echo "  assembly filters (-f): (none — all matching assemblies under path)"
fi
if ((${#METHOD_FILTER_ARGS[@]})); then
  echo "  method filters (-m): ${METHOD_FILTER_ARGS[*]}"
else
  echo "  method filters (-m): (none — UI defaults)"
fi

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
    "${FILTER_ARGS[@]}" \
    "${METHOD_FILTER_ARGS[@]}" \
    "${DB_ARGS[@]}" \
    --expunge-scan-sessions
