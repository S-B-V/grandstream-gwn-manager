# Grandstream GWN Manager containerization (experimental)

**Status: NOT runtime-ready; NO published GHCR image.** The Grandstream AlmaLinux 9 vendor archive is designed for a full host installation, potentially installing database, nginx and services. Its installer contents were not accessible for validation in this environment. Do not treat the Containerfile as production-ready.

## Intended automation

- `check-release.yml`: daily check of Grandstream's official tools page and PR if a newer AlmaLinux9 archive is detected. The HTML filename parser is fail-closed and must be verified against the current page; if no version is matched it fails rather than guessing.
- `renovate.json`: Renovate GitHub App tracks Dockerfile/Containerfile base images and GitHub Actions. Renovate **does not automatically track this vendor tarball**; the scheduled checker handles upstream discovery.
- `dependabot.yml`: GitHub Dependabot tracks Docker and Actions dependencies; do not enable competing Renovate and Dependabot PRs for the same ecosystem without choosing one primary updater.
- `security.yml`: workflow lint and secret checks.
- `build.yml`: builds only after a manually reviewed SHA-256; it deliberately does not publish an unusable image.

## Required before publishing to GHCR

1. Inspect the downloaded archive and installer scripts (including dependencies and nested payloads).
2. Determine valid container runtime model for all required services (prefer separate managed services where possible); test boot, upgrade and persistent volume handling.
3. Verify checksum from the trusted vendor release or independently reviewed archive and put the raw SHA-256 into `SHA256SUM`.
4. Implement health checks and smoke tests (8443 web and 10014 device communication, plus databases and any additional needed ports).
5. Enable image signing, SBOM generation, image scanning, and GHCR push only after functional smoke tests pass.
6. Verify Grandstream terms allow third-party redistribution of the bundled binary and image.

Vendor docs: https://documentation.grandstream.com/knowledge-base/gwn-manager-quick-installation-guide/ ; downloads: https://www.grandstream.com/support/tools

## Bootstrap a repository

```bash
gh repo create S-B-V/grandstream-gwn-manager --public --source=. --remote=origin --push
```

Run the command from the extracted directory after `git init`, `git add .`, and `git commit -m 'Initial experimental scaffold'`. The connected GitHub account must have repository creation and push rights.
