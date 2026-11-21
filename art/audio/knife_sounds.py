"""Synthesizes the knife and weapon-draw sounds (mono 16-bit 44.1 kHz).
Usage: python art/audio/knife_sounds.py <project>/audio"""
import sys, wave, numpy as np

SR = 44100
rng = np.random.default_rng(3)


def _write(path, x):
    x = x / max(1e-6, np.abs(x).max()) * 0.85
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def _bandpass(x, lo, hi):
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    f[(fr < lo) | (fr > hi)] = 0
    return np.fft.irfft(f, len(x))


def swish(dur=0.26):
    """Air swish: noise whose band sweeps up then down, loud in the middle."""
    n = int(SR * dur)
    t = np.linspace(0, 1, n)
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    seg = 512
    for i in range(0, n, seg):
        k = i / n
        centre = 900 + 2600 * np.sin(np.pi * k) ** 2
        chunk = noise[max(0, i - seg):i + seg * 2]
        bp = _bandpass(chunk, centre * 0.6, centre * 1.5)
        start = seg if i >= seg else 0
        out[i:i + seg] = bp[start:start + seg][:len(out[i:i + seg])]
    env = np.sin(np.pi * t) ** 1.6 * (1 - t) ** 0.3
    return out * env


def hit():
    """Knife connecting: a dull body thud plus a short cloth/flesh tear."""
    n = int(SR * 0.22)
    t = np.arange(n) / SR
    thud = np.sin(2 * np.pi * (140 - 260 * t) * t) * np.exp(-t * 28)
    tear = _bandpass(rng.standard_normal(n), 600, 3200) * np.exp(-t * 40)
    return thud * 1.0 + tear * 0.6


def draw():
    """Weapon coming up: cloth rustle then a metallic click."""
    n = int(SR * 0.42)
    t = np.arange(n) / SR
    rustle = _bandpass(rng.standard_normal(n), 300, 2500) * np.exp(-((t - 0.12) / 0.07) ** 2) * 0.5
    ct = np.clip(t - 0.3, 0, None)
    click = (np.sin(2 * np.pi * 3100 * ct) + 0.6 * np.sin(2 * np.pi * 5200 * ct)) * np.exp(-ct * 90) * (t > 0.3)
    click2 = _bandpass(rng.standard_normal(n), 2000, 8000) * np.exp(-ct * 160) * (t > 0.3) * 0.5
    return rustle + click * 0.8 + click2


if __name__ == "__main__":
    out = sys.argv[1]
    _write(out + "/knife_slash.wav", swish())
    _write(out + "/knife_hit.wav", hit())
    _write(out + "/weapon_draw.wav", draw())
    print("ok")
