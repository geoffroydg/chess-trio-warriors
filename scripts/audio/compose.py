"""Petit atelier de composition algorithmique (théorie, motifs, orchestration -> MIDI).

Utilisé par scores.py / gen_music.py. Dépendance : mido. Tout est déterministe
(graine fixe par morceau). Notation des mélodies : jetons « degré:durée »
séparés par des espaces, barres « | » vérifiées ; degré 0 = tonique du mode,
négatif = sous la tonique, suffixe # / b = altération, « r » = silence.
Exemple : "0:1 4:2 3:.5 4:.5 | 5:1.5 4:.5 2:2".
Accords : chiffrage romain relatif à la tonique (i, IV7, bVII, ii7, Vsus4,
IVadd9, bVImaj7, i6, v7, 5 = quinte à vide, q = quartes), plusieurs par mesure
(partage égal ou « IV:3 V:1 »).
"""
import math
import random
import re
import zlib

import mido

PPQ = 480

SCALES = {
    'ionian': [0, 2, 4, 5, 7, 9, 11],
    'dorian': [0, 2, 3, 5, 7, 9, 10],
    'aeolian': [0, 2, 3, 5, 7, 8, 10],
    'mixolydian': [0, 2, 4, 5, 7, 9, 10],
    'lydian': [0, 2, 4, 6, 7, 9, 11],
}
# Échelles pentatoniques (couleurs japonisantes) appliquées par « aimantation ».
PENTA = {
    'yo': [0, 2, 5, 7, 9],          # min. pentatonique sans tierce : ré-mi-sol-la-si
    'minp': [0, 3, 5, 7, 10],       # pentatonique mineure
    'majp': [0, 2, 4, 7, 9],        # pentatonique majeure
    'in': [0, 1, 5, 7, 8],          # in / miyako-bushi
    'hira': [0, 2, 3, 7, 8],        # hirajoshi
}


# ------------------------------------------------------------------ tonalités
class Key:
    def __init__(self, tonic, mode='ionian', penta=None):
        self.tonic, self.mode, self.scale = tonic, mode, SCALES[mode]
        self.penta = PENTA[penta] if penta else None

    def with_penta(self, penta):
        return Key(self.tonic, self.mode, penta)

    def pitch(self, deg, alt=0):
        o, i = divmod(deg, 7)
        p = self.tonic + 12 * o + self.scale[i] + alt
        if self.penta and not alt:
            p = self.snap(p)
        return p

    def snap(self, p):
        best = None
        for d in (0, -1, 1, -2, 2):
            if (p + d - self.tonic) % 12 in self.penta:
                best = p + d
                break
        return best if best is not None else p

    def in_scale(self, p):
        pcs = self.penta or self.scale
        return (p - self.tonic) % 12 in pcs


# ------------------------------------------------------------------ accords
_ROMAN = {'i': 0, 'ii': 2, 'iii': 4, 'iv': 5, 'v': 7, 'vi': 9, 'vii': 11}
_RX = re.compile(r'^([b#]?)(vii|vi|v|iv|iii|ii|i|VII|VI|V|IV|III|II|I)(.*)$')


class Chord:
    def __init__(self, sym):
        self.sym = sym
        bass = None
        if '/' in sym:
            sym, b = sym.split('/')
            bass = Chord(b).root
        m = _RX.match(sym)
        if not m:
            raise ValueError('accord inconnu: ' + sym)
        acc, num, suf = m.groups()
        self.root = (_ROMAN[num.lower()] + {'b': -1, '#': 1, '': 0}[acc]) % 12
        minor = num.islower()
        ivs = [0, 3, 7] if minor else [0, 4, 7]
        while suf:
            for tok in ('maj7', 'add9', 'sus2', 'sus4', 'm7b5', 'dim', '7', '6', '9', 'o', '+', '5', 'q'):
                if suf.startswith(tok):
                    break
            else:
                raise ValueError('suffixe inconnu: ' + self.sym)
            suf = suf[len(tok):]
            if tok == 'maj7':
                ivs.append(11)
            elif tok == 'add9':
                ivs.append(14)
            elif tok == 'sus2':
                ivs = [0, 2, 7] + ivs[3:]
            elif tok == 'sus4':
                ivs = [0, 5, 7] + ivs[3:]
            elif tok in ('dim', 'o'):
                ivs = [0, 3, 6]
            elif tok == 'm7b5':
                ivs = [0, 3, 6, 10]
            elif tok == '7':
                ivs.append(10)
            elif tok == '6':
                ivs.append(9)
            elif tok == '9':
                ivs += [10, 14]
            elif tok == '+':
                ivs = [0, 4, 8]
            elif tok == '5':
                ivs = [0, 7]
            elif tok == 'q':
                ivs = [0, 5, 10]
        self.ivs = ivs
        self.bass = self.root if bass is None else bass

    def pcs(self, key):
        return {(key.tonic + self.root + i) % 12 for i in self.ivs}

    def core(self, key):
        """Fondamentale, tierce (ou sus), septième si présente."""
        out = [(key.tonic + self.root + self.ivs[0]) % 12]
        if len(self.ivs) > 1:
            out.append((key.tonic + self.root + self.ivs[1]) % 12)
        if len(self.ivs) > 3:
            out.append((key.tonic + self.root + self.ivs[3]) % 12)
        return out


def prog(spec, meter=4):
    """'i | IV7 | ii7 V7' -> [(début_en_temps, durée, Chord)] relatifs."""
    out, t = [], 0.0
    for bar in spec.split('|'):
        toks = bar.split()
        if not toks:
            continue
        if all(':' in x for x in toks):
            items = [(x.split(':')[0], float(x.split(':')[1])) for x in toks]
        else:
            items = [(x, meter / len(toks)) for x in toks]
        if abs(sum(d for _, d in items) - meter) > 1e-6:
            raise ValueError('mesure incomplète: ' + bar)
        for s, d in items:
            out.append((t, d, Chord(s)))
            t += d
    return out


def chord_at(chords, t):
    for b, d, c in chords:
        if b <= t + 1e-6 < b + d:
            return c
    return chords[-1][2]


# ------------------------------------------------------------------ mélodies
class N:
    __slots__ = ('t', 'd', 'deg', 'alt', 'vel')

    def __init__(self, t, d, deg, alt=0, vel=0):
        self.t, self.d, self.deg, self.alt, self.vel = t, d, deg, alt, vel

    def copy(self, **kw):
        n = N(self.t, self.d, self.deg, self.alt, self.vel)
        for k, v in kw.items():
            setattr(n, k, v)
        return n


def theme(s, meter=4):
    """Analyse la notation ; renvoie une liste de N (deg None = silence)."""
    out, t = [], 0.0
    for bi, bar in enumerate(s.split('|')):
        start = t
        for tok in bar.split():
            g, d = tok.split(':')
            d = float(d)
            if g == 'r':
                out.append(N(t, d, None))
            else:
                alt = g.count('#') - g.count('b')
                out.append(N(t, d, int(g.rstrip('#b')), alt))
            t += d
        if abs(t - start - meter) > 1e-6:
            raise ValueError(f'mesure {bi + 1} = {t - start} temps: {bar}')
    return out


def length(notes):
    return max(n.t + n.d for n in notes) if notes else 0


def shift(notes, k):
    return [n.copy(deg=None if n.deg is None else n.deg + k) for n in notes]


def augment(notes, f=2.0):
    return [n.copy(t=n.t * f, d=n.d * f) for n in notes]


def window(notes, t0, t1):
    """Fragment [t0, t1[ ramené à 0."""
    return [n.copy(t=n.t - t0) for n in notes if t0 - 1e-6 <= n.t < t1 - 1e-6]


def concat(*parts):
    out, t = [], 0.0
    for p in parts:
        out += [n.copy(t=n.t + t) for n in p]
        t += length(p)
    return out


def replace_end(notes, alt, meter=4):
    """Remplace les dernières mesures par une autre terminaison (cadence)."""
    alt_n = theme(alt, meter)
    cut = length(notes) - length(alt_n)
    return [n for n in notes if n.t < cut - 1e-6] + [n.copy(t=n.t + cut) for n in alt_n]


def invert(notes, axis):
    return [n.copy(deg=None if n.deg is None else 2 * axis - n.deg) for n in notes]


def ornament(notes, rng, p=0.35, meter=4):
    """Variation : notes de passage et broderies sur les valeurs longues."""
    out = []
    for i, n in enumerate(notes):
        nxt = notes[i + 1] if i + 1 < len(notes) else None
        if n.deg is not None and n.d >= 1.5 and rng.random() < p:
            if nxt is not None and nxt.deg is not None and abs(nxt.deg - n.deg) >= 2 and rng.random() < 0.6:
                # note de passage vers la suivante
                step = 1 if nxt.deg > n.deg else -1
                out += [n.copy(d=n.d - 0.5), n.copy(t=n.t + n.d - 0.5, d=0.5, deg=nxt.deg - step, alt=0)]
            else:
                # broderie supérieure puis retour
                out += [n.copy(d=n.d - 1), n.copy(t=n.t + n.d - 1, d=0.5, deg=n.deg + 1, alt=0),
                        n.copy(t=n.t + n.d - 0.5, d=0.5)]
        elif n.deg is not None and n.d == 1 and nxt is not None and nxt.deg is not None \
                and abs(nxt.deg - n.deg) == 2 and rng.random() < p * 0.7:
            mid = (n.deg + nxt.deg) // 2
            out += [n.copy(d=0.5), n.copy(t=n.t + 0.5, d=0.5, deg=mid, alt=0)]
        else:
            out.append(n)
    return out


def rhythm_vary(notes, rng, p=0.3):
    """Paires égales (1+1) -> pointées (1.5+0.5) ; garde les temps forts."""
    out, i = [], 0
    while i < len(notes):
        a = notes[i]
        b = notes[i + 1] if i + 1 < len(notes) else None
        if b is not None and a.deg is not None and b.deg is not None and a.d == b.d == 1 \
                and a.t % 2 == 0 and rng.random() < p:
            out += [a.copy(d=1.5), b.copy(t=b.t + 0.5, d=0.5)]
            i += 2
        else:
            out.append(a)
            i += 1
    return out


# ------------------------------------------------------------------ génération guidée
def gen_line(rng, chords, key, bars, meter=4, motifs=None, lo=-2, hi=9, form='aaba',
             start=None, end=0, arch=True):
    """Mélodie à partir d'une grille : rythme par motifs répétés (forme aaba...),
    temps forts sur notes de l'accord, passages conjoints, arche de contour,
    dernière note longue sur [end]."""
    motifs = motifs or ['1 1 2', '1.5 .5 1 1', '2 1 1', '1 .5 .5 2', '3 1']
    pick = {}
    labels = (form * 8)[:bars]
    notes = []
    prev = start if start is not None else (lo + hi) // 2
    t = 0.0
    bar_cells = {}
    for b in range(bars):
        lab = labels[b]
        if lab not in pick:
            pick[lab] = [float(x) for x in rng.choice(motifs).split()]
        durs = pick[lab]
        last_bar = b == bars - 1
        if last_bar:
            durs = [float(meter)] if (b % 4 == 3 or bars < 4) else durs
        if b % 4 == 3 and not last_bar:
            durs = [2.0, 1.0, 1.0] if rng.random() < 0.5 else [3.0, 1.0]
        cell = []
        tt = t
        for k, d in enumerate(durs):
            c = chord_at(chords, tt)
            pcs = c.pcs(key)
            x = tt / max(1, bars * meter)
            target = lo + (hi - lo) * (math.sin(math.pi * x) if arch else 0.5 + 0.5 * math.sin(2 * math.pi * x))
            strong = (tt % 2 == 0) or d >= 1.5
            if last_bar and k == len(durs) - 1:
                cand = [end + 7 * o for o in (-1, 0, 1) if lo - 1 <= end + 7 * o <= hi + 1] or [end]
                deg = min(cand, key=lambda g: abs(g - prev))
            elif lab in bar_cells and b % 4 != 3 and k < len(bar_cells[lab]):
                # répétition / séquence du motif : mêmes intervalles
                ref = bar_cells[lab]
                base = ref[0]
                if k == 0:
                    cands = [g for g in range(lo, hi + 1) if key.pitch(g) % 12 in pcs]
                    deg = min(cands, key=lambda g: (abs(g - (prev + (1 if target > prev else -1))), g)) if cands else prev
                    seq_off = deg - base
                    bar_cells['_off'] = seq_off
                else:
                    deg = ref[k] + bar_cells.get('_off', 0)
                    if strong and key.pitch(deg) % 12 not in pcs:
                        deg = min((g for g in range(deg - 2, deg + 3) if key.pitch(g) % 12 in pcs),
                                  key=lambda g: abs(g - deg), default=deg)
            elif strong:
                cands = [g for g in range(lo, hi + 1) if key.pitch(g) % 12 in pcs]
                drift = 1 if target > prev + 0.5 else (-1 if target < prev - 0.5 else 0)
                deg = min(cands, key=lambda g: abs(g - (prev + 2 * drift)) + 0.6 * (g == prev)
                          + rng.random() * 0.8) if cands else prev
            else:
                step = 1 if target > prev else -1
                if rng.random() < 0.25:
                    step = -step
                deg = prev + step
            while deg > hi + 1:
                deg -= 7
            while deg < lo - 1:
                deg += 7
            cell.append(deg)
            notes.append(N(tt, d, deg))
            prev = deg
            tt += d
        if lab not in bar_cells:
            bar_cells[lab] = cell
        t += meter
    return notes


def check(notes, chords, key, label='', strong_only=True):
    """Signale les notes fortes à un demi-ton d'une note de l'accord (frottements)."""
    bad = []
    for n in notes:
        if n.deg is None:
            continue
        if strong_only and not ((n.t % 2 == 0 and n.d >= 0.75) or n.d >= 2):
            continue
        p = key.pitch(n.deg, n.alt) % 12
        c = chord_at(chords, n.t)
        pcs = c.pcs(key)
        if p in pcs:
            continue
        if any((p - q) % 12 in (1, 11) for q in pcs):
            bad.append(f'{label} mesure {int(n.t // 4) + 1} temps {n.t % 4 + 1:g}: deg {n.deg} sur {c.sym}')
    return bad


# ------------------------------------------------------------------ morceau / pistes
class Part:
    def __init__(self, name, program, ch, vol, pan, rev, cho, human, legato):
        self.name, self.program, self.ch = name, program, ch
        self.vol, self.pan, self.rev, self.cho = vol, pan, rev, cho
        self.human, self.legato = human, legato


class Song:
    def __init__(self, name, bpm, meter=4, seed=1):
        self.name, self.bpm, self.meter = name, bpm, meter
        self.rng = random.Random(seed)
        self.parts = {}
        self.notes = []     # (part, t, d, pitch, vel)
        self.ccs = []       # (part, t, cc, val)
        self.tempos = [(0.0, bpm)]
        self.end = 0.0
        self.markers = []

    # -- configuration
    def part(self, name, program, vol=100, pan=64, rev=40, cho=0, human=10, legato=1.0):
        used = {p.ch for p in self.parts.values()}
        ch = next(c for c in range(16) if c != 9 and c not in used)
        self.parts[name] = Part(name, program, ch, vol, pan, rev, cho, human, legato)
        return name

    def bar(self, b):
        return b * self.meter

    # -- évènements
    def note(self, part, t, d, pitch, vel):
        if not (20 <= pitch <= 108) or d <= 0:
            return
        self.notes.append((part, t, d, int(pitch), max(1, min(127, int(vel)))))
        self.end = max(self.end, t + d)

    def cc(self, part, t, ctrl, val):
        self.ccs.append((part, t, ctrl, max(0, min(127, int(round(val))))))

    def ramp(self, part, t0, t1, ctrl, v0, v1, step=0.25, curve=1.0):
        n = max(1, int((t1 - t0) / step))
        for i in range(n + 1):
            x = (i / n) ** curve
            self.cc(part, t0 + (t1 - t0) * i / n, ctrl, v0 + (v1 - v0) * x)

    def tempo(self, t, bpm):
        self.tempos.append((t, bpm))

    def rit(self, t0, t1, bpm1, bpm0=None):
        bpm0 = bpm0 or self.bpm
        n = max(1, int((t1 - t0) / 0.5))
        for i in range(n + 1):
            x = i / n
            self.tempo(t0 + (t1 - t0) * x, bpm0 + (bpm1 - bpm0) * x * x)

    def mark(self, t, text):
        self.markers.append((t, text))

    # -- écriture MIDI (humanisation : micro-décalages et vélocités)
    def write(self, path, tail=6.0):
        rng = random.Random(zlib.crc32(self.name.encode()))
        mid = mido.MidiFile(type=1, ticks_per_beat=PPQ)
        cond = mido.MidiTrack()
        mid.tracks.append(cond)
        ev = [(0, mido.MetaMessage('track_name', name=self.name, time=0)),
              (0, mido.MetaMessage('time_signature', numerator=self.meter, denominator=4, time=0))]
        for t, bpm in sorted(self.tempos, key=lambda x: x[0]):
            ev.append((int(t * PPQ), mido.MetaMessage('set_tempo', tempo=int(60e6 / bpm), time=0)))
        for t, text in self.markers:
            ev.append((int(t * PPQ), mido.MetaMessage('marker', text=text, time=0)))
        end_tick = int((self.end + tail) * PPQ)
        ev.append((end_tick, mido.MetaMessage('text', text='fin', time=0)))
        _flush(cond, ev)
        ms_to_ticks = self.bpm * PPQ / 60000.0
        for p in self.parts.values():
            tr = mido.MidiTrack()
            mid.tracks.append(tr)
            ev = [(0, mido.MetaMessage('track_name', name=p.name, time=0)),
                  (0, mido.Message('program_change', channel=p.ch, program=p.program, time=0)),
                  (0, mido.Message('control_change', channel=p.ch, control=7, value=p.vol, time=0)),
                  (0, mido.Message('control_change', channel=p.ch, control=10, value=p.pan, time=0)),
                  (0, mido.Message('control_change', channel=p.ch, control=91, value=p.rev, time=0)),
                  (0, mido.Message('control_change', channel=p.ch, control=93, value=p.cho, time=0)),
                  (0, mido.Message('control_change', channel=p.ch, control=11, value=100, time=0))]
            for part, t, c, v in self.ccs:
                if part == p.name:
                    ev.append((max(1, int(t * PPQ)), mido.Message('control_change', channel=p.ch,
                                                                  control=c, value=v, time=0)))
            mine = sorted((n for n in self.notes if n[0] == p.name), key=lambda n: (n[3], n[1]))
            # mêmes hauteurs qui se chevauchent : on raccourcit la précédente
            spans = []
            for i, (_, t, d, pitch, vel) in enumerate(mine):
                on = t * PPQ + rng.gauss(0, p.human * ms_to_ticks)
                if t == 0:
                    on = abs(on) + 2
                off = (t + d * p.legato) * PPQ
                if i + 1 < len(mine) and mine[i + 1][3] == pitch:
                    off = min(off, mine[i + 1][1] * PPQ - 6)
                v = vel + rng.gauss(0, 3.5)
                if off - on < 20:
                    off = on + 20
                spans.append((int(max(0, on)), int(off), pitch, max(1, min(127, int(v)))))
            for on, off, pitch, v in spans:
                ev.append((on, mido.Message('note_on', channel=p.ch, note=pitch, velocity=v, time=0)))
                ev.append((off, mido.Message('note_off', channel=p.ch, note=pitch, velocity=0, time=0)))
            _flush(tr, ev)
        mid.save(path)
        return mid


def _flush(track, ev):
    def order(e):
        tick, m = e
        pri = 0 if m.type in ('track_name', 'program_change', 'time_signature') else \
            (1 if m.type == 'note_off' else (2 if m.type == 'control_change' else 3))
        return tick, pri
    last = 0
    for tick, m in sorted(ev, key=order):
        track.append(m.copy(time=tick - last))
        last = tick


# ------------------------------------------------------------------ couches d'orchestration
def voice_lead(chord, key, n, lo, hi, prev):
    pcs = sorted(chord.pcs(key))
    cands = [p for p in range(lo, hi + 1) if p % 12 in pcs]
    if not cands:
        return []
    if not prev:
        root = key.tonic + chord.root
        base = min((p for p in cands if p % 12 == root % 12), default=cands[0])
        if base > (lo + hi) // 2:
            base = max(lo, base - 12)
        tones = [base + i for i in chord.ivs]
        out = sorted({min(cands, key=lambda c: abs(c - t)) for t in tones})
        while len(out) < n:
            nxt = [c for c in cands if c > out[-1]]
            out.append(nxt[0] if nxt else out[0])
        return sorted(out[:n])
    out = []
    for v in prev[:n]:
        choices = sorted(cands, key=lambda c: (abs(c - v), c))
        pick_ = next((c for c in choices if c not in out), choices[0])
        out.append(pick_)
    # couvrir fondamentale et tierce (ou sus)
    for pc in chord.core(key)[:2]:
        if pc not in {x % 12 for x in out}:
            counts = {}
            for x in out:
                counts[x % 12] = counts.get(x % 12, 0) + 1
            dup = [i for i, x in enumerate(out) if counts[x % 12] > 1]
            i = dup[0] if dup else len(out) - 1
            out[i] = min((c for c in cands if c % 12 == pc), key=lambda c: abs(c - out[i]))
    return sorted(out)


def pad(song, part, t0, chords, key, n=4, lo=50, hi=76, vel=50, swell=0, tie=True):
    """Accords tenus avec conduite des voix ; notes communes liées."""
    prev, held = None, {}
    for b, d, c in chords:
        v = voice_lead(c, key, n, lo, hi, prev)
        new_held = {}
        for p in v:
            if tie and p in held:
                new_held[p] = held[p]
            else:
                new_held[p] = (t0 + b, vel)
        for p, (s, vv) in held.items():
            if p not in new_held:
                song.note(part, s, t0 + b - s + 0.05, p, vv)
        held = new_held
        prev = v
        if swell:
            song.ramp(part, t0 + b, t0 + b + d * 0.6, 11, 100 - swell, 100)
    end = t0 + chords[-1][0] + chords[-1][1]
    for p, (s, vv) in held.items():
        song.note(part, s, end - s + 0.05, p, vv)


def bass(song, part, t0, chords, key, lo=36, hi=52, vel=55, style='root', pedal=None):
    prev = None
    for b, d, c in chords:
        root = (key.tonic + (c.bass if pedal is None else pedal)) % 12
        cands = [p for p in range(lo, hi + 1) if p % 12 == root]
        p = min(cands, key=lambda x: abs(x - (prev or (lo + hi) // 2)))
        prev = p
        if style == 'root':
            song.note(part, t0 + b, d, p, vel)
        elif style == 'root5':
            song.note(part, t0 + b, d / 2, p, vel)
            five = p + 7 if p + 7 <= hi + 5 else p - 5
            song.note(part, t0 + b + d / 2, d / 2, five, vel - 8)
        elif style == 'pizz':
            five = p + 7
            pat = [(0, p, 0), (1.5, five, -10), (2, p + 12 if p + 12 <= hi + 12 else p, -6), (3, five, -12)]
            for off, q, dv in pat:
                if off < d:
                    song.note(part, t0 + b + off, 0.5, q, vel + dv)
        elif style == 'pulse':
            k = 0.0
            while k < d - 1e-6:
                song.note(part, t0 + b + k, 0.9, p, vel - (0 if k % 2 == 0 else 10))
                k += 1


def arp(song, part, t0, chords, key, pattern='0 1 2 3 4 3 2 1', sub=0.5, lo=55, vel=45,
        pedal=False, ring=1.5, accent=8, skip=0.0, rng=None):
    """Arpèges sur échelle des notes de l'accord (indices 0 = basse)."""
    pat = [int(x) if x != '.' else None for x in pattern.split()]
    rng = rng or song.rng
    k = 0
    for b, d, c in chords:
        pcs = c.pcs(key)
        root = key.tonic + c.root
        base = min(p for p in range(lo, lo + 12) if p % 12 == root % 12)
        ladder = [p for p in range(base, base + 36) if p % 12 in pcs]
        if pedal:
            song.cc(part, t0 + b + 0.02, 64, 0)
            song.cc(part, t0 + b + 0.08, 64, 100)
        tt = 0.0
        while tt < d - 1e-6:
            idx = pat[k % len(pat)]
            k += 1
            if idx is not None and not (skip and rng.random() < skip):
                p = ladder[min(idx, len(ladder) - 1)]
                v = vel + (accent if (b + tt) % song.meter == 0 else 0) - 3 * (idx > 3)
                song.note(part, t0 + b + tt, min(ring * sub * 2, d - tt) if not pedal else sub * ring, p, v)
            tt += sub
    if pedal:
        song.cc(part, t0 + chords[-1][0] + chords[-1][1], 64, 0)


def koto(song, part, t0, chords, key, figure='0 2 1 4', sub=0.5, lo=60, vel=50, grace=0.3, rng=None):
    """Koto : figures pentatoniques (degrés de [key], qui doit porter une penta),
    posées sur la fondamentale de l'accord ; petites appoggiatures (oshide)."""
    rng = rng or song.rng
    fig = [None if x == '.' else int(x) for x in figure.split()]
    pen = key.penta or [0, 2, 4, 7, 9]
    k = 0
    for b, d, c in chords:
        rootp = key.tonic + c.root
        while rootp < lo:
            rootp += 12
        while rootp >= lo + 12:
            rootp -= 12
        # degrés pentatoniques autour de la fondamentale
        ladder = [p for p in range(rootp - 12, rootp + 30) if (p - key.tonic) % 12 in pen]
        i0 = min(range(len(ladder)), key=lambda i: abs(ladder[i] - rootp))
        tt = 0.0
        while tt < d - 1e-6:
            f = fig[k % len(fig)]
            k += 1
            if f is not None:
                p = ladder[max(0, min(len(ladder) - 1, i0 + f))]
                v = vel + (6 if (b + tt) % song.meter == 0 else 0)
                if rng.random() < grace and tt + sub <= d:
                    up = ladder[max(0, min(len(ladder) - 1, i0 + f + 1))]
                    song.note(part, t0 + b + tt - 0.08, 0.1, up, v - 18)
                song.note(part, t0 + b + tt, sub * 2.5, p, v)
            tt += sub


def melody(song, part, t0, notes, key, octave=0, vel=70, dyn=None, breath=False, swell=0):
    """Mélodie avec phrasé : vélocité suivant le contour et le temps fort,
    souffle (CC11) pour vents/cordes."""
    degs = [n.deg for n in notes if n.deg is not None]
    if not degs:
        return
    mean = sum(degs) / len(degs)
    total = length(notes)
    for n in notes:
        if n.deg is None:
            continue
        p = key.pitch(n.deg, n.alt) + 12 * octave
        x = n.t / max(total, 1)
        v = vel + 2.0 * (n.deg - mean) + (5 if n.t % song.meter == 0 else 0) + (3 if n.d >= 2 else 0)
        if dyn:
            v += dyn[0] + (dyn[1] - dyn[0]) * x
        song.note(part, t0 + n.t, n.d, p, v)
        if swell and n.d >= 1.5:
            song.ramp(part, t0 + n.t, t0 + n.t + n.d * 0.7, 11, 100 - swell, 100, step=0.25)
            song.cc(part, t0 + n.t + n.d - 0.05, 11, 100)


def counter(song, part, t0, chords, key, lo, hi, rhythm=2.0, vel=50, against=None, start=None):
    """Contre-chant lent : notes caractéristiques (tierces, septièmes), mouvement conjoint,
    évite l'unisson avec la mélodie [against] (liste de N, même tonalité)."""
    prev = start or (lo + hi) // 2
    total = chords[-1][0] + chords[-1][1]
    t = 0.0
    while t < total - 1e-6:
        c = chord_at(chords, t)
        core = c.core(key)
        pcs = c.pcs(key)
        cands = [p for p in range(lo, hi + 1) if p % 12 in pcs]
        mel = set()
        if against:
            for n in against:
                if n.deg is not None and n.t <= t < n.t + n.d:
                    mel.add(key.pitch(n.deg, n.alt) % 12)

        def score(p):
            s = abs(p - prev)
            s += 0 if p % 12 in core[1:] else 2.5
            s += 4 if p % 12 in mel else 0
            s += 1.5 if p == prev else 0
            return s
        p = min(cands, key=score) if cands else prev
        d = min(rhythm, total - t)
        song.note(part, t0 + t, d, p, vel)
        prev = p
        t += d


def hits(song, part, t0, beats, pitch, vel):
    for b, dv in beats:
        song.note(part, t0 + b, 1.5, pitch, vel + dv)


def roll(song, part, t0, d, pitch, v0, v1, rate=0.125):
    n = int(d / rate)
    for i in range(n):
        x = i / max(1, n - 1)
        song.note(part, t0 + i * rate, rate * 1.5, pitch, v0 + (v1 - v0) * x * x)
