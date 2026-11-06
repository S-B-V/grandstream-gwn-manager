# Renovate updates and automatic GHCR publication

Your existing hosted Renovate app remains responsible for dependency PRs. No
second Renovate instance, personal access token, or manual checksum entry is
needed. The manual publishing workflow has been replaced by the main build.

## Update flow

1. Renovate reads the official Grandstream tools page through its HTML custom
   datasource and proposes the latest **AlmaLinux9 tar.gz** version in `VERSION`.
   Four-part versions are compared numerically, including the fourth component.
   Other Dockerfile and GitHub Actions updates retain the Monday schedule.
2. `Prepare upstream release PR` runs only for open `renovate[bot]` PRs from a
   `renovate/` branch in this same repository targeting `main`. It executes only
   trusted base-branch scripts. It reads release files from the PR as data,
   confirms an official download link, streams the archive to calculate SHA-256,
   and adds a commit containing the matching `upstream.json`, `SHA256SUM`,
   Containerfile default and both Kubernetes image references.
3. The preparation workflow explicitly dispatches `build.yml` for the updated
   branch. This is necessary because commits made using `GITHUB_TOKEN` do not
   automatically trigger another PR workflow. The dispatched run attaches its
   build check to the updated branch commit. An initial run on the incomplete
   Renovate commit may fail the synchronization check; evaluate the latest commit.
4. PR checks build the image with the pinned checksum, inspect its filesystem,
   audit key material and run fresh-volume bootstrap, all-service health/HTTPS,
   graceful shutdown, recreation and persistence tests. Runtime tests use a
   **4 GiB** container limit and verify all four JVMs use their 512 MiB heap caps.
   PR/branch runs do not log into or publish to GHCR.
5. You merge the completed, passing PR. The `main` push repeats the checks and
   builds/tests the exact candidate it publishes. Failed builds, checksum checks,
   audits or runtime tests prevent publication.

`upstream.json` is the version/archive-digest lock. `scripts/sync-release.py`
generates the legacy `VERSION`/`SHA256SUM` inputs, Containerfile default and image
tags from it; `--check` rejects inconsistent changes. For a manual release,
update the lock and run the synchronization script before committing.

The downloaded archive's calculated SHA-256 pins the reviewed bytes. It is not
an independently signed vendor authenticity proof. Builds reject a later
replacement of the archive at the same URL because its bytes no longer match
the PR's pinned checksum. Previously prepared branches retain their checksum.

## One-time GitHub setup

- Keep the existing Renovate app enabled for the repository. Its custom datasource
  must be supported by your Renovate service; no self-hosted bot is introduced.
- Commit all files in this updated repository to `main`, including the new
  `prepare-release-pr.yml`, scripts and tests. **Delete the obsolete
  `.github/workflows/publish.yml` and `.github/workflows/check-release.yml`**
  from your original checkout: overlaying ZIP files alone does not remove them.
- Allow Actions to run with the permissions declared in the workflows. The PR
  preparation job needs Contents write, Pull requests read and Actions write to
  commit generated release files and dispatch checks. The build job needs
  Packages write for publication on `main`. No workflow bypasses branch rules. The configuration ignores the preparation
  bot's commit author so Renovate can continue refreshing its PRs.
- Ensure the existing GHCR package grants this repository Actions write access.
  Publication uses the built-in `GITHUB_TOKEN`; no GHCR password is required.
- Require the `build-and-test` check on PRs before merging. Keep any existing
  manifest, workflow-lint and secret checks required as appropriate.
- No `ghcr-publish` environment or per-release manual approval is referenced by
  the new build. Existing organization-level approval rules may still apply.

Publication is enabled as requested; merging a release PR is the release decision.
The existing image audit remains a required automated check.

## Image tags and digests

For repository `S-B-V/grandstream-gwn-manager`, successful main builds publish:

- `ghcr.io/s-b-v/grandstream-gwn-manager:<version>-<full-commit-sha>`: immutable
  commit reference; retries retain the already published image.
- `ghcr.io/s-b-v/grandstream-gwn-manager:<version>`: created on first publication
  of a version and never replaced.
- `ghcr.io/s-b-v/grandstream-gwn-manager:latest`: the successful main build.

The workflow summary records the **registry image digest** for deployment with
`image@sha256:...`. That digest differs from the **installer archive SHA-256** in
`SHA256SUM`. Packaging rebuilds of an already published upstream version receive
new commit tags while its original version tag remains unchanged; use the commit
tag/digest or `latest` to consume that rebuild.

The supplied Kubernetes manifest uses `OnDelete`; publishing does not update or
restart a cluster. Applying a new version and replacing its pod remain deployment
steps. The workflow does not touch your local Rancher Desktop cluster.

## Validation of this change

Local checks cover version discovery, checksum association, input synchronization,
launcher argument preservation, PR preparation and publish error handling. Shell,
YAML, Renovate schema and GitHub Actions lint validation are run separately.
A complete new vendor-image build and GHCR publication must run in your repository
with its actual package permissions; they have not been performed by this chat.

Implementation references: [Renovate HTML custom datasources](https://docs.renovatebot.com/modules/datasource/custom/#html),
[Renovate commits from other bots](https://docs.renovatebot.com/configuration-options/#gitignoredauthors),
and [GitHub token workflow-trigger behavior](https://docs.github.com/en/actions/how-tos/writing-workflows/choosing-when-your-workflow-runs/triggering-a-workflow).
