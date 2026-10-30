from pathlib import Path
import json,urllib.request,urllib.error,datetime
PROJECT='guardia-a63bd'
ROOT=f'projects/{PROJECT}/databases/(default)/documents'
API='https://firestore.googleapis.com/v1/'
def token():
    p=Path.home()/'.config/configstore/firebase-tools.json'
    value=json.loads(p.read_text()).get('tokens',{}).get('access_token')
    if not value: raise SystemExit('Run Backend/.firebase-tools/firebase login first.')
    return value
def request(path,body=None):
    req=urllib.request.Request(API+path,data=json.dumps(body).encode() if body is not None else None,headers={'Authorization':'Bearer '+token(),'Content-Type':'application/json'})
    with urllib.request.urlopen(req,timeout=30) as res: return json.load(res)
def documents():
    result=[]; page=''
    while True:
        data=request(ROOT+'/fareReferences?pageSize=100'+('&pageToken='+urllib.parse.quote(page,safe='') if page else ''))
        result.extend(data.get('documents',[]))
        page=data.get('nextPageToken','')
        if not page:return result
existing={d['name'].split('/')[-1]:d for d in documents()}
writes=[]
for area in ['colombo','kandy','galle']:
    for band in range(1,21):
        name=f'LK_{area}_tuktuk_{band}'
        if name in existing:continue
        fields={'published':{'booleanValue':False},'currency':{'stringValue':'LKR'},'area':{'stringValue':area},'vehicle':{'stringValue':'tuktuk'},'distanceBand':{'integerValue':str(band)},'sampleCount':{'integerValue':'0'},'setupStatus':{'stringValue':'awaiting_genuine_reports'}}
        writes.append({'update':{'name':ROOT+'/fareReferences/'+name,'fields':fields},'currentDocument':{'exists':False}})
if writes:request(f'projects/{PROJECT}/databases/(default)/documents:commit',{'writes':writes})
verified=documents()
expected={f'LK_{a}_tuktuk_{b}' for a in ['colombo','kandy','galle'] for b in range(1,21)}
found={d['name'].split('/')[-1]:d for d in verified}
assert expected <= found.keys(),'Some templates missing'
for name in expected-existing.keys():
    f=found[name]['fields']
    assert f['published']['booleanValue'] is False
    assert f['sampleCount']['integerValue']=='0'
    assert not any(k in f for k in ['lower','median','upper','updatedAt'])
print(json.dumps({'project':PROJECT,'created_unpublished_templates':len(writes),'verified_supported_records':len(expected),'existing_records_preserved':len(existing),'published_records':sum(d['fields'].get('published',{}).get('booleanValue') is True for d in verified),'fabricated_prices':False},indent=2))
