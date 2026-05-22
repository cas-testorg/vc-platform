# Workflows

## [platform-ci.yml](platform-ci.yml)

Runs on **`dev`** only (push, pull request, manual dispatch).

1. Restore, build, and publish to `artifacts/out` (log: `logs/build.log`)
2. Upload `dotnet-publish` and `dotnet-build-log` artifacts
3. CodeLogic scan of published binaries
4. `send_build_info` with build log and repository metadata

### CodeLogic (optional until configured)

| Kind | Name |
|------|------|
| Variable | `CODELOGIC_HOST` |
| Secret | `AGENT_UUID`, `AGENT_PASSWORD` |
| Variable (optional) | `CODELOGIC_APPLICATION_NAME`, `CODELOGIC_SCAN_SPACE_NAME`, `CODELOGIC_DATABASE_IDENTITIES` |

Scripts: [`scripts/codelogic/`](../../scripts/codelogic/).

## [pin-check.yml](pin-check.yml)

Enforces SHA-pinned third-party actions on workflow changes. Updates via [Renovate](../../renovate.json).
