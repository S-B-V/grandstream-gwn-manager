# Experimental community packaging.
# Do not publish without authorization and security review.
FROM almalinux:10 AS installer

ARG GWN_VERSION=1.1.39.8
ARG GWN_SHA256

RUN dnf -y upgrade --refresh && \
    dnf -y install \
      ca-certificates curl-minimal tar gzip procps-ng hostname iproute \
      findutils which shadow-utils iputils glibc-langpack-en \
      brotli libpsl libaio libxcrypt-compat openssl && \
    dnf clean all

WORKDIR /tmp/gwn-installer
RUN test -n "$GWN_SHA256"
RUN set -eux; \
    curl --fail --location --retry 3 \
      --proto '=https' --tlsv1.2 \
      "https://firmware.grandstream.com/GWN_Manager-${GWN_VERSION}-AlmaLinux9.tar.gz" \
      -o /tmp/gwn.tar.gz; \
    echo "${GWN_SHA256}  /tmp/gwn.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/gwn.tar.gz; \
    test -f "GWN_Manager-${GWN_VERSION}-AlmaLinux9/install"

RUN /bin/bash -o pipefail -c '\
    set -eu; \
    cd "/tmp/gwn-installer/GWN_Manager-${GWN_VERSION}-AlmaLinux9"; \
    bash ./install > /tmp/gwn-install.log 2>&1; \
    ! grep -Fq "Install GWN Manager failed" /tmp/gwn-install.log; \
    test -x /gwn/gwn \
'

# Keep vendor defaults, omit machine-specific DB and private-key material.
RUN set -eu; \
    mkdir -p /export/gwn /export/defaults/data /export/defaults/conf; \
    tar -C /gwn \
      --exclude='./data' --exclude='./conf' \
      --exclude='./apps/email/node_modules/public-encrypt/test' \
      --exclude='./scripts/prikey.pem' \
      -cf - . | tar -C /export/gwn -xf -; \
    tar -C /gwn/data \
      --exclude='./mysql' --exclude='*.key' --exclude='*.p12' \
      --exclude='*.pfx' --exclude='*.jks' --exclude='*private-key*' \
      -cf - . | tar -C /export/defaults/data -xf -; \
    tar -C /gwn/conf \
      --exclude='*.key' --exclude='*.p12' --exclude='*.pfx' \
      --exclude='*.jks' --exclude='*private-key*' \
      -cf - . | tar -C /export/defaults/conf -xf -

FROM almalinux:10

RUN groupadd -g 1000 gwn && \
    useradd -u 1000 -g 1000 -d /gwn -s /bin/bash -M gwn

RUN groupadd --system sshd && \
    useradd --system --gid sshd --home-dir /var/empty/sshd \
      --shell /sbin/nologin --no-create-home sshd && \
    mkdir -p /var/empty/sshd && \
    chown root:root /var/empty/sshd && chmod 755 /var/empty/sshd

# freetype/fontconfig/fonts are required by the vendor JRE's
# libfontmanager.so, used when generating Excel configuration exports.
RUN dnf -y upgrade --refresh && \
    dnf -y install \
      ca-certificates curl-minimal tar gzip procps-ng hostname iproute \
      findutils which shadow-utils iputils glibc-langpack-en \
      brotli libpsl libaio libxcrypt-compat openssl \
      freetype fontconfig dejavu-sans-fonts && \
    dnf clean all

COPY --from=installer /export/gwn/ /gwn/
COPY --from=installer /gwn/bin/jre/conf/ /gwn/bin/jre/conf/
COPY --from=installer /export/defaults/data/ /opt/gwn-defaults/data/
COPY --from=installer /export/defaults/conf/ /opt/gwn-defaults/conf/

# Fail image build if any fontmanager native shared library is missing.
RUN set -eu; \
    test -f /gwn/bin/jre/lib/libfontmanager.so; \
    ldd /gwn/bin/jre/lib/libfontmanager.so > /tmp/fontmanager-ldd.txt; \
    cat /tmp/fontmanager-ldd.txt; \
    ! grep -q 'not found' /tmp/fontmanager-ldd.txt; \
    rm /tmp/fontmanager-ldd.txt

# /gwn_backup is provided by the Kubernetes StatefulSet as emptyDir.
# Do not symlink this path to the persistent MariaDB/data PVC.
RUN mkdir -p /gwn_backup && chown 1000:1000 /gwn_backup && chmod 0770 /gwn_backup

COPY scripts/entrypoint.sh /usr/local/bin/entrypoint
COPY scripts/java-memory-limited.sh /usr/local/bin/gwn-java-memory
COPY scripts/healthcheck.sh /usr/local/bin/healthcheck
COPY scripts/pki-bootstrap.sh /usr/local/bin/pki-bootstrap
COPY scripts/configure-public-url.sh /usr/local/bin/configure-public-url

RUN chmod 755 \
      /usr/local/bin/entrypoint \
      /usr/local/bin/gwn-java-memory \
      /usr/local/bin/healthcheck \
      /usr/local/bin/pki-bootstrap \
      /usr/local/bin/configure-public-url

RUN cat > /usr/local/bin/gwn-runtime-entrypoint <<'EOS'
#!/bin/bash
set -euo pipefail

SSH_DIR="/gwn/conf/sshd"
if [ -d "$SSH_DIR" ]; then
    shopt -s nullglob
    for key in "$SSH_DIR"/ssh_host_*_key; do
        if [ -f "$key" ] && [ ! -L "$key" ]; then
            chmod 600 "$key"
            echo "Corrected SSH host key permissions: $key"
        fi
    done
fi
exec /usr/local/bin/entrypoint "$@"
EOS

RUN chmod 755 /usr/local/bin/gwn-runtime-entrypoint
RUN set -eu; \
    getent passwd sshd; getent group sshd; \
    test -x /gwn/bin/sshd/sshd; \
    test -f /opt/gwn-defaults/conf/sshd/sshd_config_temp; \
    test -d /var/empty/sshd; \
    test -x /usr/local/bin/gwn-runtime-entrypoint; \
    test -d /gwn_backup

EXPOSE 8443/tcp 10014/tcp 8000/tcp
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/bin/gwn-runtime-entrypoint"]
LABEL org.opencontainers.image.description="EXPERIMENTAL - not verified for clean bootstrap or redistribution"
