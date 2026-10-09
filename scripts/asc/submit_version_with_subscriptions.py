#!/usr/bin/env python3
"""Submit ProTune AI Camera version VERSION_STRING (build BUILD_NUMBER) for App Review in ONE
reviewSubmission together with the first subscriptions (Apple: the first auto-renewable subscription and
its group must ride with an app version; otherwise 409 FIRST_SUBSCRIPTION_MUST_BE_SUBMITTED_ON_VERSION).

Items: appStoreVersion + subscriptionGroupVersion (group GROUP_ID) + one subscriptionVersion per product.
Reuses an EMPTY READY_FOR_REVIEW iOS reviewSubmission when one exists (else creates one). If any item
cannot be added, nothing is submitted. MODE=status is read-only.
Env: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_API_KEY_P8,
     BUNDLE_ID, VERSION_STRING, BUILD_NUMBER, MODE (submit|status|wait_build)
"""
from __future__ import annotations
import json, os, sys, time
import jwt, requests

BASE = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = os.environ.get("BUNDLE_ID", "com.ragnus.mvp").strip()
VERSION_STRING = os.environ["VERSION_STRING"].strip()
BUILD_NUMBER = os.environ["BUILD_NUMBER"].strip()
MODE = os.environ.get("MODE", "status").strip()
GROUP_ID = "22398490"
PRODUCT_IDS = ["com.ragnus.mvp.pro.yearly", "com.ragnus.mvp.pro.monthly"]
SUB_DONE = {"WAITING_FOR_REVIEW", "IN_REVIEW", "APPROVED"}
DRAFT_STATES = ("PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "DEVELOPER_REJECTED", "REJECTED")


def token():
    now = int(time.time())
    p8 = os.environ["APP_STORE_CONNECT_API_KEY_P8"].replace("\\n", "\n").strip()
    return jwt.encode({"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"].strip(), "iat": now, "exp": now + 1100,
                       "aud": "appstoreconnect-v1"}, p8, algorithm="ES256",
                      headers={"kid": os.environ["APP_STORE_CONNECT_KEY_ID"].strip()})


def api(method, path, body=None):
    if MODE != "submit" and method != "GET":
        raise SystemExit(f"read-only mode but tried {method} {path}")
    r = requests.request(method, path if path.startswith("http") else BASE + path, json=body,
                         headers={"Authorization": "Bearer " + token()}, timeout=90)
    return r.status_code, (r.json() if r.text else {})


def must(method, path, body=None):
    code, j = api(method, path, body)
    if code >= 300:
        raise SystemExit(f"{method} {path} -> {code}: {json.dumps(j)[:2000]}")
    return j


def find_build(app_id):
    bs = must("GET", f"/v1/builds?filter[app]={app_id}&filter[version]={BUILD_NUMBER}&limit=10")["data"]
    return next((b for b in bs if not b["attributes"].get("expired")), None)


def status(app_id):
    print("\n===== STATUS =====")
    vers = must("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=5")["data"]
    for v in vers:
        a = v["attributes"]
        b = (must("GET", f"/v1/appStoreVersions/{v['id']}/build").get("data") or {})
        print("VERSION", v["id"], a.get("versionString"), a.get("appStoreState"), a.get("appVersionState"),
              "build=", (b.get("attributes") or {}).get("version"), b.get("id"))
    g = must("GET", f"/v1/subscriptionGroups/{GROUP_ID}")["data"]
    gv = must("GET", f"/v1/subscriptionGroups/{GROUP_ID}/versions?limit=10")["data"]
    print("GROUP", GROUP_ID, g["attributes"].get("referenceName"), [(x["id"], x["attributes"]) for x in gv])
    for s in must("GET", f"/v1/subscriptionGroups/{GROUP_ID}/subscriptions?limit=50")["data"]:
        sv = must("GET", f"/v1/subscriptions/{s['id']}/versions?limit=10")["data"]
        print("SUB", s["id"], s["attributes"]["productId"], s["attributes"].get("state"),
              [(x["id"], x["attributes"]) for x in sv])
    for rs in must("GET", f"/v1/apps/{app_id}/reviewSubmissions?filter[platform]=IOS&limit=20")["data"]:
        a = rs["attributes"]
        if a.get("state") == "COMPLETE":
            continue
        items = must("GET", f"/v1/reviewSubmissions/{rs['id']}/items?limit=50")["data"]
        print("REVIEW SUBMISSION", rs["id"], a.get("state"), "submitted=", a.get("submittedDate"),
              [(it["attributes"].get("state"), [k for k, v in (it.get("relationships") or {}).items()
                                               if isinstance(v, dict) and v.get("data")]) for it in items])


def latest_version(versions):
    for v in sorted(versions, key=lambda v: -(v["attributes"].get("version") or 0)):
        return v
    return None


def add_item(rs_id, rel_name, rel_type, rel_id):
    code, j = api("POST", "/v1/reviewSubmissionItems", {"data": {
        "type": "reviewSubmissionItems",
        "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": rs_id}},
                          rel_name: {"data": {"type": rel_type, "id": rel_id}}}}})
    blob = json.dumps(j)
    ok = code < 300 or "ALREADY" in blob.upper() or "DUPLICATE" in blob.upper()
    print(f"ADD ITEM {rel_name} {rel_id} -> {code}", (j.get("data") or {}).get("id") if code < 300 else blob[:2000])
    return ok


def main():
    app_id = must("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")["data"][0]["id"]
    print("APP", app_id, BUNDLE_ID, "version", VERSION_STRING, "build", BUILD_NUMBER, "mode", MODE)

    if MODE == "wait_build":
        for i in range(60):
            b = find_build(app_id)
            st = b and b["attributes"].get("processingState")
            print(f"build {BUILD_NUMBER} poll {i + 1}: {st}", b and b["attributes"].get("usesNonExemptEncryption"))
            if st == "VALID":
                return
            if st in ("FAILED", "INVALID"):
                raise SystemExit(f"build {BUILD_NUMBER} is {st}")
            time.sleep(30)
        raise SystemExit(f"build {BUILD_NUMBER} not VALID after 30 min")

    if MODE == "status":
        status(app_id)
        return

    # ---- submit ----
    build = find_build(app_id)
    if not build or build["attributes"].get("processingState") != "VALID":
        raise SystemExit(f"build {BUILD_NUMBER} not VALID: {build and build['attributes']}")
    if build["attributes"].get("usesNonExemptEncryption") is not False:
        raise SystemExit("export compliance not cleared on build (listing sync should have done this)")
    ver = must("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&filter[versionString]={VERSION_STRING}")["data"][0]
    vb = (must("GET", f"/v1/appStoreVersions/{ver['id']}/build").get("data") or {})
    print("VERSION", ver["id"], ver["attributes"].get("appStoreState"), "attached build", vb.get("id"),
          (vb.get("attributes") or {}).get("version"))
    if vb.get("id") != build["id"]:
        raise SystemExit(f"version {VERSION_STRING} does not have build {BUILD_NUMBER} attached")
    if ver["attributes"].get("appStoreState") not in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
                                                       "METADATA_REJECTED", "READY_FOR_REVIEW"):
        raise SystemExit(f"version state {ver['attributes'].get('appStoreState')} not submittable")

    subs = {s["attributes"]["productId"]: s for s in must("GET", f"/v1/subscriptionGroups/{GROUP_ID}/subscriptions?limit=50")["data"]}
    sub_versions = []
    for pid in PRODUCT_IDS:
        s = subs.get(pid) or sys.exit(f"MISSING {pid}")
        state = s["attributes"].get("state")
        print("SUB", pid, s["id"], state)
        if state in SUB_DONE:
            continue
        if state != "READY_TO_SUBMIT":
            raise SystemExit(f"NOT READY {pid}: {state}")
        sv = latest_version(must("GET", f"/v1/subscriptions/{s['id']}/versions?limit=50")["data"])
        print("  subscriptionVersion", sv and (sv["id"], sv["attributes"]))
        if not sv or sv["attributes"].get("state") not in DRAFT_STATES:
            raise SystemExit(f"no submittable subscriptionVersion for {pid}")
        sub_versions.append((pid, sv))
    gv = latest_version(must("GET", f"/v1/subscriptionGroups/{GROUP_ID}/versions?limit=50")["data"])
    print("GROUP VERSION", gv and (gv["id"], gv["attributes"]))

    rss = must("GET", f"/v1/apps/{app_id}/reviewSubmissions?filter[platform]=IOS&limit=50")["data"]
    draft = None
    for r in rss:
        if r["attributes"].get("state") == "READY_FOR_REVIEW":
            n = len(must("GET", f"/v1/reviewSubmissions/{r['id']}/items?limit=50")["data"])
            print("READY_FOR_REVIEW submission", r["id"], "items=", n)
            if draft is None and n == 0:
                draft = r
    if draft:
        print("REUSE empty reviewSubmission", draft["id"])
    else:
        draft = must("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                     "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
        print("CREATED reviewSubmission", draft["id"])
    rs_id = draft["id"]

    ok = add_item(rs_id, "appStoreVersion", "appStoreVersions", ver["id"])
    if gv and gv["attributes"].get("state") in DRAFT_STATES:
        ok = add_item(rs_id, "subscriptionGroupVersion", "subscriptionGroupVersions", gv["id"]) and ok
    for pid, sv in sub_versions:
        ok = add_item(rs_id, "subscriptionVersion", "subscriptionVersions", sv["id"]) and ok
    items = must("GET", f"/v1/reviewSubmissions/{rs_id}/items?limit=50")["data"]
    for it in items:
        print("ITEM", it["id"], it["attributes"].get("state"),
              {k: (v.get("data") or {}).get("id") for k, v in (it.get("relationships") or {}).items() if isinstance(v, dict) and v.get("data")})
    if not ok:
        raise SystemExit(f"could not add every item to reviewSubmission {rs_id}; NOT submitted")

    j = must("PATCH", f"/v1/reviewSubmissions/{rs_id}", {"data": {"type": "reviewSubmissions", "id": rs_id,
                                                                    "attributes": {"submitted": True}}})
    a = j["data"]["attributes"]
    print("SUBMIT_OK submission_id=", rs_id, "state=", a.get("state"), "submittedDate=", a.get("submittedDate"))
    time.sleep(10)
    status(app_id)


if __name__ == "__main__":
    main()
