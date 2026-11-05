
# Experimental community packaging.
# Do not publish without authorization and security review.

FROM almalinux:9 AS installer

ARG GWN_VERSION=1.1.39.8
ARG GWN_SHA256

RUN dnf -y upgrade --refresh && \
    dnf -y install \
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
      libxcrypt-compat \
      openssl && \
    dnf clean all

WORKDIR /tmp/gwn-installer

RUN test -n "$GWN_SHA256"

# Download and verify official Grandstream installer.
RUN set -eux; \
    curl --fail --location --retry 3 \
      --proto '=https' \
      --tlsv1.2 \
      "https://firmware.grandstream.com/GWN_Manager-${GWN_VERSION}-AlmaLinux9.tar.gz" \
      -o /tmp/gwn.tar.gz; \
    echo "${GWN_SHA256}  /tmp/gwn.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/gwn.tar.gz; \
    test -f "GWN_Manager-${GWN_VERSION}-AlmaLinux9/install"

# Execute vendor installation.
RUN /bin/bash -o pipefail -c '\
    set -eu; \
    cd "/tmp/gwn-installer/GWN_Manager-${GWN_VERSION}-AlmaLinux9"; \
    bash ./install > /tmp/gwn-install.log 2>&1; \
    ! grep -Fq "Install GWN Manager failed" /tmp/gwn-install.log; \
    test -x /gwn/gwn \
'

# Export application files and default configuration.
#
# Known private keys from Node.js test fixtures are excluded.
# Grandstream scripts/prikey.pem is excluded provisionally.
#
# WARNING:
# Database snapshots may contain installation-specific secrets.
# Redistribution remains blocked pending security review.

RUN set -eu; \
    mkdir -p \
      /export/gwn \
      /export/defaults/data \
      /export/defaults/conf; \
    \
    tar -C /gwn \
      --exclude='./data' \
      --exclude='./conf' \
      --exclude='./apps/email/node_modules/public-encrypt/test' \
      --exclude='./scripts/prikey.pem' \
      -cf - . | tar -C /export/gwn -xf -; \
    \
    # Exclude active installer database.
    # Keep vendor mysql_default template for runtime bootstrap.
    tar -C /gwn/data \
      --exclude='./mysql' \
      --exclude='*.key' \
      --exclude='*.p12' \
      --exclude='*.pfx' \
      --exclude='*.jks' \
      --exclude='*private-key*' \
      -cf - . | tar -C /export/defaults/data -xf -; \
    \
    tar -C /gwn/conf \
      --exclude='*.key' \
      --exclude='*.p12' \
      --exclude='*.pfx' \
      --exclude='*.jks' \
      --exclude='*private-key*' \
      -cf - . | tar -C /export/defaults/conf -xf -

# ------------------------------------------------------------
# Runtime image
# ------------------------------------------------------------

FROM almalinux:9

RUN groupadd -g 1000 gwn && \
    useradd \
      -u 1000 \
      -g 1000 \
      -d /gwn \
      -s /bin/bash \
      -M gwn

RUN dnf -y upgrade --refresh && \
    dnf -y install \
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
      libxcrypt-compat \
      openssl && \
    dnf clean all

# Copy application without the known private-key fixtures.
COPY --from=installer /export/gwn/ /gwn/

# Vendor Java 17 security configuration.
# Required to prevent Java initialization errors.
COPY --from=installer /gwn/bin/jre/conf/ /gwn/bin/jre/conf/

# Copy vendor defaults for runtime initialization.
COPY --from=installer /export/defaults/data/ /opt/gwn-defaults/data/
COPY --from=installer /export/defaults/conf/ /opt/gwn-defaults/conf/

# Runtime scripts.
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint
COPY scripts/healthcheck.sh /usr/local/bin/healthcheck
COPY scripts/pki-bootstrap.sh /usr/local/bin/pki-bootstrap
COPY scripts/configure-public-url.sh /usr/local/bin/configure-public-url

RUN chmod 755 \
      /usr/local/bin/entrypoint \
      /usr/local/bin/healthcheck \
      /usr/local/bin/pki-bootstrap \
      /usr/local/bin/configure-public-url

# GWN Manager web interface and device communication.
EXPOSE 8443/tcp 10014/tcp 8000/tcp

STOPSIGNAL SIGTERM

ENTRYPOINT ["/usr/local/bin/entrypoint"]

LABEL org.opencontainers.image.description="EXPERIMENTAL - not verified for clean bootstrap or redistribution"
