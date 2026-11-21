from pack import *
P=[load(f) for f in sorted(glob.glob("pufffinal/*.npy"))]
mr=max_radius([p[...,3] for p in P])
scale=0.94/mr
print("raw radius frac",mr,"scale",scale)
outs=[]
for p in P:
    R=recenter_scale(p,scale,256)
    st=to_straight(R,1.3,emissive=False,alpha_gain=1.0)
    st[...,3]=np.clip(st[...,3],0,1)*0.92
    outs.append(st)
S=sheet(outs,4,256)
save(S,"smoke_puffs.png")
print("final radius frac", max_radius([o[...,3] for o in outs]))
print("centre alpha", np.mean([o[118:138,118:138,3].mean() for o in outs]))
contact(outs,4,"puffs_final_contact.png")
