import sys; sys.path.insert(0,'.')
from post import *
d=sys.argv[1]; exp=float(sys.argv[2]); step=int(sys.argv[3]) if len(sys.argv)>3 else 1
fs=sorted(glob.glob(f"{d}/*.npy"))[::step]
fr=[]
for f in fs:
    P=load(f); t=int(os.path.basename(f)[1:4])/63
    w=float(np.exp(-t/0.12))
    a=to_straight(P,exp,emis_gain=1.8,emis_gamma=0.7); b=to_straight(P,exp,emissive=False)
    # blend alpha: emissive alpha only while hot
    st=b.copy(); st[...,3]=b[...,3]*(1-w)+a[...,3]*w
    pre=a[...,:3]*a[...,3:4]*w+b[...,:3]*b[...,3:4]*(1-w)
    st[...,:3]=pre/np.maximum(st[...,3:4],1e-4)
    fr.append(st)
contact(fr,8,f"{d}_contact.png")
