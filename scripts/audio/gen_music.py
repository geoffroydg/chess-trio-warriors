"""Musique orchestrale composée -> app/assets/audio/music/*.ogg

Chaîne : partitions algorithmiques (scores.py / compose.py, graine fixe par
morceau) -> MIDI (scripts/audio/out/*.mid) -> FluidSynth + soundfont General
MIDI FluidR3_GM (MIT) -> ffmpeg (réverbération de salle douce par convolution,
EQ, compression légère, loudnorm 2 passes, fondus) -> OGG Vorbis stéréo 44,1 kHz.

Usage : python -I scripts/audio/gen_music.py [dossier_sortie] [--only menu,game_1] [--midi-only]
Prérequis : pip install mido numpy ; apt install fluidsynth fluid-soundfont-gm ffmpeg.
Variable SOUNDFONT : chemin d'une autre soundfont .sf2.
"""
import json
import os
import subprocess
import sys
import tempfile
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)  # python -I n'ajoute pas le dossier du script

import numpy as np  # noqa: E402

import scores  # noqa: E402

SR = 44100
SF_CANDIDATES = [
    os.environ.get('SOUNDFONT', ''),
    '/usr/share/sounds/sf2/FluidR3_GM.sf2',
    '/usr/share/soundfonts/FluidR3_GM.sf2',
    '/usr/share/sounds/sf2/default-GM.sf2',
]
# Cible de sonie (LUFS intégrés) : musique de jeu discrète, jingles un peu plus présents.
LOUDNESS = {'victory': -18, 'defeat': -19, 'check_sting': -17}
MAX_LEN = {'victory': 16.0, 'defeat': 11.0, 'check_sting': 3.2}
# Qualité Vorbis (~55-60 kb/s sur cette musique douce) : tient les 12 Mo pour ~23 min.
QUALITY = os.environ.get('MUSIC_VORBIS_Q', '0.6')
FADE_OUT = {'check_sting': 0.6, 'victory': 2.0, 'defeat': 2.0}


def soundfont():
    for p in SF_CANDIDATES:
        if p and os.path.isfile(p):
            return p
    raise SystemExit('soundfont FluidR3_GM introuvable (apt install fluid-soundfont-gm ou SOUNDFONT=...)')


def write_wav(path, x, sr=SR):
    pcm = (np.clip(x, -1, 1) * 32767).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(x.shape[1])
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def read_wav(path):
    with wave.open(path, 'rb') as w:
        n, ch, sr = w.getnframes(), w.getnchannels(), w.getframerate()
        x = np.frombuffer(w.readframes(n), dtype='<i2').astype(np.float64) / 32768
    return x.reshape(-1, ch), sr


def make_ir(path, rt60=2.1, seed=5):
    """Réponse impulsionnelle de salle douce : pré-délai, premières réflexions,
    queue de bruit décorrélée L/R qui s'assombrit avec le temps."""
    rng = np.random.default_rng(seed)
    n = int(SR * rt60 * 1.1)
    t = np.arange(n) / SR
    out = np.zeros((n, 2))
    pre = int(0.018 * SR)
    env = np.exp(-6.91 * t / rt60)
    for c in range(2):
        noise = rng.standard_normal(n)
        # passe-bas progressif : mélange d'un bruit lissé (sombre) et brut
        k = 24
        dark = np.convolve(noise, np.ones(k) / k, mode='same') * np.sqrt(k)
        mix = np.clip(t / 0.6, 0, 1)
        tail = (noise * (1 - mix) * 0.6 + dark * mix) * env
        tail[:pre] = 0
        out[:, c] = tail
        for d, g in [(0.011, 0.5), (0.023, 0.35), (0.031, 0.3), (0.047, 0.22), (0.061, 0.18)]:
            i = int((d + 0.004 * c) * SR)
            out[i, c] += g * (1 if rng.random() > 0.5 else -1) * 3
    out /= np.sqrt(np.sum(out ** 2) / 2)
    write_wav(path, out * 0.25)


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, **kw)


def render(mid, wav, sf):
    run(['fluidsynth', '-ni', '-q', '-g', '0.45', '-r', str(SR), '-o', 'synth.chorus.active=0',
         '-o', 'synth.reverb.active=1', '-o', 'synth.reverb.room-size=0.35', '-o', 'synth.reverb.level=0.25',
         '-o', 'synth.reverb.damp=0.6', '-o', 'synth.reverb.width=0.8', '-o', 'synth.polyphony=256',
         '-F', wav, sf, mid], stdout=subprocess.DEVNULL)


def master_chain(name):
    """Chaîne ffmpeg commune avant normalisation."""
    wet = 0.22 if name == 'check_sting' else 0.3
    return (f'[0:a]highpass=f=32,asplit=2[d][w];[w][1:a]afir=gtype=none:dry=1:wet=1[r];'
            f'[d][r]amix=inputs=2:weights=1 {wet}:normalize=0,'
            'equalizer=f=250:t=q:w=1.0:g=-1.5,'       # moins de boue
            'equalizer=f=3200:t=q:w=1.2:g=-2.5,'      # adoucit les cuivres/hautbois
            'highshelf=f=9000:g=-3,'                   # aigus feutrés
            'acompressor=threshold=-22dB:ratio=1.8:attack=40:release=400:knee=6:makeup=1')


def master(raw, ir, out_ogg, name, duration):
    lufs = LOUDNESS.get(name, -20)
    chain = master_chain(name)
    # passe 1 : mesure
    p = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', raw, '-i', ir, '-filter_complex',
                        chain + f',loudnorm=I={lufs}:TP=-2:LRA=14:print_format=json', '-f', 'null', '-'],
                       capture_output=True, text=True, check=True)
    js = p.stderr[p.stderr.rfind('{'):p.stderr.rfind('}') + 1]
    m = json.loads(js)
    fo = FADE_OUT.get(name, 4.0)
    fi = 0.02 if name in ('check_sting', 'victory', 'defeat') else 1.5
    ln = (f"loudnorm=I={lufs}:TP=-2:LRA=14:measured_I={m['input_i']}:measured_TP={m['input_tp']}:"
          f"measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}:offset={m['target_offset']}:"
          'linear=true')
    flt = (chain + ',' + ln + f',aresample={SR},afade=t=in:d={fi},'
           f'afade=t=out:st={max(0, duration - fo):.2f}:d={fo},alimiter=limit=0.8:level=false')
    run(['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', '-i', raw, '-i', ir, '-filter_complex', flt,
         '-t', f'{duration:.2f}', '-ar', str(SR), '-ac', '2', '-c:a', 'libvorbis', '-q:a', QUALITY, out_ogg])


def trim_point(raw):
    """Fin utile : dernier instant au-dessus de -60 dBFS (queue de réverbération incluse)."""
    x, sr = read_wav(raw)
    e = np.abs(x).max(axis=1)
    idx = np.nonzero(e > 10 ** (-54 / 20))[0]
    return (idx[-1] / sr if len(idx) else len(x) / sr) + 1.0


def analyse(ogg):
    """Durée, crête, sonie, centroïde spectral (contrôle « pas trop brillant »)."""
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, 'a.wav')
        run(['ffmpeg', '-y', '-loglevel', 'error', '-i', ogg, '-ar', str(SR), wav])
        x, sr = read_wav(wav)
        p = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', wav, '-af',
                            'loudnorm=print_format=json', '-f', 'null', '-'], capture_output=True, text=True)
        js = json.loads(p.stderr[p.stderr.rfind('{'):p.stderr.rfind('}') + 1])
    mono = x.mean(axis=1)
    seg = 1 << 15
    cents, hi = [], []
    for i in range(0, len(mono) - seg, seg):
        s = np.abs(np.fft.rfft(mono[i:i + seg] * np.hanning(seg)))
        f = np.fft.rfftfreq(seg, 1 / sr)
        if s.sum() > 1e-3:
            cents.append(float((f * s).sum() / s.sum()))
            hi.append(float((s[f > 5000] ** 2).sum() / (s ** 2).sum()))
    return dict(duree=round(len(x) / sr, 1), crete_dbfs=round(20 * np.log10(np.abs(x).max() + 1e-9), 1),
                lufs=float(js['input_i']), centroide_hz=round(float(np.median(cents)) if cents else 0),
                energie_5k=round(float(np.mean(hi)) if hi else 0, 4),
                ko=round(os.path.getsize(ogg) / 1024))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    only = None
    for i, a in enumerate(sys.argv):
        if a == '--only' and i + 1 < len(sys.argv):
            only = set(sys.argv[i + 1].split(','))
            args = [x for x in args if x != sys.argv[i + 1]]
    midi_only = '--midi-only' in sys.argv
    out = args[0] if args else os.path.join(ROOT, 'app', 'assets', 'audio', 'music')
    mid_dir = os.path.join(HERE, 'out')
    os.makedirs(out, exist_ok=True)
    os.makedirs(mid_dir, exist_ok=True)
    songs = scores.all_songs()
    built = {}
    for name, fn in songs.items():
        if only and name not in only:
            continue
        s = fn()
        path = os.path.join(mid_dir, name + '.mid')
        s.write(path)
        built[name] = (s, path)
        print(f'MIDI {name}: {len(s.notes)} notes, {s.end / s.meter:.0f} mesures, sections '
              + ' '.join(f'{txt}@{t / s.meter:.0f}' for t, txt in s.markers), flush=True)
    for w in scores.WARN:
        print('frottement:', w, file=sys.stderr)
    if midi_only:
        return
    sf = soundfont()
    report = {}
    with tempfile.TemporaryDirectory() as tmp:
        ir = os.path.join(tmp, 'ir.wav')
        make_ir(ir)
        for name, (s, mid) in built.items():
            raw = os.path.join(tmp, name + '.wav')
            render(mid, raw, sf)
            dur = min(trim_point(raw), MAX_LEN.get(name, 1e9))
            ogg = os.path.join(out, name + '.ogg')
            master(raw, ir, ogg, name, dur)
            report[name] = analyse(ogg)
            print('musique', name, report[name], flush=True)
    total = sum(os.path.getsize(os.path.join(out, f)) for f in os.listdir(out) if f.endswith('.ogg'))
    print(f'total musique : {total / 1e6:.2f} Mo', flush=True)


if __name__ == '__main__':
    main()
