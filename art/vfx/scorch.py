import sys; sys.path.insert(0, '.')
from post import *

N = 512
rng = np.random.default_rng(11)


def vnoise(n, cells, seed):
    r = np.random.default_rng(seed).random((cells, cells)).astype(np.float32)
    im = Image.fromarray(r, ).resize((n, n), Image.BICUBIC)
    return np.asarray(im)


def fbm(n, base, octs, seed, rough=0.55):
    t = np.zeros((n, n), np.float32); amp = 1; s = 0
    for o in range(octs):
        t += amp * vnoise(n, base * 2 ** o, seed + o); s += amp; amp *= rough
    return t / s


y, x = (np.mgrid[0:N, 0:N] + 0.5) / N * 2 - 1
r = np.sqrt(x * x + y * y)
th = np.arctan2(y, x)
# warp radius with noise for irregular edge
wn = fbm(N, 4, 5, 1)
rw = r + (wn - 0.5) * 0.35
# angular blast streaks
ang = np.zeros_like(r)
for k, (f, a) in enumerate(((7, .5), (13, .3), (29, .2))):
    ph = rng.random() * 6.28
    ang += a * np.sin(th * f + ph + 2 * np.sin(th * 3 + k))
streak = 0.5 + 0.5 * ang
rw = rw - streak * 0.16 * np.clip(r * 1.5, 0, 1)
core = np.clip((0.74 - rw) / 0.42, 0, 1)
core = core * core * (3 - 2 * core)
grain = fbm(N, 16, 4, 20, 0.6)
speck = (fbm(N, 64, 2, 40, 0.5) > 0.62).astype(np.float32) * np.clip(1 - np.abs(rw - 0.72) / 0.2, 0, 1)
alpha = np.clip(core * (0.92 + 0.5 * (grain - 0.5)) * 0.86 + speck * 0.45, 0, 0.88)
# colour: black centre, brown/umber toward rim, slight grey ash
t = np.clip(1 - core, 0, 1)
black = np.array([0.03, 0.026, 0.022]); brown = np.array([0.15, 0.105, 0.072]); ash = np.array([0.28, 0.26, 0.24])
col = black[None, None] * (1 - t[..., None]) + brown[None, None] * t[..., None]
ashm = np.clip((fbm(N, 8, 4, 60) - 0.55) * 4, 0, 1) * core * 0.12
col = col * (1 - ashm[..., None]) + ash * ashm[..., None]
col = col * (0.8 + 0.4 * grain[..., None])
col = srgb(np.clip(col, 0, 1))
img = np.dstack([col, alpha])
print("centre alpha", alpha[N // 2 - 20:N // 2 + 20, N // 2 - 20:N // 2 + 20].mean(), "edge max", alpha[0].max(), alpha[:, 0].max())
to_u8(img).save(SCRATCH + "/scorch_test.png")
bg = tile_floor(N, N, 64)
to_u8(over(bg, img)).convert("RGB").save(SCRATCH + "/scorch_prev.png")
