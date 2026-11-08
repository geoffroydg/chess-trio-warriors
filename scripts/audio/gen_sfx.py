"""Effets sonores procéduraux (numpy uniquement) -> app/assets/audio/sfx/*.ogg.

Usage : python -I scripts/audio/gen_sfx.py [dossier_sortie]
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
rng = np.random.default_rng(7)


def t_axis(d):
    return np.arange(int(SR * d)) / SR


def env(n, a=0.005, r=0.1, curve=2.0):
    e = np.ones(n)
    na, nr = max(1, int(a * SR)), max(1, int(r * SR))
    e[:na] = np.linspace(0, 1, na)
    e[-nr:] *= np.linspace(1, 0, nr) ** curve
    return e


def onepole_lp(x, cutoff):
    """Passe-bas à 1 pôle ; cutoff peut être un tableau (Hz)."""
    c = np.broadcast_to(cutoff, x.shape)
    a = 1 - np.exp(-2 * np.pi * c / SR)
    y = np.empty_like(x)
    s = 0.0
    for i in range(len(x)):
        s += a[i] * (x[i] - s)
        y[i] = s
    return y


def sweep(f0, f1, d, expo=True):
    t = t_axis(d)
    f = f0 * (f1 / f0) ** (t / d) if expo else f0 + (f1 - f0) * t / d
    return np.cumsum(f) / SR * 2 * np.pi


def saw(phase):
    return 2 * ((phase / (2 * np.pi)) % 1) - 1


def aura():
    d = 1.3
    t = t_axis(d)
    ph = sweep(110, 440, d)
    x = np.sin(ph) + 0.5 * np.sin(ph * 1.005 * 2) + 0.3 * saw(ph * 0.5)
    x *= 0.6 + 0.4 * np.sin(2 * np.pi * 14 * t)
    n = onepole_lp(rng.standard_normal(len(t)), 300 + 3000 * t / d)
    x = x * 0.7 + n * 1.5
    return x * np.sin(np.pi * np.clip(t / d, 0, 1)) ** 1.5


def dash():
    d = 0.35
    n = rng.standard_normal(int(SR * d))
    t = t_axis(d)
    x = onepole_lp(n, 6000 * np.exp(-6 * t) + 300)
    return x * 2 * env(len(x), 0.02, 0.2)


def impact():
    d = 0.45
    t = t_axis(d)
    thump = np.sin(sweep(150, 38, d)) * np.exp(-9 * t)
    click = onepole_lp(rng.standard_normal(len(t)), 5000) * np.exp(-60 * t)
    return thump * 1.2 + click * 0.9


def explosion():
    d = 1.8
    t = t_axis(d)
    n = rng.standard_normal(len(t))
    body = onepole_lp(n, 4000 * np.exp(-3.2 * t) + 80) * np.exp(-2.2 * t) * 3
    boom = np.sin(sweep(90, 28, d)) * np.exp(-2.5 * t) * 1.3
    crackle = (rng.random(len(t)) > 0.997) * rng.standard_normal(len(t)) * np.exp(-1.5 * t)
    return body + boom + crackle * 1.5


def beam():
    d = 1.0
    t = t_axis(d)
    ph = sweep(220, 880, d, expo=False) + 3 * np.sin(2 * np.pi * 9 * t)
    x = 0.6 * saw(ph) + 0.4 * np.sin(ph * 2) + 0.25 * np.sin(ph * 3)
    x = onepole_lp(x, 2500 + 4000 * t / d)
    x += 0.15 * onepole_lp(rng.standard_normal(len(t)), 6000)
    return x * env(len(t), 0.08, 0.35)


def tick():
    d = 0.09
    t = t_axis(d)
    return (np.sin(2 * np.pi * 1800 * t) + 0.5 * np.sin(2 * np.pi * 3600 * t)) * np.exp(-55 * t)


def notify():
    d = 0.6
    t = t_axis(d)
    a = np.sin(2 * np.pi * 660 * t) + 0.3 * np.sin(2 * np.pi * 1320 * t)
    b = np.sin(2 * np.pi * 990 * t) + 0.3 * np.sin(2 * np.pi * 1980 * t)
    b = np.where(t > 0.12, b, 0)
    return (a * np.exp(-7 * t) + np.roll(b, 0) * np.exp(-6 * np.clip(t - 0.12, 0, None))) * 0.8


SOUNDS = {
    'aura': aura, 'dash': dash, 'impact': impact, 'explosion': explosion,
    'beam': beam, 'tick': tick, 'notify': notify,
}


def write_ogg(x, path):
    x = np.asarray(x, dtype=np.float64)
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.89
    pcm = (x * 32767).astype('<i2')
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, 'a.wav')
        with wave.open(wav, 'wb') as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav, '-ac', '1',
                        '-c:a', 'libvorbis', '-q:a', '3', path], check=True)


def main():
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, 'app', 'assets', 'audio', 'sfx')
    os.makedirs(out, exist_ok=True)
    for name, fn in SOUNDS.items():
        write_ogg(fn(), os.path.join(out, name + '.ogg'))
        print('sfx', name)


if __name__ == '__main__':
    main()
