# Workflows

## [platform-ci.yml](platform-ci.yml)

Runs on **`renovate/**`** branches only (push and pull request).

1. Restore, build, and publish to `artifacts/out` (log: `logs/build.log`)
2. Upload `dotnet-publish` and `dotnet-build-log` artifacts
3. CodeLogic scan of published binaries
4. `send_build_info` with build log and repository metadata

### CodeLogic (optional until configured)

| Kind | Name |
|------|------|
| Variable | `CODELOGIC_HOST` |
| Secret | `AGENT_UUID`, `AGENT_PASSWORD` |
| Variable (optional) | `CODELOGIC_APPLICATION_NAME`, `CODELOGIC_SCAN_SPACE_NAME` |
| Variable (optional) | `CODELOGIC_ASSEMBLY_FILTERS` — multiline/comma-separated `-f` / `--filter` (DLL name substrings, e.g. `VirtoCommerce.Platform`) |
| Variable (optional) | `CODELOGIC_METHOD_FILTERS` — multiline/comma-separated `-m` / `--method-filter` (namespace prefixes, e.g. `VirtoCommerce`) |
| Variable (optional) | `CODELOGIC_DATABASE_IDENTITIES` — multiline `-d` JDBC identities |

Each scan uses `--rescan` and `--expunge-scan-sessions` (CI keeps only the latest fingerprinted scan).

Agent credentials cache: `${RUNNER_TEMP}/codelogic-agent-home` mounted as container `HOME` (`/agent-home`). If authorization hangs after switching servers, set `CODELOGIC_FORCE_REGISTRATION` to `true` for one workflow run, then clear it.

Scripts: [`scripts/codelogic/`](../../scripts/codelogic/).

## [pin-check.yml](pin-check.yml)

Enforces SHA-pinned third-party actions on workflow changes. Updates via [Renovate](../../renovate.json).
