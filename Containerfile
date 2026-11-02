# Grandstream GWN Manager - AlmaLinux 9
# Unofficial experimental container. Official Grandstream installer is mandatory.
FROM almalinux:9

ARG GWN_VERSION=1.1.39.8
ARG GWN_SHA256

RUN dnf -y upgrade --refresh \
    && dnf -y install \
       ca-certificates curl-minimal tar gzip procps-ng hostname iproute \
       findutils which shadow-utils iputils glibc-langpack-en \
       brotli libpsl libaio \
    && dnf clean all

WORKDIR /tmp/gwn-installer

RUN test -n "$GWN_SHA256" || { echo 'Missing reviewed GWN_SHA256' >&2; exit 1; }

RUN set -eux; \
    curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
      "https://firmware.grandstream.com/GWN_Manager-${GWN_VERSION}-AlmaLinux9.tar.gz" \
      -o /tmp/gwn.tar.gz; \
    echo "${GWN_SHA256}  /tmp/gwn.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/gwn.tar.gz -C /tmp/gwn-installer; \
    test -f "/tmp/gwn-installer/GWN_Manager-${GWN_VERSION}-AlmaLinux9/install"

# Explicit Bash pipefail because OCI build output ignores the SHELL instruction.
RUN /bin/bash -o pipefail -c '\
    set -eux; \
    cd "/tmp/gwn-installer/GWN_Manager-${GWN_VERSION}-AlmaLinux9"; \
    bash ./install 2>&1 | tee /tmp/gwn-install.log; \
    if grep -Fq "Install GWN Manager failed" /tmp/gwn-install.log; then \
      echo "Grandstream installer reported a failure" >&2; exit 1; \
    fi; \
    test -x /gwn/gwn'

# Preserve pristine vendor-created directory trees for first-run PVC initialization.
# NOTE: inspect these files for bundled credentials and secrets before publication.
RUN mkdir -p /opt/gwn-defaults/data /opt/gwn-defaults/conf \
    && cp -a /gwn/data/. /opt/gwn-defaults/data/ \
    && cp -a /gwn/conf/. /opt/gwn-defaults/conf/ \
    && test -f /opt/gwn-defaults/conf/gwn.conf

COPY scripts/healthcheck.sh /usr/local/bin/healthcheck
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint
RUN chmod 755 /usr/local/bin/healthcheck /usr/local/bin/entrypoint \
    && rm -rf /tmp/gwn.tar.gz /tmp/gwn-installer

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
  CMD ["/usr/local/bin/healthcheck"]

EXPOSE 8443/tcp 10014/tcp 8000/tcp
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/bin/entrypoint"]

LABEL org.opencontainers.image.title="Grandstream GWN Manager" \
      org.opencontainers.image.description="Experimental GWN Manager container using official vendor installer" \
      org.opencontainers.image.vendor="Community packaging - unofficial"
