#!/usr/bin/env python3
"""Live smoke test using synthetic data only; removes its records and accounts."""
import datetime, json, plistlib, sys, urllib.error, urllib.request, uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
config_path = root / 'Guardia/Resources/GoogleService-Info.plist'
if not config_path.exists():
    config_path = Path('/Users/heshanx/Documents/GuardiaApp/Guardia/Resources/GoogleService-Info.plist')
config = plistlib.loads(config_path.read_bytes())
project, key = config['PROJECT_ID'], config['API_KEY']
base = f'https://firestore.googleapis.com/v1/projects/{project}/databases/(default)/documents'
results, identities, records = {}, [], []

def call(url, method='GET', body=None, token=None):
    headers = {'Content-Type': 'application/json', 'X-Ios-Bundle-Identifier': config['BUNDLE_ID']}
    if token: headers['Authorization'] = 'Bearer ' + token
    request = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()

def check(name, code, expected, valid=True):
    results[name] = {'http': code, 'passed': code in expected and valid}

def signup():
    code, data = call(f'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={key}', 'POST', {'returnSecureToken': True})
    if code != 200:
        check('anonymous_auth', code, [200]); raise RuntimeError('Anonymous sign-in failed')
    value = json.loads(data); identities.append(value['idToken'])
    return value['localId'], value['idToken']

try:
    code, data = call(f'https://{project}.web.app/track.html')
    check('hosted_tracker', code, [200], b'Guardia live trip' in data and project.encode() in data)
    uid, owner = signup(); other_uid, other = signup()
    check('anonymous_auth', 200, [200])
    share = uuid.uuid4().hex + uuid.uuid4().hex
    now = datetime.datetime.now(datetime.timezone.utc)
    iso = lambda value: value.isoformat(timespec='seconds').replace('+00:00', 'Z')
    fields = {'ownerUid': {'stringValue': uid}, 'destination': {'stringValue': 'Guardia verification — synthetic data'},
              'state': {'stringValue': 'active'}, 'updatedAt': {'timestampValue': iso(now)},
              'expiresAt': {'timestampValue': iso(now + datetime.timedelta(minutes=10))},
              'route': {'arrayValue': {'values': []}}}
    url = base + '/liveShares/' + share
    code, _ = call(url + '?currentDocument.exists=false', 'PATCH', {'fields': fields}, owner)
    check('owner_create', code, [200])
    if code == 200:
        records.append((url, owner))
        code, _ = call(url); check('recipient_read', code, [200])
        code, _ = call(base + '/liveShares?pageSize=1'); check('public_listing_denied', code, [403])
        code, _ = call(url, 'PATCH', {'fields': fields}, other); check('other_user_write_denied', code, [403])
        invalid = dict(fields); invalid['state'] = {'stringValue': 'invalid'}
        code, _ = call(url, 'PATCH', {'fields': invalid}, owner); check('invalid_state_denied', code, [403])
        changed = dict(fields); changed['state'] = {'stringValue': 'check_in'}
        code, _ = call(url + '?currentDocument.exists=true', 'PATCH', {'fields': changed}, owner); check('owner_update', code, [200])
        code, data = call(url)
        state = json.loads(data).get('fields', {}).get('state', {}).get('stringValue')
        check('recipient_sees_update', code, [200], state == 'check_in')
        code, _ = call(url, 'DELETE', token=owner); check('owner_revoke', code, [200])
        code, _ = call(url); check('revoked_link_denied', code, [403, 404])
        expired = dict(fields); expired['expiresAt'] = {'timestampValue': iso(now - datetime.timedelta(minutes=1))}
        code, _ = call(url, 'PATCH', {'fields': expired}, owner); check('expired_share_denied', code, [403])
except Exception as error:
    # Do not print credentials, URLs containing API keys or exception request details.
    results['interrupted'] = {'passed': False, 'kind': type(error).__name__}
finally:
    for url, owner in records:
        code, _ = call(url, 'DELETE', token=owner); check('test_record_cleanup', code, [200, 404])
    cleanup = True
    for token in identities:
        code, _ = call(f'https://identitytoolkit.googleapis.com/v1/accounts:delete?key={key}', 'POST', {'idToken': token})
        cleanup = cleanup and code == 200
    results['test_account_cleanup'] = {'passed': cleanup}
    print(json.dumps(results, indent=2))
    sys.exit(0 if results and all(value.get('passed') for value in results.values()) else 1)
