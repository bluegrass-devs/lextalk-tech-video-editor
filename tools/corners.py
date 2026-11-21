# usage: corners.py frames.gray W H base fps thr > out.tsv
# per sample: t, blob area, TL TR BL BR corners (in 1920x1080 coords) of the largest bright blob
import sys
from collections import deque
p,W,H,base,fps,thr=sys.argv[1],int(sys.argv[2]),int(sys.argv[3]),float(sys.argv[4]),float(sys.argv[5]),int(sys.argv[6])
K=1920/W; n=W*H; d=open(p,'rb').read()
for fi in range(len(d)//n):
    f=d[fi*n:(fi+1)*n]
    seen=bytearray(n); best=None
    for i in range(0,n,3):
        if f[i]<thr or seen[i]: continue
        q=deque([i]); seen[i]=1; pts=[]
        while q:
            j=q.popleft(); pts.append(j); y,x=divmod(j,W)
            for k in ((j-1) if x>0 else -1,(j+1) if x<W-1 else -1,(j-W) if y>0 else -1,(j+W) if y<H-1 else -1):
                if k>=0 and not seen[k] and f[k]>=thr: seen[k]=1; q.append(k)
        if best is None or len(pts)>len(best): best=pts
    t=base+fi/fps
    if not best or len(best)<2000: print(f"{t:.2f}\t0"); continue
    xy=[(j%W,j//W) for j in best]
    tl=min(xy,key=lambda a:a[0]+a[1]); br=max(xy,key=lambda a:a[0]+a[1])
    tr=max(xy,key=lambda a:a[0]-a[1]); bl=min(xy,key=lambda a:a[0]-a[1])
    c=" ".join(f"{a[0]*K:.0f} {a[1]*K:.0f}" for a in (tl,tr,bl,br))
    print(f"{t:.2f}\t{len(best)}\t{c}")
