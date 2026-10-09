#!/usr/bin/env python3
"""READ-ONLY: fetch TestFlight crash feedback (betaFeedbackCrashSubmissions + crashLog) for one or more apps.

Env: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_API_KEY_P8 (never printed)
     APP_IDS (comma-separated ASC app ids), BUNDLE_IDS (comma-separated, resolved to app ids),
     LIMIT (per app, default 5), OUT (default out)
Only GET requests are issued. Writes out/<app>/... and out/summary.md.
"""
import json, os, sys, time
import jwt, requests

BASE = 'https://api.appstoreconnect.apple.com'
p8 = os.environ['APP_STORE_CONNECT_API_KEY_P8'].replace('\\n', '\n').strip()
now = int(time.time())
tok = jwt.encode({'iss': os.environ['APP_STORE_CONNECT_ISSUER_ID'].strip(), 'iat': now, 'exp': now + 1200,
                  'aud': 'appstoreconnect-v1'}, p8, algorithm='ES256',
                 headers={'kid': os.environ['APP_STORE_CONNECT_KEY_ID'].strip()})
H = {'Authorization': f'Bearer {tok}'}
OUT = os.environ.get('OUT', 'out')
LIMIT = int(os.environ.get('LIMIT') or 5)
os.makedirs(OUT, exist_ok=True)


def get(path):
    url = path if path.startswith('http') else BASE + path
    r = requests.get(url, headers=H, timeout=60)
    print(f'GET {url.replace(BASE, "")[:160]} -> {r.status_code}', flush=True)
    try:
        return r.status_code, r.json()
    except Exception:
        return r.status_code, r.text


app_ids = [a.strip() for a in os.environ.get('APP_IDS', '').split(',') if a.strip()]
for bid in [b.strip() for b in os.environ.get('BUNDLE_IDS', '').split(',') if b.strip()]:
    st, j = get(f'/v1/apps?filter[bundleId]={bid}')
    for a in (j.get('data', []) if isinstance(j, dict) else []):
        if a['attributes'].get('bundleId') == bid and a['id'] not in app_ids:
            app_ids.append(a['id'])

summary = ['# TestFlight crash feedback', '']
for app in app_ids:
    st, info = get(f'/v1/apps/{app}')
    name = info.get('data', {}).get('attributes', {}).get('name') if isinstance(info, dict) and st < 400 else '?'
    bundle = info.get('data', {}).get('attributes', {}).get('bundleId') if isinstance(info, dict) and st < 400 else '?'
    d = os.path.join(OUT, app)
    os.makedirs(d, exist_ok=True)
    summary.append(f'## {name} ({bundle}, app {app})')
    st, subs = get(f'/v1/apps/{app}/betaFeedbackCrashSubmissions?limit={LIMIT}&sort=-createdDate&include=build,tester')
    if st >= 400:
        print(json.dumps(subs)[:800])
        st, subs = get(f'/v1/apps/{app}/betaFeedbackCrashSubmissions?limit={LIMIT}&sort=-createdDate')
    if st >= 400 or not isinstance(subs, dict):
        summary.append(f'- error {st}: {str(subs)[:300]}')
        continue
    json.dump(subs, open(os.path.join(d, 'crash_submissions.json'), 'w'), indent=1)
    inc = {(x['type'], x['id']): x.get('attributes', {}) for x in subs.get('included', [])}
    if not subs.get('data'):
        summary.append('- (no crash submissions)')
    for s in subs.get('data', []):
        a = s['attributes']
        bref = (s.get('relationships', {}).get('build', {}).get('data') or {})
        battr = inc.get(('builds', bref.get('id')), {})
        line = (f"- **{a.get('createdDate')}** submission `{s['id']}` build {battr.get('version', bref.get('id'))} "
                f"device={a.get('deviceModel')} os={a.get('osVersion')} locale={a.get('locale')} "
                f"battery={a.get('batteryPercentage')} appUptimeMs={a.get('appUptimeInMilliseconds')} "
                f"conn={a.get('connectionType')} comment={a.get('comment')!r}")
        print(line, flush=True)
        summary.append(line)
        st, log = get(f"/v1/betaFeedbackCrashSubmissions/{s['id']}/crashLog")
        json.dump(log, open(os.path.join(d, f"crashlog_{s['id']}.json"), 'w'), indent=1)
        text = ((log.get('data') or {}).get('attributes') or {}).get('logText') if isinstance(log, dict) else None
        if text:
            open(os.path.join(d, f"crashlog_{s['id']}.ips"), 'w').write(text)
            summary.append(f'  - crash log: {len(text)} chars -> {app}/crashlog_{s["id"]}.ips')
        else:
            summary.append(f'  - crash log unavailable ({st})')
    summary.append('')

open(os.path.join(OUT, 'summary.md'), 'w').write('\n'.join(summary) + '\n')
print('\n'.join(summary))
gh = os.environ.get('GITHUB_STEP_SUMMARY')
if gh:
    open(gh, 'a').write('\n'.join(summary) + '\n')
