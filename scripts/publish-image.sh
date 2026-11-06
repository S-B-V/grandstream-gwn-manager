#!/usr/bin/env bash
set -Eeuo pipefail
image=${1:?usage: publish-image.sh TESTED_IMAGE}
: "${REPO:?}" "${GWN_VERSION:?}" "${GITHUB_SHA:?}"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]
[[ "$GWN_VERSION" =~ ^[0-9]+(\.[0-9]+){3}$ ]]
[[ "$GITHUB_SHA" =~ ^[a-f0-9]{40}$ ]]
repo="ghcr.io/${REPO,,}"
commit_ref="$repo:$GWN_VERSION-$GITHUB_SHA"
version_ref="$repo:$GWN_VERSION"
registry_error=$(mktemp)
trap 'rm -f "$registry_error"' EXIT
exists() {
  if docker manifest inspect "$1" >/dev/null 2>"$registry_error"; then
    return 0
  fi
  # Do not mistake a permissions, credentials or network failure for absence.
  if grep -Eiq 'manifest unknown|no such manifest|name unknown' "$registry_error"; then
    return 1
  fi
  cat "$registry_error" >&2
  exit 1
}
if exists "$commit_ref"; then
  echo "Commit image already published; retaining $commit_ref"
  docker pull "$commit_ref" >/dev/null
else
  docker tag "$image" "$commit_ref"
  docker push "$commit_ref"
fi
# A released version tag is never replaced. Packaging rebuilds get commit tags.
if exists "$version_ref"; then
  echo "Retaining existing version tag: $version_ref"
else
  docker tag "$commit_ref" "$version_ref"
  docker push "$version_ref"
fi
docker tag "$commit_ref" "$repo:latest"
docker push "$repo:latest"
digest=$(docker image inspect "$commit_ref" --format '{{index .RepoDigests 0}}')
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "Published: $commit_ref"
    echo
    echo "Image digest: $digest"
    echo
    echo "Moving tag: $repo:latest; version tag retained once published."
  } >> "$GITHUB_STEP_SUMMARY"
fi
