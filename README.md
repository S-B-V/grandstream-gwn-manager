# Grandstream GWN Manager - local experimental handover package

**Start with [`docs/HANDOVER.md`](docs/HANDOVER.md)**. This is an overlay of replacement/additional files for the existing local repository, NOT a complete cloned repository. `VERSION` and `SHA256SUM` stay in your local repository. No changes were pushed to GitHub.

Status: **UNTESTED fresh-volume PKI, NOT publishable**. Known serious concern: installer-initialized DB contents in image defaults require sensitive-data and redistribution review. Do not treat a passing key-file audit as security approval.

Basic use after review: copy the overlay into local repo, build with `podman build --network=host --build-arg GWN_SHA256="$(cat SHA256SUM)" -t localhost/gwn-manager:secure-test .`, then run `bash scripts/test-clean-local.sh` on dedicated new Podman volumes.
