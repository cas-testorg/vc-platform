# Workflows

GitHub Actions workflows for this repo.

## Primary CI

**[platform-ci.yml](platform-ci.yml)** — build, test, package, and publish on push/PR to `master` and `dev`:

| Trigger | Behavior |
|---------|----------|
| `pull_request` | Compile, unit tests, package, Docker build |
| `push` → `dev` | Above + blob publish + Docker publish |
| `push` → `master` | Above + NuGet publish + GitHub release + Docker publish |
| `workflow_dispatch` | Same pipeline; optional `forceLatest` for Docker tag |

Post-build automation (Sonar, Jira, cloud deploy, E2E, OWASP, Trivy) has been removed to keep the pipeline focused on build/publish. Re-enable as separate workflows or jobs when needed.

## Manual workflows

| Workflow | Purpose |
|----------|---------|
| [release.yml](release.yml) | Release via shared VirtoCommerce workflow |
| [publish-nugets.yml](publish-nugets.yml) | Manual NuGet publish |
| [platform-release-hotfix.yml](platform-release-hotfix.yml) | Hotfix release |
| [deploy.yml](deploy.yml) | ArgoCD deploy by artifact URL |

## Supply-chain security: pinned third-party actions

Every third-party `uses:` reference in this repo (anything not under `VirtoCommerce/*`) is pinned to a full 40-character commit SHA with a trailing `# tag` comment, per the [GitHub Actions hardening guide](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions#using-third-party-actions). Tags are mutable; SHAs are not.

```yaml
# Correct
uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6

# Rejected by CI
uses: actions/checkout@v6
```

### How updates happen

- **Renovate** ([`renovate.json`](../../renovate.json)) opens grouped PRs for GitHub Actions digest bumps (`pinDigests: true`). Approve updates from the Renovate dependency dashboard when ready.
- **Pin-check CI** ([`pin-check.yml`](pin-check.yml)) runs `pinact run -check` on every PR that touches workflows. PRs with unpinned third-party `uses:` lines fail.
- **Scope** is configured in [`.pinact.yaml`](../../.pinact.yaml) at the repo root — `VirtoCommerce/*` is intentionally ignored (internal, not third-party).

### For contributors

- When adding a new third-party action, write the SHA, not the tag. Quick lookup:

  ```sh
  gh api repos/OWNER/REPO/commits/TAG --jq '.sha'
  ```

- `VirtoCommerce/vc-github-actions/<dir>@master` and other `VirtoCommerce/*` refs remain version-/branch-pinned as before — only non-VirtoCommerce owners require SHA pinning.

## Secrets

**Required for platform-ci:** `REPO_TOKEN`, `NUGET_KEY`, `BLOB_TOKEN`, `DOCKER_USERNAME`, `DOCKER_TOKEN`, plus repo variable `BLOB_URL` where blob publish runs.

**Unused by current workflows** (safe to leave in GitHub until other automation returns): `SONAR_TOKEN`, `CLOUD_*`, `CLIENT_*`, `JIRA_*`, `VC_TESTING_*`, `SENDGRID_*`, `PLATFORM_TEAMS_URI`.
