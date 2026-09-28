#!/usr/bin/env python3
"""Attach the fetched App Store profiles to the Xcode project.

Codemagic downloads the profiles, but flutter build ipa still archives with
automatic development signing unless each target names its profile. This
replaces the placeholders in project.pbxproj and writes export_options.plist.
"""

import glob
import os
import plistlib
import subprocess
import sys
from datetime import datetime

BUNDLE_APP = "ru.saqanet.vpn"
BUNDLE_TUNNEL = "ru.saqanet.vpn.HiddifyPacketTunnel"
TEAM_ID = "RQLYK274UC"
PBXPROJ = "ios/Runner.xcodeproj/project.pbxproj"


def profile_paths():
    patterns = [
        "~/Library/MobileDevice/Provisioning Profiles/*.mobileprovision",
        "~/Library/MobileDevice/Provisioning Profiles/*.provisionprofile",
        "~/Library/Developer/Xcode/UserData/Provisioning Profiles/*.mobileprovision",
        "~/Library/Developer/Xcode/UserData/Provisioning Profiles/*.provisionprofile",
    ]
    paths = []
    for pattern in patterns:
        paths.extend(glob.glob(os.path.expanduser(pattern)))
    return paths


def bundle_id(profile):
    entitlements = profile.get("Entitlements") or {}
    team = entitlements.get("com.apple.developer.team-identifier") or ""
    app_id = entitlements.get("application-identifier") or ""
    prefix = team + "."
    if team and app_id.startswith(prefix):
        return app_id[len(prefix) :]
    return ""


def is_app_store(profile):
    if profile.get("ProvisionedDevices"):
        return False
    if profile.get("ProvisionsAllDevices"):
        return False
    return True


def newest_profiles():
    found = {}
    for path in profile_paths():
        xml = subprocess.check_output(["security", "cms", "-D", "-i", path])
        profile = plistlib.loads(xml)
        bundle = bundle_id(profile)
        if not bundle or not is_app_store(profile):
            continue
        created = profile.get("CreationDate") or datetime.min
        current = found.get(bundle)
        if current is None or created > current[0]:
            found[bundle] = (created, profile.get("Name") or "")
    return found


def quoted(name):
    return '"' + name.replace("\\", "").replace('"', "") + '"'


def main():
    found = newest_profiles()
    missing = [bundle for bundle in (BUNDLE_APP, BUNDLE_TUNNEL) if not found.get(bundle, ("", ""))[1]]
    if missing:
        print("App Store profiles not found for: " + ", ".join(missing), file=sys.stderr)
        print("Profiles on disk: " + ", ".join(sorted(found)) or "(none)", file=sys.stderr)
        return 1

    app_name = found[BUNDLE_APP][1]
    tunnel_name = found[BUNDLE_TUNNEL][1]
    print("App profile: " + app_name)
    print("Tunnel profile: " + tunnel_name)

    with open(PBXPROJ, encoding="utf-8") as handle:
        project = handle.read()
    if "APP_STORE_PROFILE_APP" not in project or "APP_STORE_PROFILE_TUNNEL" not in project:
        print("Signing placeholders are missing from the Xcode project", file=sys.stderr)
        return 1
    project = project.replace("APP_STORE_PROFILE_APP", quoted(app_name))
    project = project.replace("APP_STORE_PROFILE_TUNNEL", quoted(tunnel_name))
    with open(PBXPROJ, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(project)

    export_path = os.path.join(os.environ.get("HOME", "/Users/builder"), "export_options.plist")
    export_options = {
        "compileBitcode": False,
        "method": "app-store-connect",
        "provisioningProfiles": {
            BUNDLE_APP: app_name,
            BUNDLE_TUNNEL: tunnel_name,
        },
        "signingCertificate": "Apple Distribution",
        "signingStyle": "manual",
        "teamID": TEAM_ID,
        "uploadSymbols": True,
    }
    with open(export_path, "wb") as handle:
        plistlib.dump(export_options, handle)
    print("Wrote " + export_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
