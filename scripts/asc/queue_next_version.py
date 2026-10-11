#!/usr/bin/env python3
"""One-shot, idempotent "queue the next App Store version" for ProTune AI Camera (com.ragnus.mvp).

Gate: the previous version (PREV_VERSION, e.g. 1.4) must be PENDING_DEVELOPER_RELEASE or
READY_FOR_SALE. Otherwise the script prints `RESULT waiting: <state>` and exits 0 with no change.

MODE
  check    read-only. Reports the gate, the 1.5 version, build, description checks, and what
           `submit` would do. No writes.
  prepare  create/update VERSION (build, What's New, AFTER_APPROVAL, description fix-ups) but
           never submits. Ignores the gate (only writes the new version; ASC may refuse to create
           it while PREV is in review -> `RESULT blocked: ...`, exit 0).
  submit   gated: when PREV is approved/released, prepare VERSION and submit it for review.

Hard guarantees (enforced in api()):
  * never writes to the PREV version or any other existing version but VERSION;
  * never PATCHes / cancels any reviewSubmission it did not create (or that does not hold only
    VERSION); protected submissions in PROTECTED_SUBMISSIONS are never touched;
  * never cancels or withdraws anything.

Env: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_API_KEY_P8,
     BUNDLE_ID, PREV_VERSION (1.4), VERSION_STRING (1.5), BUILD_NUMBER (81), MODE,
     PROTECTED_SUBMISSIONS (comma list), GITHUB_STEP_SUMMARY (optional)
"""
from __future__ import annotations
import json, os, sys, time
from pathlib import Path
import jwt, requests

ROOT = Path(__file__).resolve().parents[2]
BASE = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = os.environ.get("BUNDLE_ID", "com.ragnus.mvp").strip()
PREV = os.environ.get("PREV_VERSION", "1.4").strip()
VERSION = os.environ.get("VERSION_STRING", "1.5").strip()
BUILD = os.environ.get("BUILD_NUMBER", "81").strip()
MODE = os.environ.get("MODE", "check").strip().lower()
LOCALE = "en-US"
RELEASE_TYPE = "AFTER_APPROVAL"  # matches 1.0-1.4
WHATS_NEW = (ROOT / f"docs/asc/metadata/en-US/whatsnew-{VERSION}.txt").read_text().strip()
EULA = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
EULA_LINE = f"Terms of Use (EULA): {EULA}"
PROTECTED = {s.strip() for s in os.environ.get(
    "PROTECTED_SUBMISSIONS",
    "f10e284b-e297-475a-9a7e-6407145742c6,d40adbd9-cd75-4910-bedf-518ddd2601bd,"
    "183cff35-2a8c-4bce-9201-8e303e6ac5f0").split(",") if s.strip()}
GATE_OK = {"PENDING_DEVELOPER_RELEASE", "READY_FOR_SALE", "READY_FOR_DISTRIBUTION"}
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
IN_FLIGHT = {"WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE",
             "PROCESSING_FOR_APP_STORE", "READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "ACCEPTED"}

assert MODE in ("check", "prepare", "submit"), f"MODE must be check|prepare|submit, got {MODE}"
WRITE = MODE != "check"
summary: list[str] = []
guard = {"prev_version_ids": set(), "own_submissions": set(), "version_id": None}


def log(msg: str) -> None:
    print(msg, flush=True)
    summary.append(msg)


def finish(result: str, code: int = 0):
    log(f"RESULT {result}")
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a") as f:
            f.write(f"## ASC queue {VERSION} (mode={MODE})\n\n```\n" + "\n".join(summary) + "\n```\n")
    sys.exit(code)


def token() -> str:
    now = int(time.time())
    p8 = os.environ["APP_STORE_CONNECT_API_KEY_P8"].replace("\\n", "\n").strip()
    return jwt.encode({"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"].strip(), "iat": now,
                       "exp": now + 1100, "aud": "appstoreconnect-v1"}, p8, algorithm="ES256",
                      headers={"kid": os.environ["APP_STORE_CONNECT_KEY_ID"].strip()})


def api(method: str, path: str, body=None, allow=()):
    if method != "GET":
        assert WRITE, f"write {method} {path} in check mode"
        for pid in guard["prev_version_ids"]:
            assert pid not in path, f"refusing to write to {PREV} version: {path}"
        for sid in PROTECTED:
            assert sid not in path, f"refusing to touch protected submission: {path}"
        if "/reviewSubmissions/" in path:
            assert any(s in path for s in guard["own_submissions"]), f"not our submission: {path}"
        if path.startswith("/v1/appStoreVersions/"):
            assert guard["version_id"] and guard["version_id"] in path, f"not {VERSION}: {path}"
        print(f"  -> {method} {path}", flush=True)
    r = requests.request(method, BASE + path, json=body, timeout=120,
                         headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    if r.status_code >= 300 and r.status_code not in allow:
        finish(f"error: {method} {path} -> {r.status_code}: {r.text[:1500]}", 1)
    try:
        return r.status_code, (r.json() if r.text else {})
    except ValueError:
        return r.status_code, {"raw": r.text[:500]}


def get(path):
    return api("GET", path)[1]


def state_of(v):
    a = v["attributes"]
    return a.get("appStoreState") or a.get("appVersionState"), a.get("appVersionState")


def submission_version_ids(sid):
    items = get(f"/v1/reviewSubmissions/{sid}/items?include=appStoreVersion&limit=50")
    ids = set()
    for it in items.get("data", []):
        d = ((it.get("relationships") or {}).get("appStoreVersion") or {}).get("data")
        if d:
            ids.add(d["id"])
    for inc in items.get("included", []) or []:
        if inc.get("type") == "appStoreVersions":
            ids.add(inc["id"])
    return ids, len(items.get("data", []))


def fix_description(desc: str, privacy_url: str) -> tuple[str, list[str]]:
    """Return (description, problems). Adds the Privacy Policy line after the EULA line."""
    problems = []
    low = desc.lower()
    if "subscription" not in low or "/month" not in low or "/year" not in low:
        problems.append("description: subscription block (price per month/year + 'Subscriptions') missing")
    if EULA not in desc:
        problems.append("description: Apple standard EULA (Terms of Use) link missing")
    if privacy_url and privacy_url not in desc and EULA_LINE in desc:
        desc = desc.replace(EULA_LINE, f"{EULA_LINE}\nPrivacy Policy: {privacy_url}", 1)
    if not privacy_url:
        problems.append("app: privacyPolicyUrl not set")
    elif privacy_url not in desc:
        problems.append("description: Privacy Policy link missing (no EULA line to anchor it)")
    if len(desc) > 4000:
        problems.append(f"description: {len(desc)} > 4000 chars")
    return desc, problems


def main():
    log(f"mode={MODE} prev={PREV} version={VERSION} build={BUILD} releaseType={RELEASE_TYPE}")
    app = get(f"/v1/apps?filter[bundleId]={BUNDLE_ID}")["data"][0]
    app_id = app["id"]
    log(f"app {app_id} name={app['attributes'].get('name')!r}")

    vers = get(f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=20")["data"]
    for v in vers:
        a = v["attributes"]
        log(f"version {a['versionString']:<5} {state_of(v)[0]:<26} releaseType={a.get('releaseType')}")
    prev = next((v for v in vers if v["attributes"]["versionString"] == PREV), None)
    ver = next((v for v in vers if v["attributes"]["versionString"] == VERSION), None)
    guard["prev_version_ids"] = {v["id"] for v in vers if v["attributes"]["versionString"] != VERSION}
    prev_state = state_of(prev)[0] if prev else "MISSING"
    gate_open = prev_state in GATE_OK or (prev and state_of(prev)[1] in GATE_OK)
    log(f"gate: {PREV} is {prev_state} -> {'OPEN' if gate_open else 'closed'}")

    if ver:
        vstate = state_of(ver)[0]
        guard["version_id"] = ver["id"]
        log(f"{VERSION} exists: {ver['id']} {vstate}")
        if vstate not in EDITABLE:
            if vstate in IN_FLIGHT:
                finish(f"already-submitted: {VERSION} is {vstate}; nothing to do")
            finish(f"error: {VERSION} is {vstate} (not editable); fix in App Store Connect", 1)

    if MODE == "submit" and not gate_open:
        finish(f"waiting: {prev_state}")
    if MODE == "check" and not gate_open:
        log(f"(check) submit would exit now with 'waiting: {prev_state}'; continuing read-only checks")

    # Build
    builds = get(f"/v1/builds?filter[app]={app_id}&filter[version]={BUILD}"
                 f"&filter[preReleaseVersion.version]={VERSION}&limit=5")["data"]
    if not builds:
        finish(f"error: build {BUILD} ({VERSION}) not found", 1)
    build = builds[0]
    ba = build["attributes"]
    log(f"build {BUILD}: {build['id']} processing={ba.get('processingState')} "
        f"usesNonExemptEncryption={ba.get('usesNonExemptEncryption')} expired={ba.get('expired')}")
    if ba.get("processingState") != "VALID" or ba.get("expired"):
        finish(f"error: build {BUILD} not VALID/unexpired", 1)

    # Privacy URL from the app (never invented)
    privacy_url = None
    for info in get(f"/v1/apps/{app_id}/appInfos")["data"]:
        for l in get(f"/v1/appInfos/{info['id']}/appInfoLocalizations")["data"]:
            if l["attributes"]["locale"] == LOCALE and l["attributes"].get("privacyPolicyUrl"):
                privacy_url = l["attributes"]["privacyPolicyUrl"].strip()
    log(f"privacyPolicyUrl (app) = {privacy_url}")

    # Previous en-US localization = source for copied metadata
    src = {}
    if prev:
        src = next((l["attributes"] for l in get(f"/v1/appStoreVersions/{prev['id']}/appStoreVersionLocalizations")["data"]
                    if l["attributes"]["locale"] == LOCALE), {})

    if not WRITE:
        cur = {}
        if ver:
            cur = next((l["attributes"] for l in get(f"/v1/appStoreVersions/{ver['id']}/appStoreVersionLocalizations")["data"]
                        if l["attributes"]["locale"] == LOCALE), {})
        desc, problems = fix_description(cur.get("description") or src.get("description") or "", privacy_url)
        log(f"description check (source {'1.5' if cur else PREV}): "
            + ("OK" if not problems else "; ".join(problems))
            + (" [Privacy Policy line would be added]" if privacy_url and privacy_url not in (cur.get('description') or src.get('description') or '') else ""))
        log(f"(check) would: {'create ' + VERSION if not ver else 'update ' + VERSION}, attach build {BUILD}, "
            f"releaseType {RELEASE_TYPE}, whatsNew ({len(WHATS_NEW)} chars), then submit when gate OPEN")
        finish(f"{'ready' if gate_open else 'waiting: ' + prev_state} (check, no changes)")

    # ---- writes below (prepare / submit) ----
    if not ver:
        st, created = api("POST", "/v1/appStoreVersions", {"data": {
            "type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": VERSION, "releaseType": RELEASE_TYPE},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}, allow=(403, 409, 422))
        if st >= 300:
            finish(f"blocked: ASC refused to create {VERSION} while {PREV} is {prev_state}: "
                   f"{json.dumps(created)[:600]}", 0 if MODE == "prepare" else 1)
        ver = created["data"]
        guard["version_id"] = ver["id"]
        log(f"created {VERSION} {ver['id']} {state_of(ver)[0]}")
    vid = ver["id"]

    if ver["attributes"].get("releaseType") != RELEASE_TYPE:
        api("PATCH", f"/v1/appStoreVersions/{vid}", {"data": {"type": "appStoreVersions", "id": vid,
            "attributes": {"releaseType": RELEASE_TYPE}}})
        log(f"releaseType -> {RELEASE_TYPE}")

    if ba.get("usesNonExemptEncryption") is not False:
        api("PATCH", f"/v1/builds/{build['id']}", {"data": {"type": "builds", "id": build["id"],
            "attributes": {"usesNonExemptEncryption": False}}})
        log("export compliance cleared (usesNonExemptEncryption=false)")
    cur_build = (get(f"/v1/appStoreVersions/{vid}/relationships/build").get("data") or {}).get("id")
    if cur_build != build["id"]:
        api("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build", {"data": {"type": "builds", "id": build["id"]}})
        log(f"build {BUILD} attached")

    locs = get(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]
    loc = next((l for l in locs if l["attributes"]["locale"] == LOCALE), None)
    have = (loc or {}).get("attributes", {})
    fields = {k: have.get(k) or src.get(k) for k in ("description", "keywords", "promotionalText", "marketingUrl", "supportUrl")}
    desc, problems = fix_description(fields["description"] or "", privacy_url)
    fields["description"] = desc
    fields["whatsNew"] = WHATS_NEW
    fields = {k: v for k, v in fields.items() if v}
    if problems:
        log("description problems: " + "; ".join(problems))
    if loc is None:
        api("POST", "/v1/appStoreVersionLocalizations", {"data": {"type": "appStoreVersionLocalizations",
            "attributes": {"locale": LOCALE, **fields},
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
        log("en-US localization created")
    else:
        diff = {k: v for k, v in fields.items() if (have.get(k) or "").strip() != v.strip()}
        if diff:
            api("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", {"data": {
                "type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": diff}})
            log(f"en-US updated: {sorted(diff)}")
        else:
            log("en-US already current")

    # Verify
    loc = next(l for l in get(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]
               if l["attributes"]["locale"] == LOCALE)
    la = loc["attributes"]
    _, problems = fix_description(la.get("description") or "", privacy_url)
    if (la.get("whatsNew") or "").strip() != WHATS_NEW:
        problems.append("whatsNew mismatch")
    sets = get(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]
    nshots = {s["attributes"]["screenshotDisplayType"]: len(get(f"/v1/appScreenshotSets/{s['id']}/appScreenshots")["data"])
              for s in sets}
    log(f"screenshots: {nshots or 'NONE'}")
    if not any(nshots.values()):
        problems.append("no screenshots on the version (run asc-photo-recipes-upload.yml with this version/build)")
    vnow = get(f"/v1/appStoreVersions/{vid}")["data"]
    bnow = (get(f"/v1/appStoreVersions/{vid}/relationships/build").get("data") or {}).get("id")
    log(f"verify: {VERSION} {state_of(vnow)[0]} releaseType={vnow['attributes'].get('releaseType')} "
        f"build={'OK' if bnow == build['id'] else bnow} whatsNew={'OK' if 'whatsNew mismatch' not in problems else 'MISMATCH'}")
    if problems:
        finish("error: " + "; ".join(problems) + " (not submitted)", 1)

    if MODE == "prepare":
        finish(f"prepared: {VERSION} build {BUILD} ready, NOT submitted")

    # ---- submit (gate already OPEN) ----
    subs = get(f"/v1/apps/{app_id}/reviewSubmissions?filter[platform]=IOS&limit=50")["data"]
    sub_id = None
    for s in subs:
        sstate = s["attributes"].get("state")
        if sstate == "COMPLETE":
            continue
        vids, n = submission_version_ids(s["id"])
        log(f"open submission {s['id']} {sstate} items={n} holds{VERSION}={vid in vids}")
        if vid in vids:
            if sstate in ("WAITING_FOR_REVIEW", "IN_REVIEW"):
                finish(f"already-submitted: {VERSION} in submission {s['id']} ({sstate})")
            if sstate == "READY_FOR_REVIEW" and s["id"] not in PROTECTED and vids == {vid} and n == 1:
                sub_id = s["id"]  # our own earlier partial run
            else:
                finish(f"error: {VERSION} is held by submission {s['id']} ({sstate}, {n} items); "
                       "not touching it - resolve in App Store Connect", 1)
    if not sub_id:
        st, created = api("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions",
            "attributes": {"platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}, allow=(403, 409, 422))
        if st >= 300:
            finish("error: ASC refused a new reviewSubmission (likely the leftover READY_FOR_REVIEW drafts "
                   f"d40adbd9/183cff35 or f10e284b block it; not touching them): {json.dumps(created)[:800]}", 1)
        sub_id = created["data"]["id"]
        guard["own_submissions"].add(sub_id)
        log(f"created reviewSubmission {sub_id}")
        st, item = api("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems",
            "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
                              "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}},
            allow=(409, 422))
        if st >= 300:
            finish(f"error: could not add {VERSION} to submission {sub_id} (left as empty draft): "
                   f"{json.dumps(item)[:800]}", 1)
        log(f"added {VERSION} to {sub_id}")
    guard["own_submissions"].add(sub_id)
    st, resp = api("PATCH", f"/v1/reviewSubmissions/{sub_id}", {"data": {"type": "reviewSubmissions",
        "id": sub_id, "attributes": {"submitted": True}}}, allow=(409, 422))
    if st >= 300:
        finish(f"error: submit of {sub_id} refused: {json.dumps(resp)[:1200]}", 1)
    finish(f"submitted: {VERSION} build {BUILD} submission {sub_id} state={resp['data']['attributes'].get('state')}")


if __name__ == "__main__":
    main()
