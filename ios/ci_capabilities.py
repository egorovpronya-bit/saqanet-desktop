#!/usr/bin/env python3
"""Enable the VPN capabilities on both bundle IDs before profiles are created.

App Store profiles only allow the entitlements that were on the App ID at the
moment the profile was created. Network Extensions and Personal VPN have no
extra settings. App Groups must name group.ru.saqanet.vpn.
"""

import os
import re
import shutil
import subprocess
import sys


def _python_with_codemagic():
    """The builder's python3 does not have the Codemagic package. The CLI does."""
    if os.environ.get("SAQANET_CM_PYTHON_REEXEC") == "1":
        return None
    asc = shutil.which("app-store-connect")
    if not asc:
        return None
    candidates = []
    try:
        with open(asc, "r", encoding="utf-8", errors="replace") as handle:
            first = handle.readline().strip()
    except OSError:
        first = ""
    if first.startswith("#!"):
        parts = first[2:].strip().split()
        if parts and os.path.basename(parts[0]) == "env" and len(parts) > 1:
            found = shutil.which(parts[1])
            if found:
                candidates.append(found)
        elif parts and os.path.isfile(parts[0]):
            candidates.append(parts[0])
    bindir = os.path.dirname(os.path.realpath(asc))
    for name in ("python3", "python"):
        path = os.path.join(bindir, name)
        if os.path.isfile(path):
            candidates.append(path)
    current = os.path.realpath(sys.executable)
    for candidate in candidates:
        if os.path.realpath(candidate) == current:
            continue
        probe = subprocess.run(
            [candidate, "-c", "import codemagic"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if probe.returncode == 0:
            return candidate
    return None


def _ensure_codemagic_importable():
    try:
        import codemagic  # noqa: F401
    except ModuleNotFoundError:
        executable = _python_with_codemagic()
        if not executable:
            print(
                "python3 has no codemagic package, and the app-store-connect "
                "interpreter could not be found."
            )
            sys.exit(1)
        print(f"python3 has no codemagic package; retrying with {executable}")
        env = os.environ.copy()
        env["SAQANET_CM_PYTHON_REEXEC"] = "1"
        os.execve(executable, [executable, os.path.abspath(__file__), *sys.argv[1:]], env)


_ensure_codemagic_importable()

from codemagic.apple.app_store_connect import AppStoreConnectApiClient
from codemagic.apple.app_store_connect.api_error import AppStoreConnectApiError
from codemagic.apple.resources import BundleIdPlatform

APP_ID = "ru.saqanet.vpn"
TUNNEL_ID = "ru.saqanet.vpn.HiddifyPacketTunnel"
APP_GROUP = "group.ru.saqanet.vpn"
CAPABILITIES = ("NETWORK_EXTENSIONS", "PERSONAL_VPN", "APP_GROUPS")
APP_GROUP_SETTINGS = [
    {
        "key": "APP_GROUP_IDS",
        "options": [{"key": APP_GROUP, "enabled": True}],
    }
]


def normalize_pem(raw):
    """Codemagic often stores the .p8 with literal \\n or spaces instead of newlines."""
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives.serialization import load_pem_private_key

    text = raw.replace("\ufeff", "").strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in {'"', "'"}:
        text = text[1:-1].strip()
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = text.replace("\\r\\n", "\n").replace("\\n", "\n").strip()
    if "-----BEGIN" not in text:
        import base64

        compact = re.sub(r"\s+", "", text)
        try:
            decoded = base64.b64decode(compact, validate=False)
        except Exception:
            decoded = b""
        if decoded.startswith(b"-----BEGIN"):
            text = decoded.decode("utf-8", "replace")
        elif decoded:
            body = base64.b64encode(decoded).decode("ascii")
            chunks = "\n".join(body[i : i + 64] for i in range(0, len(body), 64))
            text = f"-----BEGIN PRIVATE KEY-----\n{chunks}\n-----END PRIVATE KEY-----\n"
    begin = re.search(r"-----BEGIN ([A-Z0-9 ]+)-----", text)
    end = re.search(r"-----END ([A-Z0-9 ]+)-----", text)
    if not begin or not end or end.start() <= begin.end():
        raise ValueError("PEM markers missing")
    kind = begin.group(1)
    body = re.sub(r"[^A-Za-z0-9+/=]", "", text[begin.end() : end.start()])
    chunks = "\n".join(body[i : i + 64] for i in range(0, len(body), 64))
    pem = f"-----BEGIN {kind}-----\n{chunks}\n-----END {kind}-----\n"
    key = load_pem_private_key(pem.encode(), password=None)
    if not isinstance(key, ec.EllipticCurvePrivateKey):
        raise ValueError("not an App Store Connect API key")
    return pem


def api_private_key():
    raw = os.environ.get("APP_STORE_CONNECT_PRIVATE_KEY", "")
    if not raw.strip():
        print("App Store Connect integration did not provide APP_STORE_CONNECT_PRIVATE_KEY.")
        sys.exit(1)
    try:
        return normalize_pem(raw)
    except Exception:
        newline_count = raw.count("\n")
        literal_newlines = raw.count("\\n")
        print(
            "The codemagic integration key is not a readable .p8 "
            f"(length {len(raw)}, newlines {newline_count}, literal \\\\n {literal_newlines})."
        )
        print("Open Team settings, Integrations, the key named codemagic,")
        print("and paste AuthKey_VR9NV2T5W6.p8 again, including the BEGIN and END lines.")
        sys.exit(1)


def client_from_env():
    names = (
        "APP_STORE_CONNECT_KEY_IDENTIFIER",
        "APP_STORE_CONNECT_ISSUER_ID",
    )
    missing = [name for name in names if not os.environ.get(name)]
    if missing:
        print("App Store Connect integration did not provide: " + ", ".join(missing))
        sys.exit(1)
    return AppStoreConnectApiClient(
        os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"],
        os.environ["APP_STORE_CONNECT_ISSUER_ID"],
        api_private_key(),
    )


def exact_bundle_id(client, identifier):
    found = client.bundle_ids.list(
        client.bundle_ids.Filter(identifier=identifier, platform=BundleIdPlatform.IOS)
    )
    matches = [item for item in found if item.attributes.identifier == identifier]
    if matches:
        return matches[0]
    name = "SAQANet" if identifier == APP_ID else "SAQANet Tunnel"
    print(f"create bundle id {identifier}")
    return client.bundle_ids.create(identifier=identifier, name=name, platform=BundleIdPlatform.IOS)


def capability_rows(client, bundle_resource_id):
    url = f"{client.API_URL}/bundleIds/{bundle_resource_id}/bundleIdCapabilities"
    return list(client.paginate(url, page_size=None))


def post_capability(client, bundle_resource_id, capability_type):
    attributes = {"capabilityType": capability_type}
    if capability_type == "APP_GROUPS":
        attributes["settings"] = APP_GROUP_SETTINGS
    payload = {
        "data": {
            "type": "bundleIdCapabilities",
            "attributes": attributes,
            "relationships": {
                "bundleId": {
                    "data": {"type": "bundleIds", "id": bundle_resource_id},
                }
            },
        }
    }
    client.session.post(f"{client.API_URL}/bundleIdCapabilities", json=payload)


def patch_app_group(client, capability_id):
    payload = {
        "data": {
            "type": "bundleIdCapabilities",
            "id": capability_id,
            "attributes": {
                "capabilityType": "APP_GROUPS",
                "settings": APP_GROUP_SETTINGS,
            },
        }
    }
    client.session.patch(
        f"{client.API_URL}/bundleIdCapabilities/{capability_id}",
        json=payload,
    )


def enable(client, bundle_id):
    resource_id = bundle_id.id
    identifier = bundle_id.attributes.identifier
    for capability_type in CAPABILITIES:
        try:
            post_capability(client, resource_id, capability_type)
            print(f"enabled {capability_type} on {identifier}")
        except AppStoreConnectApiError as err:
            rows = capability_rows(client, resource_id)
            existing = [
                row
                for row in rows
                if row.get("attributes", {}).get("capabilityType") == capability_type
            ]
            if not existing:
                print(f"failed to enable {capability_type} on {identifier}: {err}")
                raise
            if capability_type == "APP_GROUPS":
                patch_app_group(client, existing[0]["id"])
                print(f"updated APP_GROUPS on {identifier}")
            else:
                print(f"{capability_type} already enabled on {identifier}")


def delete_app_store_profiles(client, bundle_id):
    url = f"{client.API_URL}/bundleIds/{bundle_id.id}/profiles"
    for row in client.paginate(url):
        if row.get("attributes", {}).get("profileType") != "IOS_APP_STORE":
            continue
        client.profiles.delete(row["id"])
        print(f"deleted App Store profile {row['id']} for {bundle_id.attributes.identifier}")


def main():
    if "--write-api-key" in sys.argv:
        index = sys.argv.index("--write-api-key")
        destination = sys.argv[index + 1]
        pem = api_private_key()
        with open(destination, "w", encoding="utf-8") as handle:
            handle.write(pem)
        print("normalized App Store Connect API key")
        return
    client = client_from_env()
    bundle_ids = [exact_bundle_id(client, APP_ID), exact_bundle_id(client, TUNNEL_ID)]
    for bundle_id in bundle_ids:
        enable(client, bundle_id)
    for bundle_id in bundle_ids:
        delete_app_store_profiles(client, bundle_id)


if __name__ == "__main__":
    main()
