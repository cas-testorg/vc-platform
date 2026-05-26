#!/usr/bin/env bash
# Scan dotnet publish output with the CodeLogic .NET agent (Docker).
# Usage: run-dotnet-analyze.sh <publish_dir>
#
# Optional env (multiline or comma-separated per entry):
#   CODELOGIC_ASSEMBLY_FILTERS  -> -f|--filter (DLL / filename substrings)
#   CODELOGIC_METHOD_FILTERS    -> -m|--method-filter (namespace prefixes)
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

# Append analyze flags from a multiline/comma-separated env value.
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
IMAGE_HOST="${CODELOGIC_HOST#http://}"
IMAGE_HOST="${IMAGE_HOST#https://}"
IMAGE_HOST="${IMAGE_HOST%%/*}"
IMAGE="${IMAGE_HOST}/codelogic_dotnet:latest"

# LibGit2Sharp in the agent reads git metadata from /scan; match runner UID and mark safe.directory.
DOCKER_USER=(--user "$(id -u):$(id -g)")
GITCONFIG="$(mktemp)"
trap 'rm -f "$GITCONFIG"' EXIT
printf '[safe]\n\tdirectory = /scan\n' > "$GITCONFIG"

DOCKER_VOLUMES=(
  -v "${REPO_ROOT}:/scan"
  -v "${GITCONFIG}:/tmp/gitconfig-codelogic:ro"
)

REF_ARGS=()
_add_ref_path() {
  local _container_path=$1
  REF_ARGS+=(--ref-path="${_container_path}")
  echo "  ref-path: ${_container_path}"
}

# Source tree (namespace / project context; git metadata when ownership matches).
_add_ref_path /scan

# Host .NET SDK — mount so ref-path resolves Microsoft.* / ASP.NET shared assemblies.
DOTNET_ROOT="${DOTNET_ROOT:-/usr/share/dotnet}"
if [[ -d "${DOTNET_ROOT}/shared" ]]; then
  DOCKER_VOLUMES+=(-v "${DOTNET_ROOT}:/dotnet:ro")
  _add_ref_path /dotnet/shared
  if [[ -d "${DOTNET_ROOT}/packs" ]]; then
    _add_ref_path /dotnet/packs
  fi
fi

# NuGet package cache from restore/build on the runner.
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

echo "CodeLogic analyze: application=${APPLICATION_NAME} scan-space=${SCAN_SPACE_NAME}"
echo "  artifact path (container): ${CONTAINER_PUBLISH}"
if ((${#FILTER_ARGS[@]})); then
  echo "  assembly filters (-f): ${FILTER_ARGS[*]}"
fi
if ((${#METHOD_FILTER_ARGS[@]})); then
  echo "  method filters (-m): ${METHOD_FILTER_ARGS[*]}"
fi

docker run --pull always --rm \
  "${DOCKER_USER[@]}" \
  -e CODELOGIC_HOST \
  -e AGENT_UUID \
  -e AGENT_PASSWORD \
  -e GIT_CONFIG_GLOBAL=/tmp/gitconfig-codelogic \
  "${DOCKER_VOLUMES[@]}" \
  "$IMAGE" analyze \
    --application "$APPLICATION_NAME" \
    --path "$CONTAINER_PUBLISH" \
    --scan-space-name "$SCAN_SPACE_NAME" \
    "${REF_ARGS[@]}" \
    "${FILTER_ARGS[@]}" \
    "${METHOD_FILTER_ARGS[@]}" \
    "${DB_ARGS[@]}" \
    --rescan \
    --expunge-scan-sessions
