# Container build and releases

GitHub Actions builds and tests the GWN Manager image and publishes successful builds from `main` to GitHub Container Registry (GHCR).

## Use

1. Enable GitHub Actions and the repository's existing Renovate integration.
2. Review and merge an upstream-version update pull request after its checks pass.
3. A successful build on `main` publishes the tested container image to `ghcr.io/s-b-v/grandstream-gwn-manager`.
4. Deploy the desired image tag or digest using [README-k8s.md](README-k8s.md).

## Image tags

- `<version>-<commit-sha>` identifies a build from a specific repository commit.
- `<version>` identifies the first published build of that upstream version and is not overwritten.
- `latest` points to the most recently published successful build from `main`.

An image is published only after its build and checks succeed. The release workflow does not automatically update a running Kubernetes installation.
