# Experimental execution of the official Grandstream AlmaLinux 9 installer.
# Preserve the vendor installation path; do not replace it with direct RPM extraction.
FROM almalinux:9
ARG GWN_VERSION=1.1.39.8
ARG GWN_SHA256
RUN dnf -y upgrade --refresh \
 && dnf -y install ca-certificates curl-minimal tar gzip procps-ng hostname iproute \
      findutils which shadow-utils iputils glibc-langpack-en \
 && dnf clean all
WORKDIR /tmp/gwn-installer
RUN test -n "$GWN_SHA256" || (echo 'Missing reviewed GWN_SHA256' >&2; exit 1)
RUN set -eux; \
    curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
      "https://firmware.grandstream.com/GWN_Manager-${GWN_VERSION}-AlmaLinux9.tar.gz" -o /tmp/gwn.tar.gz; \
    echo "${GWN_SHA256}  /tmp/gwn.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/gwn.tar.gz -C /tmp/gwn-installer; \
    test -f "/tmp/gwn-installer/GWN_Manager-${GWN_VERSION}-AlmaLinux9/install"
# The vendor installer may require systemd, interactive input or full-host services.
# If this step fails, inspect its log; do not suppress errors or bypass vendor logic.
RUN set -eux; \
    cd "/tmp/gwn-installer/GWN_Manager-${GWN_VERSION}-AlmaLinux9"; \
    bash ./install
RUN test -x /gwn/gwn || (echo 'Vendor installation did not create /gwn/gwn' >&2; exit 1)
EXPOSE 8443/tcp 10014/tcp
# /gwn/gwn starts daemons and can return; preserve a foreground PID 1 while they run.
# A service/process health check must be implemented once the installer runs successfully.
STOPSIGNAL SIGTERM
CMD ["/bin/bash", "-c", "set -e; /gwn/gwn start; exec sleep infinity"]
LABEL org.opencontainers.image.description="Experimental Grandstream GWN Manager using official vendor installer"
