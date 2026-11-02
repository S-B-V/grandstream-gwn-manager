
# Grandstream GWN Manager - AlmaLinux 9
# Experimental container using the official Grandstream installer.
# Do not replace the vendor installation procedure with direct RPM extraction.

FROM almalinux:9

ARG GWN_VERSION=1.1.39.8
ARG GWN_SHA256

# Install prerequisites and security updates.
# curl-minimal avoids conflicts with AlmaLinux's default curl package.
# brotli and libpsl are required by dependencies bundled with GWN Manager.
RUN dnf -y upgrade --refresh \
    && dnf -y install \
        ca-certificates \
        curl-minimal \
        tar \
        gzip \
        procps-ng \
        hostname \
        iproute \
        findutils \
        which \
        shadow-utils \
        iputils \
        glibc-langpack-en \
        brotli \
        libpsl \
        libaio \
    && dnf clean all

# Ensure failures inside pipelines are propagated.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /tmp/gwn-installer

# Require a reviewed SHA-256 checksum.
RUN test -n "$GWN_SHA256" \
    || { echo "Missing reviewed GWN_SHA256" >&2; exit 1; }

# Download and verify the official Grandstream archive.
RUN set -eux; \
    curl --fail --location --retry 3 \
        --proto '=https' --tlsv1.2 \
        "https://firmware.grandstream.com/GWN_Manager-${GWN_VERSION}-AlmaLinux9.tar.gz" \
        -o /tmp/gwn.tar.gz; \
    echo "${GWN_SHA256}  /tmp/gwn.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/gwn.tar.gz -C /tmp/gwn-installer; \
    test -f "/tmp/gwn-installer/GWN_Manager-${GWN_VERSION}-AlmaLinux9/install"

# Execute the official Grandstream installer.
# Capture its output and detect reported installation failures.
RUN set -eux; \
    cd "/tmp/gwn-installer/GWN_Manager-${GWN_VERSION}-AlmaLinux9"; \
    bash ./install 2>&1 | tee /tmp/gwn-install.log; \
    if grep -Fq "Install GWN Manager failed" /tmp/gwn-install.log; then \
        echo "Grandstream installer reported a failure" >&2; \
        exit 1; \
    fi; \
    test -x /gwn/gwn

COPY scripts/healthcheck.sh /usr/local/bin/healthcheck
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint
RUN chmod 755 /usr/local/bin/healthcheck /usr/local/bin/entrypoint

HEALTHCHECK --interval=30s --timeout=10s \
  --start-period=120s --retries=3 \
  CMD ["/usr/local/bin/healthcheck"]

# Remove temporary installer files after successful installation.
RUN rm -rf /tmp/gwn.tar.gz /tmp/gwn-installer

# GWN Manager management interface and device communication.
EXPOSE 8443/tcp 10014/tcp

STOPSIGNAL SIGTERM

# Experimental startup.
# The vendor launcher may daemonize its services.
# A proper process supervisor and runtime health checks are still required.
#CMD ["/bin/bash", "-c", "set -e; /gwn/gwn start; exec sleep infinity"]
ENTRYPOINT ["/usr/local/bin/entrypoint"]

LABEL org.opencontainers.image.title="Grandstream GWN Manager" \
      org.opencontainers.image.description="Experimental Grandstream GWN Manager container using the official vendor installer" \
      org.opencontainers.image.vendor="Community packaging - unofficial"
