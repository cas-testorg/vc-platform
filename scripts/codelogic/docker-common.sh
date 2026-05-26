#!/usr/bin/env bash
# Shared Docker settings for CodeLogic agent containers (source, do not execute).
# Requires caller to set REPO_ROOT before sourcing.

: "${REPO_ROOT:?REPO_ROOT must be set before sourcing docker-common.sh}"

# With --user uid:gid the image often has no HOME, so config paths become //.local/...
CODELOGIC_CONTAINER_HOME=/agent-home
CODELOGIC_AGENT_HOME="${RUNNER_TEMP:-/tmp}/codelogic-agent-home"
mkdir -p "${CODELOGIC_AGENT_HOME}/.local/share/CodeLogic/netCape" "${CODELOGIC_AGENT_HOME}/work"

CODELOGIC_DOCKER_USER=(--user "$(id -u):$(id -g)")
CODELOGIC_DOCKER_ENV=(
  -e "HOME=${CODELOGIC_CONTAINER_HOME}"
  -e CODELOGIC_HOST
  -e AGENT_UUID
  -e AGENT_PASSWORD
)
CODELOGIC_DOCKER_VOLUMES=(
  -v "${REPO_ROOT}:/scan"
  -v "${CODELOGIC_AGENT_HOME}:${CODELOGIC_CONTAINER_HOME}"
)

CODELOGIC_GITCONFIG="$(mktemp)"
printf '[safe]\n\tdirectory = /scan\n' > "${CODELOGIC_GITCONFIG}"
CODELOGIC_DOCKER_VOLUMES+=(-v "${CODELOGIC_GITCONFIG}:/tmp/gitconfig-codelogic:ro")
CODELOGIC_DOCKER_ENV+=(-e GIT_CONFIG_GLOBAL=/tmp/gitconfig-codelogic)

codelogic_cleanup() {
  rm -f "${CODELOGIC_GITCONFIG:-}"
}
