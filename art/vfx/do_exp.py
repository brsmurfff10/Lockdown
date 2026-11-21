from pack import *
import post
post.HUEMIX=1.0
def conv(P,t,smoke):
    b=to_straight(P,0.5,emissive=False,sat=1.5)
    if smoke: return b
    a=to_straight(P,0.5,emis_gain=1.8,emis_gamma=0.7,sat=1.5)
    w=float(np.exp(-t/0.12))
    st=b.copy(); st[...,3]=b[...,3]*(1-w)+a[...,3]*w
    pre=a[...,:3]*a[...,3:4]*w+b[...,:3]*b[...,3:4]*(1-w)
    st[...,:3]=pre/np.maximum(st[...,3:4],1e-4)
    return st
res={}
for d,smoke,name in (("epfinal",False,"explosion_sheet.png"),("epsmoke",True,"explosion_smoke_sheet.png")):
    S=[load(f) for f in sorted(glob.glob(d+"/*.npy"))]; assert len(S)==64
    full=[conv(P,i/63,smoke) for i,P in enumerate(S)]
    if d=="epfinal":
        mr=max_radius([f[...,3] for f in full],0.05); scale=0.85/mr
    print(d,"raw",mr,"scale",scale)
    fr=[]
    for i,P in enumerate(S):
        R=recenter_scale(P,scale,256)
        f=vignette(conv(R,i/63,smoke),0.9,1.0)
        t=i/63; x=min(max((t-0.7)/0.3,0),1); f[...,3]*=1-0.92*x*x*(3-2*x)
        fr.append(f)
    ext=[max_radius([f[...,3]],0.05) for f in fr]
    print("extent per frame (0.05)", [round(e,2) for e in ext[::4]], "peak", max(ext))
    print("last frame max alpha", fr[-1][...,3].max())
    save(sheet(fr,8,256),name); res[d]=fr
np.save("exp_strip_idx.npy",np.array([0]))
contact(res["epfinal"][::2],8,"exp_final_contact.png")
contact(res["epsmoke"][::4],8,"expsmoke_final_contact.png")
