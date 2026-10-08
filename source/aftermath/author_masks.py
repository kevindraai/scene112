"""Original deterministic soot/streak/char/water channels. No external images."""
from pathlib import Path
import math, random, struct, zlib, hashlib, json
ROOT=Path(__file__).resolve().parents[2]
N=512
rng=random.Random(112404)
freqs=[4,8,16,32,64]
grids={f:[[rng.random() for x in range(f)] for y in range(f)] for f in freqs}
def smooth(t):return t*t*(3-2*t)
def noise(x,y,f):
    x*=f;y*=f;ix=int(math.floor(x));iy=int(math.floor(y));fx=smooth(x-ix);fy=smooth(y-iy)
    a=grids[f][iy%f][ix%f]*(1-fx)+grids[f][iy%f][(ix+1)%f]*fx
    b=grids[f][(iy+1)%f][ix%f]*(1-fx)+grids[f][(iy+1)%f][(ix+1)%f]*fx
    return a*(1-fy)+b*fy
def fbm(x,y):return sum(w*noise(x,y,f) for w,f in zip([.32,.26,.18,.14,.10],freqs))
def byte(v):return max(0,min(255,round(v*255)))
def chunk(kind,data):return struct.pack('!I',len(data))+kind+data+struct.pack('!I',zlib.crc32(kind+data)&0xffffffff)
rows=[]
for y in range(N):
    row=bytearray([0]);v=y/N
    for x in range(N):
        u=x/N;n=fbm(u,v)
        mottled=max(0,min(1,(n-.22)*1.65))
        drift=noise(u,v,8)*.025
        streak=fbm((u+drift)*2.0,v*.20)
        fine=abs(math.sin((u*19+v*17+noise(u,v,16)*3)*math.pi))
        char_detail=max(0,min(1,(fine-.14)*1.1))
        water=max(0,min(1,(fbm(u+.27,v+.53)-.29)*2.0))
        row.extend([byte(mottled),byte(streak),byte(char_detail),byte(water)])
    rows.append(row)
data=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!IIBBBBB',N,N,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(rows),9))+chunk(b'IEND',b'')
out=ROOT/'assets/textures/aftermath/incident_mask.png';out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(data)
manifest={'author':'Original SCENE112 deterministic source','license':'Project private/proprietary','seed':112404,'size':[N,N],'channels':{'R':'mottled soot deposit','G':'vertical streak variation','B':'char edge microstructure','A':'water irregularity'},'sha256':hashlib.sha256(data).hexdigest(),'source':'source/aftermath/author_masks.py'}
(out.parent/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('SCENE112_AFTERMATH_MASK',manifest['sha256'],len(data))
