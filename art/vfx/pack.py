import sys, math; sys.path.insert(0, '.')
from post import *

OUT = "C:/Users/lucas/OneDrive/Documents/Lockdown/assets/vfx"
os.makedirs(OUT, exist_ok=True)


def max_radius(frames_alpha, thr=0.03):
    h, w = frames_alpha[0].shape
    y, x = np.mgrid[0:h, 0:w]
    rr = np.sqrt((x + 0.5 - w / 2) ** 2 + (y + 0.5 - h / 2) ** 2)
    m = 0
    for a in frames_alpha:
        sel = a > thr
        if sel.any():
            m = max(m, rr[sel].max())
    return m / (w / 2)   # fraction of half-width


def recenter_scale(P, scale, out):
    """P premult RGBA (h,w,4). zoom by scale about centre, resample to out x out (premult, lanczos per channel)"""
    h, w = P.shape[:2]
    crop = w / scale
    if crop > w:
        pad = int(math.ceil((crop - w) / 2)) + 2
        P = np.pad(P, ((pad, pad), (pad, pad), (0, 0)))
        h, w = P.shape[:2]
    l = (w - crop) / 2
    chans = []
    for c in range(4):
        im = Image.fromarray(np.ascontiguousarray(P[..., c]).astype(np.float32))
        im = im.resize((out, out), Image.LANCZOS, box=(l, l, l + crop, l + crop))
        chans.append(np.asarray(im))
    R = np.stack(chans, -1)
    R[..., 3] = np.clip(R[..., 3], 0, None)
    R[..., :3] = np.clip(R[..., :3], 0, None)
    return R


def sheet(frames, cols, cell):
    rows = (len(frames) + cols - 1) // cols
    S = np.zeros((rows * cell, cols * cell, 4), np.float32)
    for i, f in enumerate(frames):
        r, c = divmod(i, cols)
        S[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell] = f
    return S


def save(img, name):
    # zero colour where fully transparent for clean edges
    img = img.copy()
    img[img[..., 3] < 1.5 / 255] = 0
    to_u8(img).save(OUT + "/" + name, optimize=True)
    print("saved", name, img.shape)


def vignette(img, inner=0.86, outer=0.99):
    h, w = img.shape[:2]
    y, x = (np.mgrid[0:h, 0:w] + 0.5) / (w / 2) - 1
    r = np.sqrt(x * x + y * y)
    v = np.clip((outer - r) / (outer - inner), 0, 1)
    v = v * v * (3 - 2 * v)
    img = img.copy(); img[..., 3] *= v
    return img
