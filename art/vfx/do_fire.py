from pack import *
import post
post.HUEMIX=0.7
S=[load(f) for f in sorted(glob.glob("fire3/render/*.npy"))]
assert len(S)==80
NN,LL=64,16
out=[]
for i in range(NN):
    if i<LL:
        w=i/LL; w=w*w*(3-2*w)
        out.append(S[NN+i]*(1-w)+S[i]*w)
    else:
        out.append(S[i])
# extent measured on emissive alpha
def st(P): return to_straight(P,0.9,emis_gain=1.8,emis_gamma=0.7,sat=1.15)
mr=max_radius([st(P)[...,3] for P in out[::4]],0.12)
scale=0.94/mr
print("raw",mr,"scale",scale)
fr=[vignette(st(recenter_scale(P,scale,256))) for P in out]
print("final extent", max_radius([f[...,3] for f in fr],0.03), "solid(0.3)", max_radius([f[...,3] for f in fr],0.3))
save(sheet(fr,8,256),"fire_sheet.png")
contact(fr[:16],8,"fire_final_contact.png")
# loop seam check: diff between last and first vs typical consecutive diff
d=lambda a,b: np.abs(a-b).mean()
print("seam diff", d(fr[63],fr[0]), "typical", np.mean([d(fr[i],fr[i+1]) for i in range(20,40)]))
