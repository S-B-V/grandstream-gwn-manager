# Experimental: Grandstream installer targets a full AlmaLinux host.
FROM almalinux:9
ARG GWN_VERSION=1.1.39.8
ARG GWN_SHA256
RUN dnf -y install ca-certificates curl tar gzip procps-ng hostname iproute && dnf clean all
WORKDIR /tmp/gwn-installer
RUN test -n "$GWN_SHA256" || (echo 'GWN_SHA256 must be set to a reviewed checksum' >&2; exit 1)
RUN curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
      "https://firmware.grandstream.com/GWN_Manager-${GWN_VERSION}-AlmaLinux9.tar.gz" -o /tmp/gwn.tar.gz \
 && echo "${GWN_SHA256}  /tmp/gwn.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/gwn.tar.gz -C /tmp/gwn-installer \
 && find /tmp/gwn-installer -maxdepth 3 -name install -type f -print
# Installer behavior must be inspected before enabling installation and publishing.
# Running ./install in an ordinary Docker build may require systemd, RPM services, or privileges.
LABEL org.opencontainers.image.description="Experimental packaging of Grandstream GWN Manager"
CMD ["/bin/sh", "-c", "echo 'GWN Manager image is not runtime-ready; vendor installer integration must be validated' >&2; exit 1"]
