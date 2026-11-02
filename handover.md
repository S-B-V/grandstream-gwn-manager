# Handover — Grandstream GWN Manager containerization

**Last updated:** 2026-11-01 (Europe/Berlin)  
**Repository:** https://github.com/S-B-V/grandstream-gwn-manager  
**Target:** AlmaLinux 9 container running the **official Grandstream installer**, then GHCR publishing and deployment to K3s.  
**Current state:** Vendor installer succeeds; container starts with persisted data/config volumes; most services are running. **Do not consider production-ready.**

## Non-negotiable design decisions

- Use the **official Grandstream `install` script**, not manual RPM extraction or replacement installation logic.
- Preserve checksum verification of the upstream tarball; updates require reviewing a new SHA-256.
- Do not enable GHCR publishing until runtime, persistence, and shutdown tests pass.
- Run rootless Podman on Fedora for local validation, with SELinux enforcing.
- Do not publish bundled DB passwords, RADIUS secrets, certificates, or private configuration in CI logs/issues/commits.

## Version, image and upstream

- Version: `1.1.39.8` in repository `VERSION`.
- URL template: `https://firmware.grandstream.com/GWN_Manager-${GWN_VERSION}-AlmaLinux9.tar.gz`.
- SHA256 in repository `SHA256SUM`; checksum confirmed during local build. **Do not change without verifying new upstream archive.**
- Image built successfully with Podman: `localhost/gwn-manager:test`.
- Important build option on this Fedora machine: `podman build --network=host` (Podman build DNS otherwise intermittently failed on AlmaLinux mirrorlist).
- Dependencies added to AlmaLinux before executing installer: `ca-certificates curl-minimal tar gzip procps-ng hostname iproute findutils which shadow-utils iputils glibc-langpack-en brotli libpsl libaio` plus `dnf upgrade --refresh`.
- `curl-minimal` avoids a conflict with `curl`; `brotli`/`libpsl` solved bundled RPM prerequisites, `libaio` solved `gwn-mariadb` RPM dependency.
- Podman warns `SHELL` Containerfile instruction is ignored for OCI output. Either make pipeline verification explicitly use `bash -o pipefail -c ...`, or build `--format docker`; prefer explicit shell in the specific `RUN` line rather than relying on global `SHELL`.

## Repository automation inspected

- `.github/workflows/build.yml`: builds experimentally; no GHCR push currently.
- `.github/workflows/security.yml`: security checks.
- `.github/workflows/check-release.yml`: scheduled upstream release detection / proposed PR.
- `.github/workflows/inspect-installer.yml`: installer inventory artifact.
- `renovate.json` and Dependabot configuration are present; avoid duplicate competing PRs for same ecosystem.
- A successful inspection run was observed: https://github.com/S-B-V/grandstream-gwn-manager/actions/runs/41309363611
- GitHub connector was **read-only for this repo** when checked, so edits must be committed/pushed locally unless connection permissions change.

## Verified local install/runtime

- Official vendor installer printed `Install GWN Manager successfully.` and generated `/gwn/gwn`.
- Earlier run returned `HTTP/1.1 200 OK` on `https://localhost:8443` with Nginx 1.28.0.
- Services in the **latest reported** `podman exec gwn-manager /gwn/gwn status`:
  - Redis: running
  - Mysql/MariaDB: running
  - Nginx: running
  - Sshd: running
  - User: running
  - Router: running
  - Email: running
  - Gateway: running
  - Link: running
  - **Web: starting**
  - **Checker: stopped**
- This is a snapshot taken during initialization; check again before diagnosing failures. A previous non-persistent run reported all ten core application services running (SSH aside).
- HTTPS can serve a static page even if backend Web/Checker services are not ready. `curl -k -I` **alone is not an adequate readiness check**.
- Vendor launcher advertises `access_address=172.17.2.243` from persistent `/gwn/conf/gwn.conf`: this is an internal Podman address; update via Grandstream-supported method to a reachable controller address before deployment.
- Installer/runtime prints `grep: /etc/ssh/sshd_config: No such file or directory` despite successfully starting application services; do not blindly install host SSH or weaken container isolation to silence this.

## Persistent storage: verified directory layout

- Volumes: `gwn-data` mounted at `/gwn/data`, `gwn-conf` mounted at `/gwn/conf`.
- `/gwn/data/mysql/data` is the active MariaDB datadir; `mysqld` uses `/gwn/conf/mysql/my.cnf` and runs as vendor `gwn` account.
- Other paths: `/gwn/data/redis`, `/gwn/data/gwn`, `/gwn/data/nginx`, and `/gwn/data/mysql_default` (possible template, retain).
- Configuration: `/gwn/conf/gwn.conf`, `/gwn/conf/mysql/my.cnf`, `/gwn/conf/nginx/nginx.conf`, `/gwn/conf/redis/` plus certificates.
- `/gwn/bin` and `/gwn/apps` are image-managed (not mounted).
- `/gwn/logs` currently **not persisted**; logs remain in container writable layer. Consider log output and rotation later.
- Original container preserved under name `gwn-manager-old`, as fallback. It was previously restarted for inspection; verify current state/port conflicts before starting or stopping containers.

### Permission incident and fix

An initial copy via `podman cp ... | tar --strip-components=2` incorrectly flattened directory layout. Then copying staged paths with `cp -a` caused mismatched root ownership and SELinux `user_tmp_t` labels; startup produced permission errors. Corrected by recreating volumes, copying source contents with correct directory tree, restoring ownership and applying accessible SELinux label.

The working verification output was:

```text
/conf/mysql: uid 1000, gid 1000, system_u:object_r:container_file_t:s0
/data/mysql/data: uid 1000, gid 1000, system_u:object_r:container_file_t:s0
Ownership and persistence OK
```

Vendor service account: `gwn` UID/GID `1000:1000`.

Recorded fix (only if needed again; ensure containers are stopped and volumes correctly populated):

```bash
DATA_VOL=$(podman volume inspect gwn-data --format '{{.Mountpoint}}')
CONF_VOL=$(podman volume inspect gwn-conf --format '{{.Mountpoint}}')
podman unshare chown -R 1000:1000 "$DATA_VOL" "$CONF_VOL"
podman unshare chcon -R -t container_file_t -l s0 "$DATA_VOL" "$CONF_VOL"
```

`container_file_t:s0` is a *shared* SELinux label used for the local diagnostic test; for final deployment, prefer proper per-container private labeling and suitable ownership. Avoid `:Z` on a temporary helper container followed by a second container because a fresh private MCS label can make the volume unreadable from the next container. Do not use `chmod 777`, `--privileged`, or disable SELinux as a workaround.

## Reproduce current local run

Only if there is no other active `gwn-manager` container and the named volumes are intact:

```bash
podman ps -a --filter name=gwn-manager
podman volume ls
podman run -d --name gwn-manager \
  -p 8443:8443 -p 10014:10014 \
  -v gwn-data:/gwn/data \
  -v gwn-conf:/gwn/conf \
  localhost/gwn-manager:test

podman logs --tail 100 gwn-manager
podman exec gwn-manager /gwn/gwn status
curl -k -I https://localhost:8443
podman healthcheck run gwn-manager
podman inspect gwn-manager --format '{{.State.Health.Status}}'
```

Do **not** discard `gwn-manager-old` yet. Do **not** delete `gwn-data` / `gwn-conf` (they now hold the persisted DB and configuration). Avoid copying database files while MariaDB is running; use a clean vendor stop or an application-consistent backup.

## Current Containerfile design

- AlmaLinux 9; pinned GWN version and reviewed SHA256 build args.
- Download and check vendor archive; extract; `bash ./install` with logged output; detect vendor string `Install GWN Manager failed`; assert executable `/gwn/gwn`.
- `scripts/healthcheck.sh` was requested and added in user's posted Containerfile, but **its exact repository/current image contents have not been reverified**. Previously proposed script checks 10 core services plus HTTPS. Because `sshd` also appears in status, decide deliberately whether it is essential.
- `HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3`.
- `EXPOSE 8443/tcp 10014/tcp`; runtime also reports HTTP port **8000** (GWN771X); review network requirements including other controller/device UDP ports before K3s manifests.
- Current `CMD` is `bash -c 'set -e; /gwn/gwn start; exec sleep infinity'`.
- **This CMD does not shut down services cleanly**: `podman stop --time 60` timed out and used SIGKILL. This can harm MariaDB consistency. Prior suggestions included an entrypoint invoking `/gwn/gwn stop` on SIGTERM, but it has NOT been implemented/validated.

## Next steps in order

1. **Confirm convergence:** Run `/gwn/gwn status` after Web and Checker have time to initialize. If not running, inspect `/gwn/logs/gwn` and relevant service logs. Run health check; verify full app beyond Nginx static page.
2. **Graceful shutdown:** Add `scripts/entrypoint.sh` as PID 1, trap SIGTERM/SIGINT, run `/gwn/gwn stop`, wait for services (especially MariaDB) to exit, and exit nonzero when critical services die unexpectedly. Avoid `sleep infinity` and verify `podman stop --time 60` no longer invokes SIGKILL. If using a shell monitor loop, ensure signals interrupt waits and log clearly.
3. **Persistence recreation test:** After a clean shutdown, recreate container with same volumes, verify app config/data and MariaDB integrity. Test modifications through UI if possible. Consider backup before testing.
4. **Initialize fresh named volumes safely:** Provide repeatable first-run initialization from image's vendor-created `/gwn/data` and `/gwn/conf`, without hiding or overwriting populated databases, preserving UID 1000 permissions. The first local volume copy was manual, not built into the image.
5. **Controller address/network:** Configure stable address accessible from managed Grandstream devices and map required TCP/UDP ports; avoid using old container IP.
6. **Security/operations:** Credentials exposed in an earlier transcript: **rotate database password and RADIUS secret**, and any other shared secrets before production. Do not copy these into this handover. Avoid public logs with `gwn.conf`. Assess bundled software CVEs and image scanning; verify redistribution rights before publishing vendor software in public GHCR.
7. **CI/GHCR:** Add startup smoke tests, Trivy, SBOM, Cosign signatures, and guarded GHCR publish after functional success. Ensure Renovate/Dependabot update ownership is clear. Then K3s manifests with PVCs, probes, resource sizing, and appropriate security context.

## Not-yet-proven / caveats

- The persistent volumes are correctly mounted and services restarted from them, but **end-to-end data retention across a second clean recreate is still unverified**.
- Graceful shutdown is still absent.
- Application Web and Checker services last reported not fully up.
- No GHCR image has been published by the project workflow yet.
- Running entirely as vendor `gwn` UID 1000 without extra privileges is not validated; vendor installation currently provisions SSHD and other local services.

## Handover prompt for next ChatGPT session

> Continue containerization of https://github.com/S-B-V/grandstream-gwn-manager using this handover.md. Vendor installer is mandatory. Local Podman image built and application launches with persistent named volumes `gwn-data` and `gwn-conf`; permissions fixed to UID 1000 and SELinux container_file_t:s0. Latest status showed Web starting, Checker stopped; verify they finish. Next implement/test clean signal-driven shutdown and persistence recreation, then fresh-volume bootstrap, security checks, GHCR, and K3s deployment. Do not expose credentials or delete original fallback container `gwn-manager-old`.
