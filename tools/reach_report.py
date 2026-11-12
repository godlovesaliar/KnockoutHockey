"""Summarises `-- fightdebug` [reach] lines (fight.gd _measure_reach) from log files:
python tools/reach_report.py <log>... -- per style and move, per outcome, per body.
"""
import re,sys,collections,statistics as st
rows=[]
for f in sys.argv[1:]:
  for l in open(f):
    m=re.search(r'\[reach\] (\w+) (\w+) (\w+) scale=([\d.]+) sep=([\d.]+) (?:range|reach)=([\d.]+) (\S+)\s+d=([\d.]+) along=([+-][\d.]+) up=([+-][\d.]+) side=([\d.]+) need=([\d.]+)',l)
    if m:
      g=m.groups(); rows.append(dict(style=g[0],move=g[1],body=g[2],scale=float(g[3]),sep=float(g[4]),conn=g[6],d=float(g[7]),along=float(g[8]),up=float(g[9]),side=float(g[10]),need=float(g[11])))
print(len(rows),'contacts')
def summ(key):
  by=collections.defaultdict(list)
  for r in rows: by[key(r)].append(r)
  for k in sorted(by):
    v=by[k]
    if len(v)<4: continue
    f=lambda n: st.mean(x[n] for x in v)
    big=sum(1 for x in v if x['d']>0.15)/len(v)
    print(f"  {str(k):34} n={len(v):3} |d|={f('d'):.2f} along={f('along'):+.2f} up={f('up'):+.2f} side={f('side'):.2f} need={f('need'):.2f} sep={f('sep'):.2f}  >15cm {big*100:.0f}%")
print('by style, move:'); summ(lambda r:(r['style'],r['move']))
print('by connect:'); summ(lambda r:r['conn'])
print('by body:'); summ(lambda r:(r['body'], 'tall' if r['scale']>1.02 else ('short' if r['scale']<0.98 else 'avg')))
