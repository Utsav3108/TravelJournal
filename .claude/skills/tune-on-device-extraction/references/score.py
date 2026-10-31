import json,sys,re,collections
corpus={c['id']:c for c in json.load(open('corpus.json'))}
JUNK={"hello testing","um uh","can you hear me","okay so uh yeah","what should we have for dinner tonight","the weather is nice today","one two three testing testing","hmm let me think"}
F=['place','category','rating','cost','minutes','travelMode','arrival']
KEY={'place':'place','category':'category','rating':'rating','cost':'cost','minutes':'minutes','travelMode':'travelMode','arrival':'arrival'}
def norm(f,v):
    if v is None: return None
    if isinstance(v,str) and v.strip().lower() in ('','null','none','n/a','nil','unknown','not mentioned','not said'): return None
    if f=='place': return re.sub(r'[^a-z0-9]','',str(v).lower())
    if f in('rating','minutes'): return int(float(v))
    if f=='cost': return float(v)
    if f=='arrival':
        m=re.match(r'^(\d{1,2}):(\d\d)$',str(v)); return f"{int(m[1]):02d}:{m[2]}" if m else str(v)
    return str(v)
def eq(f,e,p):
    if e is None or p is None: return e==p
    if f=='place': return e in p or p in e
    return e==p
def maj(vals):
    cnt=collections.Counter(vals); top=cnt.most_common()
    best=top[0][1]; c=[v for v,n in top if n==best]
    return (None if None in c else c[0]), best/len(vals)
def storyviol(c,r):
    v=[]
    s=r.get('story');h=r.get('highlight');t=c['text']
    if s and len(s.split())>100: v.append('storylen')
    if h and len(h)>60: v.append('hllen')
    tt=set(re.findall(r'\d+',t))
    for x in (s,h):
        if x:
            for d in re.findall(r'\d+',x):
                if d not in tt: v.append('num:'+d)
            for w in re.findall(r'(?<![.!?] )(?<!^)\b[A-Z][a-z]{3,}',x):
                if w.lower() not in t.lower(): v.append('cap:'+w)
    return v
def score(outfile):
    outs=json.load(open(outfile)); res=[]
    for o in outs:
        c=corpus[o['id']]; row=dict(id=o['id'],holdout=c['holdout'],text=c['text'],f={},agree=[],viol=[],err=0)
        junk=c['text'] in JUNK
        for f in F:
            e=norm(f,c[KEY[f]] if f!='travelMode' else c['travelMode'])
            if f=='category': e=c['category']
            preds=[norm(f,r.get(f)) for r in o['runs']]
            p,ag=maj(preds); row['agree'].append(ag)
            row['f'][f]=(e,p)
        if junk:
            preds=[1 if (r.get('story') or r.get('highlight')) else None for r in o['runs']]
            p,_=maj(preds); row['f']['junkstory']=(None,p)
        row['err']=sum(1 for r in o['runs'] if '_error' in r)
        for r in o['runs']: row['viol']+=storyviol(c,r)
        res.append(row)
    return res
def agg(rows):
    tp=fp=fn=wrong=hal=nullf=total=corr=0; perf=collections.defaultdict(lambda:[0,0,0,0])
    for r in rows:
        for f,(e,p) in r['f'].items():
            total+=1
            if e is None:
                nullf+=1
                if p is None: corr+=1
                else: hal+=1; perf[f][2]+=1
            else:
                if p is None: fn+=1; perf[f][1]+=1
                elif eq(f,e,p): tp+=1; corr+=1; perf[f][0]+=1
                else: wrong+=1; perf[f][3]+=1
    exp=tp+fn+wrong; pred=tp+wrong+hal
    return dict(precision=tp/pred if pred else 0,recall=tp/exp if exp else 0,halluc=hal/nullf if nullf else 0,
      score=(corr-3*hal)/total,n=len(rows),tp=tp,miss=fn,wrong=wrong,hal=hal,
      viol=sum(1 for r in rows if r['viol'])/len(rows),agree=sum(sum(r['agree'])/7 for r in rows)/len(rows),errs=sum(r['err'] for r in rows),perf=dict(perf))
def fmt(a):
    return f"score {a['score']:.3f} | P {a['precision']:.3f} R {a['recall']:.3f} | halluc {a['halluc']:.3f} ({a['hal']}) | wrong {a['wrong']} miss {a['miss']} | storyviol {a['viol']:.2f} | agree {a['agree']:.2f} | errs {a['errs']} (n={a['n']})"
def casebad(r):
    bad=[]
    for f,(e,p) in r['f'].items():
        if f=='junkstory':
            if p: bad.append(('junkstory',None,'set'))
        elif not eq(f,e,p): bad.append((f,e,p))
    return bad
if __name__=='__main__':
    rows=score(sys.argv[1]); mode=sys.argv[2] if len(sys.argv)>2 else 'all'
    tr=[r for r in rows if not r['holdout']]; ho=[r for r in rows if r['holdout']]
    if tr: print('TRAIN',fmt(agg(tr)))
    if ho: print('HOLD ',fmt(agg(ho)))
    if mode=='fail':
        pf=agg(tr)['perf']; print('per-field [tp,miss,hal,wrong]:',pf)
        for r in tr:
            b=casebad(r)
            if b or r['viol']: print(r['id'],repr(r['text'][:90]),b,r['viol'][:3])
