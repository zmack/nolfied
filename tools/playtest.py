#!/usr/bin/env python3
"""Random-input soak test with grid invariant checks.

Usage: python3 tools/playtest.py OUTDIR SEED STEPS
"""
import sys, random; sys.path.insert(0,'tools')
from retro import Emu
lab={}
for l in open('build/nolfied.lbl'):
    _,a,n=l.split(); lab[n[1:]]=int(a,16)
S=sys.argv[1]; seed=int(sys.argv[2]); N=int(sys.argv[3])
random.seed(seed)
e=Emu('build/nolfied.sfc')
dirs=['up','down','left','right']
maxstage=0; deaths=0; last=None; stuck=0; games=0
prev_nmi=None; prev_ml=None
for i in range(N):
    st=e.wram()[lab['state']]
    if st==0:
        e.run(2,'start'); e.run(2); games+=1; continue
    d=random.choice(dirs); n=random.randint(4,40)
    btn=['b'] if random.random()<0.75 else []
    e.run(n, d, *btn)
    r=e.wram()
    if r[lab['state']]==3 and st!=3: deaths+=1
    maxstage=max(maxstage, r[lab['stage']])
    # sanity: player must be inside the field and in a sane mode
    p=r[lab['p_idx']]|r[lab['p_idx']+1]<<8
    if (p&63)>=60 or (p>>6)>=48 or r[lab['pmode']]>2 or r[lab['state']]>5:
        print('BAD', i, p&63, p>>6, r[lab['pmode']], r[lab['state']]); e.shot(S+f'/bad{seed}.png'); break
    if r[lab['state']]==2 and r[lab['pmode']]==0 and (r[lab['trail_len']]|r[lab['trail_len']+1])==0:
        g=[[r[0x880+y*64+x] for x in range(60)] for y in range(48)]
        bad=None
        for y in range(48):
            for x in range(60):
                v=g[y][x]
                nb=[g[y+dy][x+dx] for dy in (-1,0,1) for dx in (-1,0,1) if (dy or dx) and 0<=y+dy<48 and 0<=x+dx<60]
                if v==1 and 0 in nb: bad=('claimed next to open',x,y)
                if v==2 and 0 not in nb: bad=('orphan edge',x,y)
                if v>3: bad=('temp state',x,y)
                if v==3: bad=('trail left over',x,y)
        bx=r[0x501]>>2; by=r[0x511]>>2
        if g[by][bx] not in (0,3) and r[0x540]: bad=('boss in claimed',bx,by)
        if bad: print('INVARIANT',i,bad); e.shot(S+f'/inv{seed}.png'); break
    nmi=r[lab['nmi_count']]
    if nmi==prev_nmi: print('HANG?', i); break
    prev_nmi=nmi
    if e.frames % 3000 < n: 
        print(f'frame {e.frames} state {r[lab["state"]]} stage {r[lab["stage"]]} pct {r[lab["pct"]]} lives {r[lab["lives"]]}')
print('done frames', e.frames, 'games', games, 'deaths', deaths, 'maxstage', maxstage)
e.shot(S+f'/fuzz{seed}.png')
