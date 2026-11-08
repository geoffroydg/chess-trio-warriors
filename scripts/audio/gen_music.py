"""Musique -> app/assets/audio/music/{menu,battle,tension,victory}.ogg

MusicGen (facebook/musicgen-small, CPU) avec repli procédural numpy/Python si
MusicGen est absent, échoue ou dépasse le temps imparti (MUSICGEN_TIMEOUT, 900 s
par morceau). Boucles propres par fondu croisé fin -> début (sauf victory).

Usage : python -I scripts/audio/gen_music.py [dossier_sortie] [--fallback-only]
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 32000  # fréquence de MusicGen
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TIMEOUT = int(os.environ.get('MUSICGEN_TIMEOUT', '900'))

TRACKS = {
    'menu': dict(seconds=30, loop=True, bpm=100, style='heroic',
                 prompt='heroic 90s anime opening theme, warm distorted electric guitars, '
                        'soaring brass, steady drums, hopeful, epic, instrumental'),
    'battle': dict(seconds=30, loop=True, bpm=160, style='battle',
                   prompt='energetic 90s anime battle rock, distorted electric guitars, '
                          'brass stabs, fast drums, heroic, intense, instrumental'),
    'tension': dict(seconds=20, loop=True, bpm=130, style='tension',
                    prompt='tense dark anime showdown, pulsing bass, low distorted guitar, '
                           'ominous brass, driving drums, suspense, instrumental'),
    'victory': dict(seconds=10, loop=False, bpm=120, style='victory',
                    prompt='triumphant victory fanfare, bright brass, electric guitar, '
                           'big drums, 90s anime, heroic, instrumental'),
}


# ------------------------------------------------------------------ utilitaires
def lowpass(x, cutoff):
    a = 1 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    s = 0.0
    for i in range(len(x)):
        s += a * (x[i] - s)
        y[i] = s
    return y


def saw(freq, n, detune=0.0):
    ph = np.cumsum(np.full(n, freq * (1 + detune) / SR))
    return 2 * (ph % 1) - 1


def adsr(n, a=0.005, r=0.05, decay=0.0):
    e = np.exp(-decay * np.arange(n) / SR) if decay else np.ones(n)
    na, nr = max(1, min(n, int(a * SR))), max(1, min(n, int(r * SR)))
    e[:na] *= np.linspace(0, 1, na)
    e[-nr:] *= np.linspace(1, 0, nr)
    return e


def add(buf, start, sig, gain=1.0, pan=0.0):
    end = min(len(buf), start + len(sig))
    if end <= start:
        return
    s = sig[:end - start] * gain
    buf[start:end, 0] += s * (1 - max(0, pan))
    buf[start:end, 1] += s * (1 + min(0, pan))


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


# ------------------------------------------------------------------ batterie / instruments
def kick():
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    ph = np.cumsum(45 + 110 * np.exp(-t * 28)) / SR * 2 * np.pi
    return np.sin(ph) * np.exp(-t * 14) * 1.4


def snare(rng):
    n = int(0.22 * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n) * np.exp(-t * 20)
    return noise * 0.8 + np.sin(2 * np.pi * 190 * t) * np.exp(-t * 25) * 0.6


def hat(rng, open_=False):
    n = int((0.18 if open_ else 0.05) * SR)
    t = np.arange(n) / SR
    x = np.diff(rng.standard_normal(n + 1))  # passe-haut
    return x * np.exp(-t * (18 if open_ else 80)) * 0.35


def power_chord(root_midi, n, gain=3.0):
    sig = 0
    for off in (0, 7, 12):
        for d in (-0.004, 0.004):
            sig = sig + saw(hz(root_midi + off), n, d)
    return np.tanh(gain * sig / 6) * adsr(n, 0.004, 0.03)


def brass(chord, n):
    sig = 0
    for m in chord:
        sig = sig + saw(hz(m), n, 0.003) + saw(hz(m), n, -0.003)
    sig = sig / (2 * len(chord))
    sig = np.tanh(1.5 * lowpass(sig, 2400))
    return sig * adsr(n, 0.02, 0.06, decay=2.0)


def bass_note(midi, n):
    return np.tanh(2 * lowpass(saw(hz(midi), n), 500)) * adsr(n, 0.004, 0.03, decay=3.0)


# ------------------------------------------------------------------ morceaux procéduraux
def fallback(name, spec):
    rng = np.random.default_rng(sum(map(ord, name)))
    bpm, style = spec['bpm'], spec['style']
    beat = 60.0 / bpm
    bar = 4 * beat
    bars = max(2, round(spec['seconds'] / bar))
    total = int(bars * bar * SR)
    step = int(beat / 2 * SR)           # croche
    sixteenth = int(beat / 4 * SR)
    drums = np.zeros((total + SR, 2))
    guitar = np.zeros_like(drums)
    low = np.zeros_like(drums)
    horns = np.zeros_like(drums)

    if style == 'victory':
        progression = [(60, (60, 64, 67)), (65, (65, 69, 72)), (67, (67, 71, 74)), (72, (72, 76, 79, 84))]
        progression = (progression * 2)[:bars]
        progression[-1] = (72, (72, 76, 79, 84))
    elif style == 'tension':
        progression = [(57, (57, 60, 63)), (57, (57, 60, 63)), (53, (53, 56, 60)), (56, (56, 59, 62))]
    elif style == 'heroic':
        progression = [(57, (57, 60, 64)), (53, (53, 57, 60)), (48, (48, 52, 55)), (55, (55, 59, 62))]
    else:  # battle
        progression = [(45, (57, 60, 64)), (41, (53, 57, 60)), (43, (55, 59, 62)), (45, (57, 60, 64))]

    for b in range(bars):
        root, chord = progression[b % len(progression)]
        t0 = int(b * bar * SR)
        gr = root if root >= 40 else root + 12  # guitare >= E2
        if style == 'victory':
            add(horns, t0, brass(chord, int(bar * SR * (1.0 if b == bars - 1 else 0.45))), 0.5)
            add(guitar, t0, power_chord(gr - 12 if gr > 55 else gr, int(bar * SR * 0.9), 4.0), 0.5)
            for k in range(4):
                add(drums, t0 + k * int(beat * SR), kick(), 0.9)
                if k % 2:
                    add(drums, t0 + k * int(beat * SR), snare(rng), 0.8)
            for k in range(8):
                add(drums, t0 + k * step, hat(rng), 0.6)
            add(drums, t0, hat(rng, True), 1.0)
            continue
        for k in range(8):  # croches
            pos = t0 + k * step
            if style == 'tension':
                # basse pulsée, tritons, très peu de batterie
                note = root - 12 + (6 if (b % 2 and k in (6, 7)) else 0)
                add(low, pos, bass_note(note, int(step * 0.85)), 0.9)
                if k % 4 == 0:
                    add(guitar, pos, power_chord(gr, int(step * 3.8), 5.0), 0.35)
            elif style == 'heroic':
                add(low, pos, bass_note(root - 12, int(step * 0.9)), 0.8)
                if k % 4 == 0:
                    add(guitar, pos, power_chord(gr, int(step * 3.9), 3.0), 0.45)
            else:  # battle : palm-mute en croches
                add(low, pos, bass_note(root - 12 + (0 if k != 7 else 7), int(step * 0.8)), 0.9)
                add(guitar, pos, power_chord(gr, int(step * 0.7), 6.0), 0.45)
        if style == 'heroic':
            add(horns, t0, brass(chord, int(bar * SR * 0.9)), 0.35)
        if style == 'battle' and b % 2 == 0:
            add(horns, t0, brass(chord, int(beat * SR * 0.6)), 0.4)
            add(horns, t0 + int(2.5 * beat * SR), brass(chord, int(beat * SR * 0.5)), 0.4)
        # batterie
        for k in range(16):
            pos = t0 + k * sixteenth
            if style == 'battle':
                if k % 4 == 0 or k in (10,):
                    add(drums, pos, kick(), 0.9)
                if k % 8 == 4:
                    add(drums, pos, snare(rng), 0.85)
                if k % 2 == 0:
                    add(drums, pos, hat(rng, k % 8 == 6), 0.7)
            elif style == 'heroic':
                if k % 8 == 0:
                    add(drums, pos, kick(), 0.8)
                if k % 8 == 4:
                    add(drums, pos, snare(rng), 0.7)
                if k % 2 == 0:
                    add(drums, pos, hat(rng), 0.5)
            else:  # tension
                if k in (0, 6):
                    add(drums, pos, kick(), 0.8)
                if k == 12:
                    add(drums, pos, snare(rng), 0.6)

    guitar = np.tanh(lowpass_stereo(guitar, 4500) * 1.2)
    mix = drums * 0.9 + guitar * 0.8 + low * 0.9 + horns * 0.7
    mix = mix[:total] if spec['loop'] else mix[:total + SR // 2]
    mix = mix + 0.12 * delay(mix, int(beat * 0.75 * SR))  # ambiance
    if not spec['loop']:
        n = len(mix)
        mix *= np.concatenate([np.ones(n - SR), np.linspace(1, 0, SR)])[:, None]
    return mix


def lowpass_stereo(x, cutoff):
    return np.stack([lowpass(x[:, 0], cutoff), lowpass(x[:, 1], cutoff)], axis=1)


def delay(x, n):
    y = np.zeros_like(x)
    y[n:] = x[:-n]
    return y


# ------------------------------------------------------------------ boucle propre
def make_loop(x, xfade_s=1.5):
    """Fondu croisé de la fin vers le début : la sortie boucle sans clic."""
    n = int(xfade_s * SR)
    if len(x) <= 3 * n:
        return x
    body, tail, head = x[:-n], x[-n:], x[:n]
    out = body.copy()
    w = np.linspace(0, 1, n)[:, None]
    out[:n] = head * np.sqrt(w) + tail * np.sqrt(1 - w)  # puissance constante
    return out


# ------------------------------------------------------------------ MusicGen
def musicgen_worker(prompt, seconds, out_npy):
    import torch
    from transformers import AutoProcessor, MusicgenForConditionalGeneration
    torch.manual_seed(42)
    proc = AutoProcessor.from_pretrained('facebook/musicgen-small')
    model = MusicgenForConditionalGeneration.from_pretrained('facebook/musicgen-small')
    inputs = proc(text=[prompt], padding=True, return_tensors='pt')
    audio = model.generate(**inputs, do_sample=True, guidance_scale=3.0,
                           max_new_tokens=int(seconds * 50) + 20)
    sr = model.config.audio_encoder.sampling_rate
    x = audio[0].float().numpy()            # (canaux, n)
    np.save(out_npy, np.concatenate([[sr], x.reshape(-1)]).astype(np.float32))
    np.save(out_npy + '.shape.npy', np.array(x.shape))


def run_musicgen(spec, tmp):
    out = os.path.join(tmp, 'mg.npy')
    r = subprocess.run([sys.executable, '-I', os.path.abspath(__file__), '--worker',
                        spec['prompt'], str(spec['seconds']), out], timeout=TIMEOUT)
    if r.returncode != 0:
        raise RuntimeError('musicgen a échoué')
    data = np.load(out)
    shape = np.load(out + '.shape.npy')
    sr, x = int(data[0]), data[1:].reshape(tuple(shape))
    if sr != SR:  # ré-échantillonnage linéaire simple
        idx = np.arange(int(x.shape[1] * SR / sr)) * sr / SR
        x = np.stack([np.interp(idx, np.arange(x.shape[1]), c) for c in x])
    x = x.T if x.shape[0] <= 2 else x
    if x.shape[1] == 1:
        x = np.repeat(x, 2, axis=1)
    return x[:, :2].astype(np.float64)


# ------------------------------------------------------------------ export
def encode(x, path):
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.9
    pcm = (x * 32767).astype('<i2')
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, 'a.wav')
        with wave.open(wav, 'wb') as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav, '-af',
                        'loudnorm=I=-18:TP=-1.5:LRA=11', '-ar', '44100', '-ac', '2',
                        '-c:a', 'libvorbis', '-b:a', '96k', path], check=True)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    only_fallback = '--fallback-only' in sys.argv
    out = args[0] if args else os.path.join(ROOT, 'app', 'assets', 'audio', 'music')
    os.makedirs(out, exist_ok=True)
    for name, spec in TRACKS.items():
        x, source = None, 'musicgen'
        if not only_fallback:
            try:
                with tempfile.TemporaryDirectory() as tmp:
                    x = run_musicgen(spec, tmp)
            except Exception as e:
                print('MusicGen indisponible pour', name, '->', repr(e), file=sys.stderr)
        if x is None:
            source = 'repli procédural'
            x = fallback(name, spec)
        if spec['loop']:
            x = make_loop(x)
        encode(x, os.path.join(out, name + '.ogg'))
        print('musique', name, source, f'{len(x) / SR:.1f}s', flush=True)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--worker':
        musicgen_worker(sys.argv[2], float(sys.argv[3]), sys.argv[4])
    else:
        main()
