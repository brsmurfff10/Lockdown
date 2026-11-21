import numpy as np, glob, os
from PIL import Image

SCRATCH = "C:/Users/lucas/AppData/Local/Temp/claude/eec82e66440eb993/cdba2fb7-a320-4560-b81d-5ae8c6cce097/scratchpad/vfx"


def load(p):
    return np.load(p).astype(np.float32)


def box_down(img, f):
    if f == 1:
        return img
    h, w, c = img.shape
    return img.reshape(h // f, f, w // f, f, c).mean(axis=(1, 3))


def srgb(x):
    x = np.clip(x, 0, 1)
    return np.where(x <= 0.0031308, 12.92 * x, 1.055 * np.power(x, 1 / 2.4) - 0.055)


HUEMIX = 0.7


def tonemap(P, exposure=1.0):
    # soft shoulder on premultiplied linear colour
    x = P * exposure
    pc = 1.0 - np.exp(-x)
    L = (0.2126 * x[..., 0] + 0.7152 * x[..., 1] + 0.0722 * x[..., 2])[..., None]
    hp = x * (1.0 - np.exp(-L)) / np.maximum(L, 1e-6)
    hp = hp / np.maximum(1.0, hp.max(axis=-1, keepdims=True))
    return HUEMIX * hp + (1 - HUEMIX) * pc


def to_straight(P, exposure=1.0, emissive=True, alpha_gain=1.0, alpha_gamma=1.0, emis_gain=1.0, emis_gamma=1.0, sat=1.0):
    """P: premult linear RGBA float. returns straight sRGB RGBA float 0..1"""
    rgb = tonemap(P[..., :3], exposure)
    a = np.clip(P[..., 3] * alpha_gain, 0, 1)
    if alpha_gamma != 1.0:
        a = a ** alpha_gamma
    if emissive:
        a = np.maximum(a, np.clip(rgb.max(axis=-1) * emis_gain, 0, 1) ** emis_gamma)
    a = np.clip(a, 0, 1)
    st = rgb / np.maximum(a, 1e-4)[..., None]
    st = srgb(np.clip(st, 0, 1))
    if sat != 1.0:
        lm = st.mean(axis=-1, keepdims=True)
        st = np.clip(lm + (st - lm) * sat, 0, 1)
    return np.dstack([st, a])


def to_u8(img):
    return Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def tile_floor(w, h, tile=64):
    y, x = np.mgrid[0:h, 0:w]
    base = 0.42 + 0.03 * (((x // tile) + (y // tile)) % 2)
    grout = ((x % tile) < 2) | ((y % tile) < 2)
    base = np.where(grout, 0.33, base)
    return np.dstack([base, base, base * 1.02, np.ones_like(base)])


def over(bg, fg):
    a = fg[..., 3:4]
    out = bg.copy()
    out[..., :3] = fg[..., :3] * a + bg[..., :3] * (1 - a)
    return out


def contact(frames, cols, path, cell=None):
    """frames: list of straight RGBA float arrays; composite over floor"""
    h, w = frames[0].shape[:2]
    rows = (len(frames) + cols - 1) // cols
    bg = tile_floor(cols * w, rows * h, 32)
    for i, f in enumerate(frames):
        r, c = divmod(i, cols)
        bg[r * h:(r + 1) * h, c * w:(c + 1) * w] = over(bg[r * h:(r + 1) * h, c * w:(c + 1) * w], f)
    to_u8(bg).convert("RGB").save(path)
