#!/usr/bin/env python3
"""READ-ONLY in-app purchase audit across apps via the App Store Connect API.

Only issues GET requests (enforced). Never creates, modifies or submits anything.
For each app id in APP_IDS (comma separated) prints:
  app availability, recent App Store versions (+ build),
  subscription groups (+ localizations) and subscriptions: state, group level, period,
  USA price, #territories priced, availability territory count (+ availableInNewTerritories),
  intro offers (#territories, by mode/duration), localizations, review screenshot,
  non-subscription inAppPurchasesV2: type, state, base price, #territories priced,
  availability, localizations, review screenshot.
Writes the full result to iap_audit.json as well.
Env: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_API_KEY_P8, APP_IDS
"""
from __future__ import annotations
import collections, json, os, sys, time
import jwt, requests

BASE = "https://api.appstoreconnect.apple.com"
APP_IDS = [a.strip() for a in os.environ.get("APP_IDS", "").split(",") if a.strip()]
_tok = {"v": None, "t": 0}


def token() -> str:
    now = int(time.time())
    if _tok["v"] and now - _tok["t"] < 600:
        return _tok["v"]
    p8 = os.environ["APP_STORE_CONNECT_API_KEY_P8"].replace("\\n", "\n").strip()
    _tok["v"] = jwt.encode({"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"].strip(), "iat": now,
                            "exp": now + 1100, "aud": "appstoreconnect-v1"}, p8, algorithm="ES256",
                           headers={"kid": os.environ["APP_STORE_CONNECT_KEY_ID"].strip()})
    _tok["t"] = now
    return _tok["v"]


def get(path, ok404=True):
    url = path if path.startswith("http") else BASE + path
    for attempt in range(5):
        r = requests.get(url, headers={"Authorization": "Bearer " + token()}, timeout=120)
        if r.status_code in (429, 500, 502, 503, 504) and attempt < 4:
            time.sleep(3 * (attempt + 1))
            continue
        break
    if r.status_code == 404 and ok404:
        return None
    if r.status_code >= 300:
        return {"_error": f"{r.status_code}: {r.text[:600]}"}
    return r.json() if r.text else {}


def get_all(path):
    data, inc, url, err = [], [], path, None
    while url:
        j = get(url)
        if j is None:
            break
        if "_error" in j:
            err = j["_error"]
            break
        d = j.get("data")
        if isinstance(d, list):
            data += d
        elif d:
            data.append(d)
        inc += j.get("included", []) or []
        url = (j.get("links") or {}).get("next")
    return data, inc, err


def rel_id(obj, name):
    d = ((obj.get("relationships") or {}).get(name) or {}).get("data")
    return d.get("id") if isinstance(d, dict) else None


def screenshot(path):
    j = get(path)
    if not j or "_error" in j or not j.get("data"):
        return None if not (j and "_error" in j) else j["_error"]
    a = j["data"]["attributes"]
    return {"fileName": a.get("fileName"), "state": (a.get("assetDeliveryState") or {}).get("state")}


def audit_sub(sub):
    sid, a = sub["id"], sub["attributes"]
    out = {"id": sid, "productId": a.get("productId"), "name": a.get("name"), "state": a.get("state"),
           "groupLevel": a.get("groupLevel"), "period": a.get("subscriptionPeriod"),
           "familySharable": a.get("familySharable"), "reviewNote": bool(a.get("reviewNote"))}
    # prices
    prices, inc, err = get_all(f"/v1/subscriptions/{sid}/prices?include=subscriptionPricePoint,territory&limit=200")
    pp = {i["id"]: i["attributes"] for i in inc if i["type"] == "subscriptionPricePoints"}
    terr_prices = collections.defaultdict(list)
    for p in prices:
        t = rel_id(p, "territory")
        terr_prices[t].append({"start": p["attributes"].get("startDate"),
                               "price": (pp.get(rel_id(p, "subscriptionPricePoint")) or {}).get("customerPrice")})
    out["pricesError"] = err
    out["territoriesPriced"] = len(terr_prices)
    out["usaPrice"] = terr_prices.get("USA")
    # availability
    j = get(f"/v1/subscriptions/{sid}/subscriptionAvailability")
    if j and j.get("data") and "_error" not in j:
        av = j["data"]
        terrs, _, terr_err = get_all(f"/v1/subscriptionAvailabilities/{av['id']}/availableTerritories?limit=200")
        out["availability"] = {"availableInNewTerritories": av["attributes"].get("availableInNewTerritories"),
                               "territories": len(terrs), "error": terr_err,
                               "hasUSA": any(t["id"] == "USA" for t in terrs)}
    else:
        out["availability"] = {"territories": 0, "error": (j or {}).get("_error") if j else "not set"}
    # intro offers
    offers, _, oerr = get_all(f"/v1/subscriptions/{sid}/introductoryOffers?include=territory&limit=200")
    modes = collections.Counter()
    terr_off = set()
    for o in offers:
        oa = o["attributes"]
        modes[f"{oa.get('offerMode')}/{oa.get('duration')}x{oa.get('numberOfPeriods')}"] += 1
        terr_off.add(rel_id(o, "territory"))
    out["introOffers"] = {"territories": len(terr_off), "modes": dict(modes), "error": oerr,
                          "hasUSA": "USA" in terr_off}
    # promotional offers (count only)
    promos, _, _ = get_all(f"/v1/subscriptions/{sid}/promotionalOffers?limit=50")
    out["promotionalOffers"] = len(promos)
    locs, _, lerr = get_all(f"/v1/subscriptions/{sid}/subscriptionLocalizations?limit=50")
    out["localizations"] = [{"locale": l["attributes"].get("locale"), "name": l["attributes"].get("name"),
                             "state": l["attributes"].get("state"),
                             "desc": l["attributes"].get("description")} for l in locs]
    out["reviewScreenshot"] = screenshot(f"/v1/subscriptions/{sid}/appStoreReviewScreenshot")
    return out


def audit_iap(iap):
    iid, a = iap["id"], iap["attributes"]
    out = {"id": iid, "productId": a.get("productId"), "name": a.get("name"), "type": a.get("inAppPurchaseType"),
           "state": a.get("state"), "familySharable": a.get("familySharable"), "reviewNote": bool(a.get("reviewNote"))}
    j = get(f"/v2/inAppPurchases/{iid}/iapPriceSchedule?include=baseTerritory")
    if j and j.get("data") and "_error" not in j:
        sched = j["data"]["id"]
        out["baseTerritory"] = rel_id(j["data"], "baseTerritory")
        man, inc, merr = get_all(f"/v1/inAppPurchasePriceSchedules/{sched}/manualPrices?include=inAppPurchasePricePoint,territory&limit=200")
        pp = {i["id"]: i["attributes"] for i in inc if i["type"] == "inAppPurchasePricePoints"}
        out["manualPrices"] = [{"territory": rel_id(m, "territory"), "start": m["attributes"].get("startDate"),
                                "price": (pp.get(rel_id(m, "inAppPurchasePricePoint")) or {}).get("customerPrice")}
                               for m in man]
        auto, _, _ = get_all(f"/v1/inAppPurchasePriceSchedules/{sched}/automaticPrices?include=territory&limit=200")
        out["territoriesPriced"] = len({rel_id(x, "territory") for x in man + auto})
        out["pricesError"] = merr
    else:
        out["priceSchedule"] = (j or {}).get("_error") if j else "not set"
        out["territoriesPriced"] = 0
    j = get(f"/v2/inAppPurchases/{iid}/inAppPurchaseAvailability")
    if j and j.get("data") and "_error" not in j:
        av = j["data"]
        terrs, _, terr_err = get_all(f"/v1/inAppPurchaseAvailabilities/{av['id']}/availableTerritories?limit=200")
        out["availability"] = {"availableInNewTerritories": av["attributes"].get("availableInNewTerritories"),
                               "territories": len(terrs), "error": terr_err}
    else:
        out["availability"] = {"territories": 0, "error": (j or {}).get("_error") if j else "not set"}
    locs, _, _ = get_all(f"/v2/inAppPurchases/{iid}/inAppPurchaseLocalizations?limit=50")
    out["localizations"] = [{"locale": l["attributes"].get("locale"), "name": l["attributes"].get("name"),
                             "state": l["attributes"].get("state"),
                             "desc": l["attributes"].get("description")} for l in locs]
    out["reviewScreenshot"] = screenshot(f"/v2/inAppPurchases/{iid}/appStoreReviewScreenshot")
    return out


def audit_app(app_id):
    res = {"appId": app_id}
    j = get(f"/v1/apps/{app_id}")
    if not j or "_error" in j:
        res["error"] = (j or {}).get("_error", "not found")
        return res
    a = j["data"]["attributes"]
    res.update(name=a.get("name"), bundleId=a.get("bundleId"))
    av = get(f"/v1/apps/{app_id}/appAvailabilityV2")
    if av and av.get("data") and "_error" not in av:
        ta, _, _ = get_all(f"/v2/appAvailabilities/{av['data']['id']}/territoryAvailabilities?limit=200")
        res["appAvailability"] = {"availableInNewTerritories": av["data"]["attributes"].get("availableInNewTerritories"),
                                  "available": sum(1 for t in ta if t["attributes"].get("available")),
                                  "total": len(ta)}
    else:
        res["appAvailability"] = (av or {}).get("_error") if av else "not set"
    vers, inc, _ = get_all(f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=5&include=build")
    builds = {i["id"]: i["attributes"].get("version") for i in inc if i["type"] == "builds"}
    res["versions"] = [{"version": v["attributes"].get("versionString"), "state": v["attributes"].get("appStoreState"),
                        "build": builds.get(rel_id(v, "build"))} for v in vers[:5]]
    subs_ = get_all(f"/v1/reviewSubmissions?filter[app]={app_id}&limit=20")
    res["reviewSubmissions"] = [{"id": s["id"], "state": s["attributes"].get("state"),
                                 "submitted": s["attributes"].get("submittedDate")} for s in subs_[0]][:10]
    groups, _, gerr = get_all(f"/v1/apps/{app_id}/subscriptionGroups?limit=50")
    res["groupsError"] = gerr
    res["groups"] = []
    for g in groups:
        gl, _, _ = get_all(f"/v1/subscriptionGroups/{g['id']}/subscriptionGroupLocalizations?limit=50")
        subs, _, _ = get_all(f"/v1/subscriptionGroups/{g['id']}/subscriptions?limit=50")
        res["groups"].append({"id": g["id"], "referenceName": g["attributes"].get("referenceName"),
                              "localizations": [{"locale": x["attributes"].get("locale"),
                                                 "name": x["attributes"].get("name"),
                                                 "state": x["attributes"].get("state")} for x in gl],
                              "subscriptions": [audit_sub(s) for s in subs]})
    iaps, _, ierr = get_all(f"/v1/apps/{app_id}/inAppPurchasesV2?limit=200")
    res["iapsError"] = ierr
    res["inAppPurchases"] = [audit_iap(i) for i in iaps]
    return res


def main():
    total, _, _ = get_all("/v1/territories?limit=200")
    out = {"totalTerritories": len(total), "apps": [audit_app(a) for a in APP_IDS]}
    json.dump(out, open("iap_audit.json", "w"), indent=1)
    print(f"TOTAL TERRITORIES {out['totalTerritories']}")
    for app in out["apps"]:
        print("\n" + "=" * 70)
        print(f"APP {app['appId']} {app.get('name')} {app.get('bundleId')} {app.get('error') or ''}")
        print(f"  appAvailability {app.get('appAvailability')}")
        for v in app.get("versions", []):
            print(f"  VERSION {v}")
        for s in app.get("reviewSubmissions", []):
            print(f"  REVIEW_SUBMISSION {s}")
        if app.get("groupsError"):
            print(f"  GROUPS_ERROR {app['groupsError']}")
        for g in app.get("groups", []):
            print(f"  GROUP {g['id']} {g['referenceName']!r} locs={g['localizations']}")
            for s in g["subscriptions"]:
                print("    SUB " + json.dumps(s, ensure_ascii=False))
        if app.get("iapsError"):
            print(f"  IAPS_ERROR {app['iapsError']}")
        for i in app.get("inAppPurchases", []):
            print("  IAP " + json.dumps(i, ensure_ascii=False))
    print("\nREAD-ONLY: only GET requests were made.")


if __name__ == "__main__":
    if not APP_IDS:
        sys.exit("APP_IDS is required")
    main()
