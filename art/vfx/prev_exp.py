import sys; sys.path.insert(0,'.')
from post import *
name=sys.argv[1]; sub=sys.argv[2] if len(sys.argv)>2 else 'render'; exp=float(sys.argv[3]) if len(sys.argv)>3 else 1.0
fs=sorted(glob.glob(f"{name}/{sub}/*.npy"))
frames=[]
for f in fs:
    P=load(f); 
    print(os.path.basename(f), 'maxrgb %.2f maxa %.2f'%(P[...,:3].max(), P[...,3].max()))
    frames.append(to_straight(P,exp))
contact(frames,8,f"{name}_{sub}_contact.png")
