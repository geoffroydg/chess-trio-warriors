"""Voix françaises (Piper TTS) + transformation ffmpeg -> app/assets/audio/voice/*.ogg.

Usage : python -I scripts/audio/gen_voice.py [dossier_sortie]
Prérequis : pip install piper-tts ; ffmpeg ; accès à huggingface.co.
Un fichier qui échoue est ignoré (le jeu fonctionne sans).
"""
import json
import os
import subprocess
import sys
import tempfile
import urllib.request

HF = 'https://huggingface.co/rhasspy/piper-voices/resolve/main'
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
MAX_SECONDS = 2.2

ECHOES = {  # chaîne de filtres « combat épique »
    'light': 'aecho=0.8:0.6:45|90:0.25|0.12',
    'medium': 'aecho=0.8:0.7:60|140:0.3|0.18',
    'heavy': 'aecho=0.8:0.75:80|200|350:0.35|0.25|0.12,lowpass=f=6500',
    'ethereal': 'aecho=0.8:0.85:120|260|420:0.4|0.3|0.2,highpass=f=120',
}


def voice_url(name):
    lang, rest = name.split('-', 1)          # fr_FR, tom-medium
    speaker, quality = rest.rsplit('-', 1)
    return f"{HF}/{lang.split('_')[0]}/{lang}/{speaker}/{quality}/{name}"


def fetch_voice(name, cache):
    os.makedirs(cache, exist_ok=True)
    onnx = os.path.join(cache, name + '.onnx')
    for ext in ('.onnx', '.onnx.json'):
        dest = os.path.join(cache, name + ext)
        if not os.path.exists(dest) or os.path.getsize(dest) == 0:
            print('téléchargement', name + ext, flush=True)
            urllib.request.urlretrieve(voice_url(name) + ext + '?download=true', dest)
    return onnx


def synth(model, text, wav, length_scale):
    subprocess.run([sys.executable, '-m', 'piper', '-m', model, '-f', wav,
                    '--length-scale', str(length_scale)],
                   input=text.encode('utf-8'), check=True, timeout=120)


def transform(src, dst, ch):
    """Hauteur/débit (asetrate+atempo), écho, compression, loudnorm -> ogg mono 22 kHz."""
    pitch, tempo = ch['pitch'], ch['tempo']
    rate = 22050
    af = ','.join([
        'silenceremove=start_periods=1:start_threshold=-45dB',
        f'asetrate={int(rate * pitch)}', f'aresample={rate}',
        f'atempo={max(0.5, min(2.0, tempo / pitch)):.3f}',
        'highpass=f=70',
        'acompressor=threshold=-20dB:ratio=4:attack=5:release=80:makeup=3',
        ECHOES[ch['echo']],
        f'atrim=0:{MAX_SECONDS}', 'afade=t=out:st=%.2f:d=0.25' % (MAX_SECONDS - 0.25),
        'loudnorm=I=-16:TP=-1.5:LRA=7',
    ])
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', src, '-af', af,
                    '-ar', str(rate), '-ac', '1', '-c:a', 'libvorbis', '-q:a', '4', dst],
                   check=True, timeout=120)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'app', 'assets', 'audio', 'voice')
    os.makedirs(out, exist_ok=True)
    cache = os.environ.get('PIPER_VOICES', os.path.join(tempfile.gettempdir(), 'piper-voices'))
    with open(os.path.join(HERE, 'lines.json'), encoding='utf-8') as f:
        cfg = json.load(f)
    chars = cfg['characters']

    jobs = []  # (fichier, personnage, texte)
    for piece, events in cfg['pieces'].items():
        for event, lines in events.items():
            for i, text in enumerate(lines, 1):
                jobs.append((f'{piece}_{event}_{i}.ogg', piece, text))
    for key, text in cfg['announcer'].items():
        jobs.append((f'announcer_{key}.ogg', 'announcer', text))
    for i, k in enumerate(cfg['kiai'], 1):
        jobs.append((f'kiai_{i}.ogg', k['char'], k['text']))

    models = {}
    ok = fail = 0
    for fname, char, text in jobs:
        ch = chars[char]
        try:
            vname = ch['voice']
            if vname not in models:
                models[vname] = fetch_voice(vname, cache)
            with tempfile.TemporaryDirectory() as tmp:
                wav = os.path.join(tmp, 'raw.wav')
                synth(models[vname], text, wav, ch.get('length_scale', 1.0))
                transform(wav, os.path.join(out, fname), ch)
            ok += 1
            print('voix', fname, '-', text, flush=True)
        except Exception as e:  # ne jamais bloquer le pipeline
            fail += 1
            print('ÉCHEC', fname, e, file=sys.stderr, flush=True)
    print(f'voix : {ok} ok, {fail} échecs')


if __name__ == '__main__':
    main()
