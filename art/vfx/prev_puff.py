import sys; sys.path.insert(0,'.')
from post import *
name=sys.argv[1]; exp=float(sys.argv[2])
fr=[to_straight(load(f),exp,emissive=False) for f in sorted(glob.glob(f"{name}/*.npy"))]
for f in fr[:2]: print('alpha max',f[...,3].max())
contact(fr,4,f"{name}_contact.png")
