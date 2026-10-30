from pathlib import Path
import json,random,statistics,datetime,urllib.request,urllib.error,csv,argparse
parser=argparse.ArgumentParser(description="Retrain and publish explicitly synthetic/demo fare estimates. Never use these as market forecasts.")
parser.add_argument('--extra-reports', help='Optional CSV: area,distanceKm,fareLKR. Use a complete cumulative export on each retrain.')
args=parser.parse_args()
extra=[]
if args.extra_reports:
    import math
    with open(args.extra_reports,newline='') as stream:
        for row in csv.DictReader(stream):
            a=row['area'];x=float(row['distanceKm']);y=float(row['fareLKR'])
            if a not in ['colombo','kandy','galle'] or not math.isfinite(x) or not math.isfinite(y) or not 0<x<=100 or not 0<y<=1000000:
                raise SystemExit('Invalid extra fare report; no writes performed.')
            extra.append((a,x,y))
rng=random.Random(314159)
project='guardia-a63bd'
root=f'projects/{project}/databases/(default)/documents'
token=json.loads((Path.home()/'.config/configstore/firebase-tools.json').read_text())['tokens']['access_token']
now=datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
rows=[];writes=[];metrics={}
def field(v):
 if isinstance(v,bool):return {'booleanValue':v}
 if isinstance(v,int):return {'integerValue':str(v)}
 if isinstance(v,float):return {'doubleValue':v}
 return {'stringValue':v}
for area,base,rate in [('colombo',110,105),('kandy',100,98),('galle',105,100)]:
 samples=[]
 for i in range(240):
  km=rng.uniform(.3,100)
  fare=round(base+rate*km+rng.gauss(0,35+km*3),2)
  samples.append((km,max(50,fare)))
 samples.extend((x,y) for a,x,y in extra if a==area)
 rng.shuffle(samples)
 cutoff=int(len(samples)*.8)
 train=samples[:cutoff];test=samples[cutoff:]
 mx=statistics.mean(x for x,y in train);my=statistics.mean(y for x,y in train)
 slope=sum((x-mx)*(y-my) for x,y in train)/sum((x-mx)**2 for x,y in train)
 intercept=my-slope*mx
 residuals=sorted(abs(y-(intercept+slope*x)) for x,y in train)
 spread=residuals[int(.9*(len(residuals)-1))]
 mae=statistics.mean(abs(y-(intercept+slope*x)) for x,y in test)
 metrics[area]={'trainingCount':len(train),'testCount':len(test),'extraReportCount':sum(a==area for a,x,y in extra),'holdoutMAE_LKR':round(mae,2)}
 for band in range(1,21):
  km=(band-.5)*5
  median=round(intercept+slope*km,2)
  values={'published':True,'currency':'LKR','area':area,'vehicle':'tuktuk','distanceBand':band,'lower':round(max(1,median-spread),2),'median':median,'upper':round(median+spread,2),'sampleCount':len(train),'dataSource':'synthetic','modelVersion':'synthetic-linear-v1','modelIntercept':intercept,'modelPerKm':slope,'nextMonthMedian':round(median*1.01,2),'assumedMonthlyGrowth':.01,'holdoutMAE':round(mae,2),'setupStatus':'synthetic_demo_only'}
  fields={k:field(v) for k,v in values.items()};fields['updatedAt']={'timestampValue':now}
  writes.append({'update':{'name':root+f'/fareReferences/LK_{area}_tuktuk_{band}','fields':fields}})
 for i,(km,fare) in enumerate(samples):
  rows.append({'area':area,'distanceKm':round(km,4),'fareLKR':fare,'source':'synthetic_or_user_supplied_demo_training','split':'train' if i<cutoff else 'test'})
# Store complete synthetic training data in owner/admin-only model documents.
for area in metrics:
 data={'dataSource':field('synthetic'),'modelVersion':field('synthetic-linear-v1'),'datasetJSON':field(json.dumps([r for r in rows if r['area']==area],separators=(',',':'))),'metricsJSON':field(json.dumps(metrics[area]))}
 writes.append({'update':{'name':root+'/fareModels/synthetic_'+area+'_v1','fields':data}})
for write in writes:
    name=write['update']['name']
    try:
        with urllib.request.urlopen(urllib.request.Request('https://firestore.googleapis.com/v1/'+name,headers={'Authorization':'Bearer '+token}),timeout=20) as response:
            current=json.load(response)
        f=current.get('fields',{})
        if '/fareReferences/' in name and f.get('published',{}).get('booleanValue') and f.get('dataSource',{}).get('stringValue')!='synthetic':
            raise SystemExit('Refusing to overwrite a genuine published fare reference.')
        write['currentDocument']={'updateTime':current['updateTime']}
    except urllib.error.HTTPError as error:
        if error.code!=404: raise
        write['currentDocument']={'exists':False}
req=urllib.request.Request('https://firestore.googleapis.com/v1/'+f'projects/{project}/databases/(default)/documents:commit',data=json.dumps({'writes':writes}).encode(),headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
with urllib.request.urlopen(req,timeout=30) as res: result=json.load(res)
Path('/tmp/guardia-synthetic-fare-metrics.json').write_text(json.dumps(metrics,indent=2))
print(json.dumps({'demoTrainingSamples':len(rows),'publishedDemoReferences':60,'privateModelDocuments':3,'committedWrites':len(result['writeResults']),'metrics':metrics},indent=2))
