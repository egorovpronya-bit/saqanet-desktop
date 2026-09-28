#!/usr/bin/env python3
"""Enable the VPN capabilities on both bundle IDs before profiles are created.

App Store profiles only allow the entitlements that were on the App ID at the
moment the profile was created. Network Extensions and Personal VPN have no
extra settings. App Groups must name group.ru.saqanet.vpn.
"""

import os
import sys

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


def client_from_env():
    names = (
        "APP_STORE_CONNECT_KEY_IDENTIFIER",
        "APP_STORE_CONNECT_ISSUER_ID",
        "APP_STORE_CONNECT_PRIVATE_KEY",
    )
    missing = [name for name in names if not os.environ.get(name)]
    if missing:
        print("App Store Connect integration did not provide: " + ", ".join(missing))
        sys.exit(1)
    return AppStoreConnectApiClient(
        os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"],
        os.environ["APP_STORE_CONNECT_ISSUER_ID"],
        os.environ["APP_STORE_CONNECT_PRIVATE_KEY"],
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
    client = client_from_env()
    bundle_ids = [exact_bundle_id(client, APP_ID), exact_bundle_id(client, TUNNEL_ID)]
    for bundle_id in bundle_ids:
        enable(client, bundle_id)
    for bundle_id in bundle_ids:
        delete_app_store_profiles(client, bundle_id)


if __name__ == "__main__":
    main()
