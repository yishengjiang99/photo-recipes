#!/usr/bin/env python3
"""Create / update the next App Store version record of ProTune AI Camera (no build needed).

- Creates IOS appStoreVersion VERSION_STRING (PREPARE_FOR_SUBMISSION) if it does not exist yet.
- Sets en-US "What's New" from docs/asc/metadata/en-US/whatsnew.txt (when the version is editable).
- Probes the App Privacy (nutrition label) API read-only. The public ASC API has no endpoint for
  it; the iris host has rejected API-key JWTs before. Prints PRIVACY_LABEL_MANUAL when rejected —
  then enter docs/asc/app-privacy-1.2.md by hand in App Store Connect.

NEVER attaches a build, never creates a review submission, never submits (that is
asc-submit-app-store.yml, run by the owner). Full listing sync with a build is
upload_photo_recipes_listing.py.

Env: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_API_KEY_P8,
     BUNDLE_ID (com.ragnus.mvp), VERSION_STRING (1.2), DRY_RUN (true/false)
"""
from __future__ import annotations
import json, os, time
from pathlib import Path
import jwt, requests

ROOT = Path(__file__).resolve().parents[2]
WHATS_NEW = (ROOT / "docs/asc/metadata/en-US/whatsnew.txt").read_text().strip()
BASE = "https://api.appstoreconnect.apple.com"
IRIS = "https://appstoreconnect.apple.com/iris"
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
BUNDLE_ID = os.environ.get("BUNDLE_ID", "com.ragnus.mvp").strip()
VERSION = os.environ.get("VERSION_STRING", "1.2").strip()
DRY_RUN = os.environ.get("DRY_RUN", "false").strip().lower() == "true"
LOCALE = "en-US"


def token() -> str:
    now = int(time.time())
    p8 = os.environ["APP_STORE_CONNECT_API_KEY_P8"].replace("\\n", "\n").strip()
    return jwt.encode({"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"].strip(), "iat": now,
                       "exp": now + 1100, "aud": "appstoreconnect-v1"}, p8, algorithm="ES256",
                      headers={"kid": os.environ["APP_STORE_CONNECT_KEY_ID"].strip()})


def api(method, path, body=None, base=BASE, allow=()):
    assert "reviewSubmission" not in path and "appStoreVersionSubmission" not in path, "never submits"
    if DRY_RUN and method != "GET":
        print(f"[dry-run] {method} {path} {json.dumps(body)[:300]}")
        return 0, {}
    r = requests.request(method, base + path, json=body, timeout=120,
                         headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    if r.status_code >= 300 and r.status_code not in allow:
        raise SystemExit(f"{method} {path} -> {r.status_code}: {r.text[:1500]}")
    try:
        data = r.json() if r.text else {}
    except ValueError:
        data = {"raw": r.text[:500]}
    return r.status_code, data


def main():
    assert 0 < len(WHATS_NEW) <= 4000 and "#" not in WHATS_NEW, "whatsnew.txt: 1–4000 chars, no hashtags"
    _, apps = api("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")
    app_id = apps["data"][0]["id"]
    print("APP", app_id, apps["data"][0]["attributes"].get("name"), BUNDLE_ID)

    _, all_vers = api("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=10")
    for v in all_vers.get("data", []):
        a = v["attributes"]
        print("  existing", a.get("versionString"), a.get("appStoreState"), a.get("appVersionState"))
    ver = next((v for v in all_vers.get("data", []) if v["attributes"].get("versionString") == VERSION), None)
    if ver is None:
        print(f"creating IOS version {VERSION}")
        _, created = api("POST", "/v1/appStoreVersions", {"data": {
            "type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": VERSION},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
        ver = created.get("data")
        if ver:
            print("VERSION_CREATED", ver["id"], ver["attributes"].get("appStoreState"))
    if ver:
        state = ver["attributes"].get("appVersionState") or ver["attributes"].get("appStoreState")
        print("VERSION", ver["id"], VERSION, state)
        if state in EDITABLE or ver["attributes"].get("appStoreState") in EDITABLE:
            _, locs = api("GET", f"/v1/appStoreVersions/{ver['id']}/appStoreVersionLocalizations")
            loc = next((l for l in locs.get("data", []) if l["attributes"]["locale"] == LOCALE), None)
            if loc is None:
                api("POST", "/v1/appStoreVersionLocalizations", {"data": {
                    "type": "appStoreVersionLocalizations",
                    "attributes": {"locale": LOCALE, "whatsNew": WHATS_NEW},
                    "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver["id"]}}}}})
                print("whatsNew set (new en-US localization)")
            elif (loc["attributes"].get("whatsNew") or "").strip() == WHATS_NEW:
                print("whatsNew already current")
            else:
                api("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", {"data": {
                    "type": "appStoreVersionLocalizations", "id": loc["id"],
                    "attributes": {"whatsNew": WHATS_NEW}}})
                print("whatsNew updated")
            if not DRY_RUN:
                _, check = api("GET", f"/v1/appStoreVersions/{ver['id']}/appStoreVersionLocalizations")
                got = next((l for l in check["data"] if l["attributes"]["locale"] == LOCALE), {})
                ok = (got.get("attributes", {}).get("whatsNew") or "").strip() == WHATS_NEW
                print("VERIFY whatsNew", "OK" if ok else "MISMATCH")
                if not ok:
                    raise SystemExit("whatsNew verify failed")
        else:
            print(f"WARNING: version {VERSION} not editable ({state}); whatsNew left alone")

    # App Privacy: read-only probe of the iris endpoint fastlane uses.
    st, usages = api("GET", f"/v1/apps/{app_id}/dataUsages?limit=50&include=category,purpose,dataProtection",
                     base=IRIS, allow=(400, 401, 403, 404))
    if st < 300 and isinstance(usages, dict) and "data" in usages:
        print("PRIVACY_LABEL_API_OK rows", len(usages["data"]))
        print(json.dumps(usages)[:3000])
    else:
        print("iris dataUsages", st, json.dumps(usages)[:400])
        print("PRIVACY_LABEL_MANUAL the App Privacy API rejected the API key. Enter "
              "docs/asc/app-privacy-1.2.md in App Store Connect → App Privacy, then Publish.")


if __name__ == "__main__":
    main()
