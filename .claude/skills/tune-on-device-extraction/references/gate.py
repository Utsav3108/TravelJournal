import re,json
G={
'rating':r"star|out of (5|five)|/ ?5|\brat(e|ed|ing)\b|gave it (a |an )?(\d|one|two|three|four|five)|\b(one|two|three|four|five) stars?\b",
'cost':r"rupee|\brs\b|₹|\bfree\b|nothing|paid|cost|spent|price|fee\b|ticket|\bbill\b|\d{2,}",
'minutes':r"hour|minute|\bmins?\b|\bhrs?\b",
'travelMode':r"\bauto\b|rickshaw|\bcab\b|taxi|\bola\b|uber|\bbus\b|train|local|metro|\bwalk|\bbik(e|ed|ing)\b|rode|\bferry|boat",
'arrival':r"\b(am|pm)\b|\bat \d|\bat (noon|midnight)|reached|arrived|got (there|in)|quarter|noon|showed up|around \d",
'category':r"temple|mandir|food|ate|eat|lunch|dinner|breakfast|cafe|restaurant|thali|stay|hotel|room|hostel|zostel|shop|market|bought|souvenir|fort|palace|gate|mahal|minar|park|lake|beach|ghat|garden|caves|station|drive|chowk|haat|museum",
}
def gate(text,r):
    r=dict(r)
    for f,p in G.items():
        if f in r and not re.search(p,text): del r[f]
    # place gate: must be a substring-ish of transcript tokens, reject generic
    if 'place' in r:
        n=re.sub(r'[^a-z0-9 ]','',r['place'].lower()).strip()
        if n in ('place','the place','temple','the temple','market','station','tickets','room','rs','null','') or not n or re.fullmatch(r'[\d ]*(am|pm|rs)?[\d ]*',n): del r['place']
    return r
if __name__=='__main__':
    import sys
    src,dst=sys.argv[1:3]
    C={c['id']:c for c in json.load(open('corpus.json'))}
    O=json.load(open(src))
    for o in O: o['runs']=[gate(C[o['id']]['text'],r) for r in o['runs']]
    json.dump(O,open(dst,'w'))
