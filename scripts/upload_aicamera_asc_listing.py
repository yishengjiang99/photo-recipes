#!/usr/bin/env python3
"""Upload ProTune AI Camera (com.ragnus.mvp) listing + screenshots to ASC."""
from __future__ import annotations

import hashlib
import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path

import jwt

BUNDLE_ID = "com.ragnus.mvp"
SHOT_DIR = Path(os.environ.get("SHOT_DIR", "assets/app-store/screenshots"))

NAME = "ProTune AI Camera"
SUBTITLE = "AI Auto: Shutter ISO Focus"
PROMO = (
    "AI Auto Optimize applies shutter, ISO, EV, WB & focus — real capture dials, not filters. "
    "Field looks = viewfinder grades. Free Peek available. Get on TestFlight · App Store."
)
DESCRIPTION = """AI Auto Optimize applies shutter, ISO, EV, WB & focus on your iPhone — concrete capture dials, not filters. ProTune AI Camera is an agentic field camera for high-end photography enthusiasts — serious hobbyists with real cameras who use the iPhone as a companion tool.

Set the shot. Then take it.

Auto Optimize senses the scene, picks a Photo Recipe, and **applies real capture dials** on your iPhone — not just filters.

CONTROLS WE SET (ON DEVICE)
AI Auto Optimize writes these capture dials on your iPhone:
• Shutter / exposure duration
• ISO
• EV bias
• White balance (temp / tint when available)
• Focus lock / POI
• Zoom / lens when the device allows
• Torch / flash when relevant
• Field looks / creative look intensity

Also when the device allows: custom exposure, video HDR, fps / format, brackets / HDR, photo quality.

COACH-ONLY (brief)
Aperture, ND filters, and tripod/support stay guidance — we don’t fake aperture writes on device.

FIELD LOOKS — CAPTURE GRADES
Optional field looks live on the viewfinder and at capture — crispCool, warmGlow, warmPop, editorialRed, softVintage, monoInk, goldenHour, loFiPunch, tealOrange, blockbuster, moodyFilm, coolBlue, softDream, filmGrain. Auto Optimize can suggest a look; intensity 0–1. These are capture grades for the field — not beauty filters.

PHOTOGRAPHY SKILL LIBRARY
Classic field techniques — panning, motion control, HDR, focus discipline, low angle, and more — as recipes with dials, steps, and checklists. Browse free anytime.

TEACH MODE
Ask “Why this?” after a run. See the recipe choice, which dials moved (shutter, ISO, EV, WB, focus), and what to watch for — instructor-at-your-shoulder, not a chat wall.

FREE PEEK vs PRO
• Free Peek: browse recipes, live viewfinder, limited Auto Optimize per day
• AI Camera Pro: unlimited Auto Optimize, manual dials, apply recipes to the live session, full Teach mode, interactive field checklists

Pricing: $7.99/month or $59.99/year (best value), both with a 7-day free trial. Subscriptions via Apple In-App Purchase.

CTA: Get on TestFlight · Download — App Store.

Optional: dictate a short scene note if you prefer (voice is secondary to From-viewfinder Auto Optimize).

Tone: precise, craft-forward, field technique — never beauty filters, sky replacement, or AI-magic edits.

Privacy: Camera and photo library access are used for capture, Auto Optimize, and optional scene photos. See the privacy policy in the app."""
KEYWORDS = "photography,camera settings,shutter,ISO,exposure,focus,HDR,panning,landscape,optimize"
WHATS_NEW = (
    "Renamed to ProTune AI Camera. AI Auto Optimize applies shutter, ISO, EV, WB, focus, "
    "zoom/lens, torch when needed, plus field look intensity — real capture dials, not filters. "
    "Set the shot. Then take it."
)
SUPPORT_URL = "https://photo.grepawk.com/support"
MARKETING_URL = "https://photo.grepawk.com"
PRIVACY_URL = "https://photo.grepawk.com/privacy"
REVIEW_NOTES = (
    "Resolution: Renamed the app to ProTune AI Camera and removed the prior trademarked "
    "name from the display name, onboarding, paywall, Settings, permission strings, "
    "Support/Privacy/Terms, and App Store listing/screenshots. Pro marketing name is now AI Camera Pro. "
    "Demo account N/A (guest session). Free Peek allows limited Auto Optimize/day without purchase. "
    "IAP yearly/monthly with 7-day trials. No Stripe inside iOS app."
)

# Primary ASC set (Build 16 frames)
SHOTS = [
    ("iphone-67-01-ao-dial-burst.png", "APP_IPHONE_67"),
    ("iphone-67-02-recommend.png", "APP_IPHONE_67"),
    ("iphone-67-03-stt-scene.png", "APP_IPHONE_67"),
    ("iphone-67-04-manual-teach.png", "APP_IPHONE_67"),
    ("iphone-67-05-hero-value.png", "APP_IPHONE_67"),
    ("iphone-61-01-ao-dial-burst.png", "APP_IPHONE_61"),
    ("iphone-61-02-recommend.png", "APP_IPHONE_61"),
    ("iphone-61-03-stt-scene.png", "APP_IPHONE_61"),
    ("iphone-61-04-manual-teach.png", "APP_IPHONE_61"),
    ("iphone-61-05-hero-value.png", "APP_IPHONE_61"),
]


def token() -> str:
    key_id = os.environ["APP_STORE_CONNECT_KEY_ID"].strip()
    issuer = os.environ["APP_STORE_CONNECT_ISSUER_ID"].strip()
    p8 = os.environ["APP_STORE_CONNECT_API_KEY_P8"].replace("\\n", "\n").strip()
    print(f"ASC auth key_id={key_id} issuer_len={len(issuer)}")
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        p8,
        algorithm="ES256",
        headers={"kid": key_id},
    )


TOK = None


def api(method: str, path: str, body=None):
    global TOK
    if TOK is None:
        TOK = token()
    data = None if body is None else json.dumps(body).encode()
    headers = {"Authorization": f"Bearer {TOK}"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path,
        data=data,
        method=method,
        headers=headers,
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            raw = r.read().decode() or "{}"
            return r.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        err = e.read().decode()
        raise SystemExit(f"{method} {path} -> {e.code}: {err[:3000]}")


def put_bytes(url: str, method: str, headers: dict, chunk: bytes):
    req = urllib.request.Request(url, data=chunk, method=method, headers=headers)
    with urllib.request.urlopen(req, timeout=180) as r:
        r.read()


def upload_screenshot(loc_id: str, display_type: str, path: Path):
    raw = path.read_bytes()
    checksum = hashlib.md5(raw).hexdigest()
    st, sets = api(
        "GET",
        f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets",
    )
    shot_set = next(
        (s for s in sets.get("data", []) if s["attributes"].get("screenshotDisplayType") == display_type),
        None,
    )
    if shot_set is None:
        st, created = api(
            "POST",
            "/v1/appScreenshotSets",
            {
                "data": {
                    "type": "appScreenshotSets",
                    "attributes": {"screenshotDisplayType": display_type},
                    "relationships": {
                        "appStoreVersionLocalization": {
                            "data": {"type": "appStoreVersionLocalizations", "id": loc_id}
                        }
                    },
                }
            },
        )
        shot_set = created["data"]
    set_id = shot_set["id"]

    # Reserve screenshot
    st, reserved = api(
        "POST",
        "/v1/appScreenshots",
        {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileName": path.name, "fileSize": len(raw)},
                "relationships": {
                    "appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}
                },
            }
        },
    )
    shot = reserved["data"]
    shot_id = shot["id"]
    ops = shot["attributes"]["uploadOperations"]
    for op in ops:
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        chunk = raw[op["offset"] : op["offset"] + op["length"]]
        put_bytes(op["url"], op["method"], headers, chunk)
    api(
        "PATCH",
        f"/v1/appScreenshots/{shot_id}",
        {
            "data": {
                "type": "appScreenshots",
                "id": shot_id,
                "attributes": {"uploaded": True, "sourceFileChecksum": checksum},
            }
        },
    )
    print("uploaded", path.name, "->", display_type, shot_id)


def main():
    st, apps = api("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")
    if not apps.get("data"):
        raise SystemExit(f"App not found for {BUNDLE_ID}")
    app = apps["data"][0]
    app_id = app["id"]
    print("APP", app_id, app["attributes"].get("name"), app["attributes"].get("bundleId"))

    # App name / subtitle via appInfoLocalizations
    st, infos = api("GET", f"/v1/apps/{app_id}/appInfos")
    if infos.get("data"):
        info_id = infos["data"][0]["id"]
        st, info_locs = api("GET", f"/v1/appInfos/{info_id}/appInfoLocalizations")
        info_loc = next(
            (L for L in info_locs.get("data", []) if L["attributes"].get("locale") == "en-US"),
            None,
        )
        attrs = {
            "name": NAME[:30],
            "subtitle": SUBTITLE[:30],
            "privacyPolicyUrl": PRIVACY_URL,
        }
        if info_loc is None:
            st, created = api(
                "POST",
                "/v1/appInfoLocalizations",
                {
                    "data": {
                        "type": "appInfoLocalizations",
                        "attributes": {"locale": "en-US", **attrs},
                        "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info_id}}},
                    }
                },
            )
            print("created appInfoLocalization", created["data"]["id"], attrs)
        else:
            loc_id = info_loc["id"]
            api(
                "PATCH",
                f"/v1/appInfoLocalizations/{loc_id}",
                {
                    "data": {
                        "type": "appInfoLocalizations",
                        "id": loc_id,
                        "attributes": attrs,
                    }
                },
            )
            print("patched appInfoLocalization", loc_id, attrs)

    # Version localization
    st, vers = api("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=20")
    version = None
    for v in vers.get("data", []):
        a = v["attributes"]
        print("VERSION", v["id"], a.get("versionString"), a.get("appStoreState"), a.get("appVersionState"))
        if version is None:
            version = v  # prefer first (newest)
        if a.get("versionString") == "1.0" and a.get("appStoreState") in {
            "PREPARE_FOR_SUBMISSION",
            "REJECTED",
            "METADATA_REJECTED",
            "DEVELOPER_REJECTED",
            "WAITING_FOR_REVIEW",
            "INVALID_BINARY",
        }:
            version = v
            break
    if version is None:
        raise SystemExit("No editable iOS appStoreVersion found")
    version_id = version["id"]
    print("using version", version_id, version["attributes"].get("versionString"), version["attributes"].get("appStoreState"))

    st, locs = api("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations")
    loc = next((L for L in locs.get("data", []) if L["attributes"].get("locale") == "en-US"), None)
    if loc is None:
        st, created = api(
            "POST",
            "/v1/appStoreVersionLocalizations",
            {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "attributes": {"locale": "en-US"},
                    "relationships": {
                        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}
                    },
                }
            },
        )
        loc = created["data"]
    loc_id = loc["id"]
    loc_attrs = {
        "description": DESCRIPTION,
        "keywords": KEYWORDS[:100],
        "marketingUrl": MARKETING_URL,
        "promotionalText": PROMO[:170],
        "supportUrl": SUPPORT_URL,
        "whatsNew": WHATS_NEW[:4000],
    }
    try:
        api(
            "PATCH",
            f"/v1/appStoreVersionLocalizations/{loc_id}",
            {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "id": loc_id,
                    "attributes": loc_attrs,
                }
            },
        )
        print("localization patched", loc_id)
    except SystemExit as e:
        if "whatsNew" in str(e) or "What" in str(e):
            loc_attrs.pop("whatsNew", None)
            api(
                "PATCH",
                f"/v1/appStoreVersionLocalizations/{loc_id}",
                {
                    "data": {
                        "type": "appStoreVersionLocalizations",
                        "id": loc_id,
                        "attributes": loc_attrs,
                    }
                },
            )
            print("localization patched without whatsNew", loc_id)
        else:
            raise

    # Review details
    st, revs = api("GET", f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail")
    if revs.get("data"):
        rid = revs["data"]["id"]
        api(
            "PATCH",
            f"/v1/appStoreReviewDetails/{rid}",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "id": rid,
                    "attributes": {"notes": REVIEW_NOTES},
                }
            },
        )
        print("review notes patched", rid)
    else:
        api(
            "POST",
            "/v1/appStoreReviewDetails",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "attributes": {"notes": REVIEW_NOTES},
                    "relationships": {
                        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}
                    },
                }
            },
        )
        print("review notes created")

    upload_shots = os.environ.get("UPLOAD_SCREENSHOTS", "1") == "1"
    if upload_shots:
        # Clear existing screenshots in target sets then upload
        st, sets = api("GET", f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")
        for s in sets.get("data", []):
            dtype = s["attributes"].get("screenshotDisplayType")
            if dtype not in {"APP_IPHONE_67", "APP_IPHONE_61"}:
                continue
            st, existing = api("GET", f"/v1/appScreenshotSets/{s['id']}/appScreenshots")
            for shot in existing.get("data", []):
                api("DELETE", f"/v1/appScreenshots/{shot['id']}")
                print("deleted old screenshot", shot["id"], dtype)
        for fname, dtype in SHOTS:
            path = SHOT_DIR / fname
            if not path.exists():
                print("MISSING shot", path)
                continue
            upload_screenshot(loc_id, dtype, path)

    print("DONE listing update for", NAME)


if __name__ == "__main__":
    main()
