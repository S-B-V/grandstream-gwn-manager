
#!/usr/bin/env bash
set -Eeuo pipefail

# Grandstream GWN Manager - Public URL Configuration
#
# EXPERIMENTAL - local bootstrap only.
#
# Run once against newly initialized persistent volumes,
# before starting Grandstream services.
#
# Required:
#   GWN_ACCESS_ADDRESS
#   GWN_PUBLIC_HOST
#
# Optional:
#   GWN_PUBLIC_HTTPS_PORT (default: 443)
#
# GWN_ACCESS_ADDRESS is currently restricted to IPv4 because
# this is the format verified with GWN Manager 1.1.39.8.

: "${GWN_ACCESS_ADDRESS:?GWN_ACCESS_ADDRESS is required}"
: "${GWN_PUBLIC_HOST:?GWN_PUBLIC_HOST is required}"

export GWN_ACCESS_ADDRESS
export GWN_PUBLIC_HOST
export GWN_PUBLIC_HTTPS_PORT="${GWN_PUBLIC_HTTPS_PORT:-443}"

python3 - <<'PY'
import ipaddress
import os
import re
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

access_address = os.environ["GWN_ACCESS_ADDRESS"].strip()
public_host = os.environ["GWN_PUBLIC_HOST"].strip()

try:
    public_port = int(os.environ["GWN_PUBLIC_HTTPS_PORT"])
except ValueError:
    raise SystemExit("ERROR: Invalid HTTPS port")

if not 1 <= public_port <= 65535:
    raise SystemExit("ERROR: HTTPS port out of range")

# Validate controller access address.
try:
    ipaddress.IPv4Address(access_address)
except ipaddress.AddressValueError:
    raise SystemExit(
        "ERROR: GWN_ACCESS_ADDRESS must be a valid IPv4 address"
    )

# Validate public hostname or IP.
try:
    ip = ipaddress.ip_address(public_host)
    is_ip = True
except ValueError:
    is_ip = False

if not is_ip:
    labels = public_host.split(".")

    if (
        len(public_host) > 253
        or not all(
            re.fullmatch(
                r"[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?",
                label
            ) and len(label) <= 63
            for label in labels
        )
    ):
        raise SystemExit("ERROR: Invalid GWN_PUBLIC_HOST")

# IPv6 URL authorities require square brackets.
if is_ip and ip.version == 6:
    url_host = f"[{public_host}]"
else:
    url_host = public_host

authority = (
    url_host
    if public_port == 443
    else f"{url_host}:{public_port}"
)

def replace_https_url(old):
    parsed = urlsplit(old)

    if parsed.scheme != "https" or not parsed.netloc:
        raise ValueError(
            "Expected existing HTTPS URL"
        )

    return urlunsplit((
        "https",
        authority,
        parsed.path,
        parsed.query,
        parsed.fragment,
    ))

targets = {
    Path("/gwn/conf/gwn.conf"): {
        "access_address": lambda old: access_address,
    },
    Path("/gwn/conf/gwn/local_env.cfg"): {
        "web_domain": replace_https_url,
        "api_domain": replace_https_url,
    },
}

# Prepare and validate every change before writing anything.
prepared = {}

for path, replacements in targets.items():
    if not path.is_file():
        raise SystemExit(f"ERROR: Missing file: {path}")

    original = path.read_text()
    lines = original.splitlines(keepends=True)

    found = set()
    updated = []

    for line in lines:
        match = re.match(
            r"^(\s*([^=\s]+)\s*=\s*)(.*?)(\r?\n)?$",
            line,
        )

        if not match:
            updated.append(line)
            continue

        prefix, key, raw, newline = match.groups()

        if key not in replacements:
            updated.append(line)
            continue

        if key in found:
            raise SystemExit(
                f"ERROR: Duplicate setting {key} in {path}"
            )

        found.add(key)

        value = raw.strip()
        quote = ""

        if (
            len(value) >= 2
            and value[0] in ("'", '"')
            and value[-1] == value[0]
        ):
            quote = value[0]
            value = value[1:-1]

        try:
            new_value = replacements[key](value)
        except ValueError as exc:
            raise SystemExit(
                f"ERROR: {path}: {key}: {exc}"
            )

        updated.append(
            f"{prefix}{quote}{new_value}{quote}{newline or ''}"
        )

    missing = set(replacements) - found

    if missing:
        raise SystemExit(
            f"ERROR: Missing settings in {path}: "
            f"{', '.join(sorted(missing))}"
        )

    prepared[path] = "".join(updated)

# Write validated configuration.
for path, content in prepared.items():
    path.write_text(content)
    print(f"Configured {path}")

print(f"Controller access address: {access_address}")
print(f"Public HTTPS authority: {authority}")
print("GDMS and HTTP-specific settings unchanged")
PY
