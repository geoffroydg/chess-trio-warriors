"""Partitions de Chess Trio Warriors (100 % originales, composées pour le jeu).

Leitmotiv commun LEIT (8 mesures) : quinte ascendante « héroïque », retombée
sur la tierce, réponse vers l'octave et cadence. Chaque morceau de partie a son
propre thème (A) et cite le leitmotiv dans sa section C (autre mode, autre
timbre, canon pentatonique sur bourdon).
Forme des morceaux de partie : intro - A (thème + variation) - transition -
B (nouvelle tonalité, mélodie développée par motifs) - A' - C (leitmotiv puis
canon pentatonique) - transition - A'' (tutti doux, parfois modulé) - coda.
"""
import random

from compose import (Key, Song, augment, arp, bass, check, concat, counter, gen_line, hits,
                     koto, length, melody, ornament, pad, prog, replace_end, rhythm_vary, roll,
                     shift, theme, window)

# --------------------------------------------------------------- GM (0-based)
PIANO, CELESTA, TUBBELL = 0, 8, 14
CELLO, CBASS, TREM, PIZZ, HARP, TIMP = 42, 43, 44, 45, 46, 47
STR, SLOWSTR, CHOIR = 48, 49, 52
HORN, OBOE, CLAR, FLUTE, SHAKU = 60, 68, 71, 73, 77
WARMPAD, KOTO, TAIKO = 89, 107, 116

LEIT = ('0:1 4:2 3:.5 4:.5 | 5:1.5 4:.5 2:2 | 1:1 2:1 4:1 3:1 | 2:3 r:1 | '
        '0:1 4:2 3:.5 4:.5 | 7:1.5 6:.5 4:2 | 5:1 4:1 3:1 1:1 | 0:4')
LEIT_CH = {
    'dorian': 'i | IV7 | v7 | bIII | i | IVadd9 | ii7 V7 | i',
    'aeolian': 'i | bVI | v7 | bIII | i | ivadd9 | bVI V7 | i',
    'ionian': 'I | vi | V7 | iii | I | IVadd9 | ii7 V7 | I',
}

WARN = []


def chk(notes, chords, key, label):
    WARN.extend(check(notes, chords, key, label))


# --------------------------------------------------------------- morceaux de partie
GAMES = {
    # Aube sur la montagne : shakuhachi, koto, cordes lentes ; ré dorien.
    'game_1': dict(
        seed=101, bpm=80, key=Key(62, 'dorian'), title='Aube sur la montagne',
        theme='4:1.5 3:.5 4:1 7:1 | 6:2 5:1 4:1 | 2:1.5 3:.5 4:1 2:1 | 1:3 r:1 | '
              '4:1.5 3:.5 4:1 7:1 | 8:2 9:1 7:1 | 6:1 5:1 4:1 3:1 | 4:3 r:1',
        chords='i | v7:2 IV:2 | bIII | ii7 | i | bVIIadd9:2 IV7:2 | v7 | IVadd9',
        alt='6:1 4:1 3:1 1:1 | 0:3 r:1', alt_chords='v7 | i',
        lead=(SHAKU, 0, 92), lead2=(FLUTE, 0, 84), counter=(CELLO, 70), padp=(SLOWSTR, 78),
        texture='koto', texture2='harp', bassp=(CBASS, 'root'), perc='taiko_soft',
        penta='yo', intro='i | bVIIadd9 | IVadd9 | i',
        b_key=Key(65, 'ionian'), b_prog='I | iii | IV | Iadd9 | vi | IVmaj7 | ii7 | V7',
        trans='IV | V7', c_mode='dorian', c_lead=(HORN, -1, 80), lift=0,
        outro='IVadd9 | bVIIadd9 | i | i'),
    # Méditation du maître : piano, koto, shakuhachi, cloche ; la éolien / in.
    'game_2': dict(
        seed=202, bpm=74, key=Key(57, 'aeolian'), title='Méditation du maître',
        theme='0:2 2:1 4:1 | 3:3 2:1 | 1:2 2:1 -1:1 | 0:4 | 4:2 5:1 4:1 | 7:3 6:1 | '
              '5:1.5 4:.5 3:1 1:1 | 2:4',
        chords='i | iv | v7:2 bIII:2 | i | bIII:2 iv:2 | bVI | iv6 | bIII',
        alt='5:1.5 4:.5 3:1 1:1 | 0:4', alt_chords='iv:2 v7:2 | i',
        lead=(PIANO, 1, 74), lead2=(SHAKU, 1, 82), counter=(CELLO, 62), padp=(SLOWSTR, 66),
        texture='piano', texture2='koto', bassp=(CBASS, 'root'), perc='bell',
        penta='in', intro='i | bVI | iv | i',
        b_key=Key(57, 'aeolian', None), b_prog='bVI | bIII | iv | i | bVI | bVII | iv | v7',
        trans='bVI | v7', c_mode='aeolian', c_lead=(CELLO, -1, 76), lift=0,
        outro='iv | bVI | i | i'),
    # Entraînement : pizzicati, koto en croches, taiko léger, flûte ; sol dorien.
    'game_3': dict(
        seed=303, bpm=92, key=Key(55, 'dorian'), title='Entraînement',
        theme='0:.5 2:.5 4:1 3:.5 2:.5 1:1 | 2:.5 4:.5 5:1 4:2 | 3:.5 2:.5 1:1 0:.5 1:.5 2:1 | '
              '1:2 -1:1 -3:1 | 0:.5 2:.5 4:1 3:.5 2:.5 1:1 | 2:.5 4:.5 7:1 6:2 | '
              '5:.5 4:.5 3:1 4:.5 3:.5 2:1 | 1:4',
        chords='i | i6 | bVII | v7 | i | bIII | IV7 | v',
        alt='5:.5 4:.5 3:1 2:.5 1:.5 -1:1 | 0:4', alt_chords='IV7 | i',
        lead=(FLUTE, 1, 82), lead2=(SHAKU, 1, 84), counter=(HORN, 66), padp=(STR, 64),
        texture='koto_run', texture2='harp', bassp=(PIZZ, 'pizz'), perc='taiko_drill',
        penta='minp', intro='i | bVII | i | v7',
        b_key=Key(58, 'ionian'), b_prog='I | IV | vi | V | I | IV | ii7 | V7',
        trans='IV7 | v7', c_mode='dorian', c_lead=(HORN, 0, 78), lift=0,
        outro='IV7 | bVIIadd9 | i | i'),
    # Ciel du tournoi : cors, cordes, harpe, timbales ; fa majeur, montée en sol.
    'game_4': dict(
        seed=404, bpm=88, key=Key(65, 'ionian'), title='Ciel du tournoi',
        theme='0:1.5 4:.5 4:2 | 5:1 7:1 6:1 5:1 | 4:3 2:1 | 3:1 2:1 1:2 | '
              '0:1.5 4:.5 4:2 | 5:1 7:1 9:2 | 8:1 7:1 6:1 5:1 | 4:4',
        chords='I | vi:2 iii:2 | I | ii7 | I | IVmaj7 | ii7:2 iii:2 | V',
        alt='6:1 5:1 4:1 1:1 | 0:4', alt_chords='V7 | I',
        lead=(HORN, -1, 84), lead2=(STR, 0, 76), counter=(CELLO, 66), padp=(STR, 70),
        texture='harp', texture2='piano', bassp=(CBASS, 'root5'), perc='timpani',
        penta='majp', intro='Iadd9 | IVmaj7 | vi | V',
        b_key=Key(62, 'aeolian'), b_prog='i | bVI | bIII | bVII | i | iv | bVI | V7',
        trans='IV | V7', c_mode='ionian', c_lead=(FLUTE, 0, 80), lift=2,
        outro='IVadd9 | V | I | I'),
    # Rivalité : violoncelle, hautbois, cœur de taiko, trémolos ; mi éolien.
    'game_5': dict(
        seed=505, bpm=84, key=Key(52, 'aeolian'), title='Rivalité',
        theme='0:1 -1:.5 0:.5 2:2 | 4:1 3:.5 2:.5 3:2 | 2:1 1:.5 0:.5 -1:1 -3:1 | -2:4 | '
              '0:1 -1:.5 0:.5 2:2 | 4:1 5:.5 4:.5 7:2 | 6:1 5:1 4:1 3:1 | 4:4',
        chords='i | bIIIadd9 | i7 | bVI | iv7 | i | v7 | V',
        alt='6:1 5:1 4:1 1:1 | 0:4', alt_chords='v7 | i',
        lead=(CELLO, 1, 84), lead2=(OBOE, 1, 76), counter=(HORN, 62), padp=(STR, 66),
        texture='harp', texture2='koto', bassp=(CBASS, 'pulse'), perc='heartbeat',
        penta='minp', intro='i | bVI | iv | v7',
        b_key=Key(55, 'ionian'), b_prog='IV | V | iii | vi | IV | I | ii7 | V7',
        trans='bVI | V', c_mode='aeolian', c_lead=(OBOE, 1, 76), lift=0,
        outro='bVI | iv | i | i'),
    # Sérénité avant le combat : piano, flûte, cordes, harpe ; si bémol majeur.
    'game_6': dict(
        seed=606, bpm=76, key=Key(58, 'ionian'), title='Sérénité avant le combat',
        theme='2:1 1:1 0:1 4:1 | 4:2 3:1 2:1 | 1:1 2:1 3:1 5:1 | 4:4 | '
              '2:1 1:1 0:1 4:1 | 7:2 6:1 5:1 | 4:1 3:1 2:1 0:1 | 1:4',
        chords='I | iii:2 ii7:2 | IV | V | vi7 | IV:2 V7:2 | ii7:2 I:2 | V',
        alt='4:1 3:1 1:1 2:1 | 0:4', alt_chords='V7 | I',
        lead=(FLUTE, 1, 80), lead2=(PIANO, 1, 74), counter=(CELLO, 62), padp=(SLOWSTR, 70),
        texture='piano', texture2='harp', bassp=(CBASS, 'root'), perc='none',
        penta='majp', intro='Iadd9 | IVmaj7 | Iadd9 | IVmaj7',
        b_key=Key(55, 'aeolian'), b_prog='i | bVI | bIII | bVII | iv | bVI | iv | V',
        trans='IV | V7', c_mode='ionian', c_lead=(PIANO, 1, 70), lift=0,
        outro='IVmaj7 | ii7 | Iadd9 | I'),
}


class Ctx:
    """Orchestre d'un morceau : parties MIDI + curseur de mesures."""

    def __init__(self, song):
        self.s = song
        self.t = 0.0

    def beats(self, bars):
        return bars * self.s.meter


def texture_layer(c, kind, t, chords, key, vel, penta, rng, density=1.0):
    s = c.s
    if kind == 'koto':
        koto(s, 'koto', t, chords, key.with_penta(penta), figure='0 2 4 2 5 4 2 .', sub=0.5,
             lo=62, vel=vel, grace=0.25, rng=rng)
    elif kind == 'koto_run':
        koto(s, 'koto', t, chords, key.with_penta(penta), figure='0 1 2 4 3 2 1 2', sub=0.5,
             lo=62, vel=vel - 4, grace=0.15, rng=rng)
    elif kind == 'harp':
        arp(s, 'harp', t, chords, key, pattern='0 2 4 5 6 5 4 2', sub=0.5, lo=50, vel=vel,
            pedal=False, ring=2.5, skip=0.1 * (1 - density), rng=rng)
    elif kind == 'piano':
        arp(s, 'piano', t, chords, key, pattern='0 3 4 . 5 4 3 .', sub=0.5, lo=48, vel=vel - 4,
            pedal=True, ring=2.0, skip=0.15 * (1 - density), rng=rng)


def perc_layer(c, kind, t, bars, vel, final=False):
    s, m = c.s, c.s.meter
    for b in range(bars):
        tb = t + b * m
        if kind == 'taiko_soft' and b % 4 == 0:
            hits(s, 'taiko', tb, [(0, 0), (2.5, -14)], 41, vel)
        elif kind == 'taiko_drill':
            hits(s, 'taiko', tb, [(0, 0), (1.5, -16), (2, -8), (3.5, -18)], 43, vel)
        elif kind == 'heartbeat':
            hits(s, 'taiko', tb, [(0, 0), (0.5, -14)], 38, vel)
        elif kind == 'timpani' and b % 2 == 0:
            hits(s, 'timp', tb, [(0, 0)], c.timp[0] if b % 4 == 0 else c.timp[1], vel)
        elif kind == 'bell' and b % 8 == 0:
            s.note('bell', tb, 6, 69, vel)


def timp_pitch(key, iv=0):
    pc = (key.tonic + iv) % 12
    return next(p for p in range(40, 52) if p % 12 == pc)


def build_game(name):
    cfg = GAMES[name]
    rng = random.Random(cfg['seed'])
    s = Song(name, cfg['bpm'], seed=cfg['seed'])
    c = Ctx(s)
    key = cfg['key']
    c.timp = (timp_pitch(key), timp_pitch(key, 7))
    li, lo_, lv = cfg['lead']
    l2i, l2o, l2v = cfg['lead2']
    s.part('lead', li, vol=86, pan=60, rev=52, human=12, legato=1.02)
    s.part('lead2', l2i, vol=84, pan=74, rev=56, human=12, legato=1.02)
    s.part('counter', cfg['counter'][0], vol=84, pan=46, rev=50, human=10)
    s.part('pad', cfg['padp'][0], vol=min(110, cfg['padp'][1] + 18), pan=64, rev=60, human=6)
    s.part('bass', cfg['bassp'][0], vol=72, pan=58, rev=40, human=8)
    s.part('koto', KOTO, vol=100, pan=84, rev=50, human=9)
    s.part('harp', HARP, vol=100, pan=40, rev=55, human=9)
    s.part('piano', PIANO, vol=90, pan=70, rev=52, human=9)
    s.part('cl', cfg['c_lead'][0], vol=88, pan=54, rev=55, human=12, legato=1.02)
    s.part('horn', HORN, vol=72, pan=50, rev=60, human=10)
    s.part('taiko', TAIKO, vol=52, pan=64, rev=45, human=6)
    s.part('timp', TIMP, vol=70, pan=64, rev=50, human=6)
    s.part('bell', TUBBELL, vol=46, pan=80, rev=70, human=4)
    s.part('drone', WARMPAD, vol=70, pan=64, rev=60, human=4)
    m = s.meter
    T = theme(cfg['theme'])
    CH = prog(cfg['chords'])
    TA = replace_end(T, cfg['alt'])
    CHA = prog(' | '.join(cfg['chords'].split('|')[:-2] + cfg['alt_chords'].split('|')))
    chk(T, CH, key, name + ' thème')
    chk(TA, CHA, key, name + ' thème/fin')
    pen = cfg['penta']

    def harmony(t, chords, k, v, padn=4, tex=None, tex_v=46, b_style=None, density=1.0, swell=12):
        pad(s, 'pad', t, chords, k, n=padn, lo=k.tonic - 10, hi=k.tonic + 14, vel=v, swell=swell)
        bass(s, 'bass', t, chords, k, lo=34, hi=50, vel=v + 4,
             style=b_style or cfg['bassp'][1])
        if tex:
            texture_layer(c, tex, t, chords, k, tex_v, pen, rng, density)

    # ---------------- intro (4 mesures)
    t = 0.0
    s.mark(t, 'intro')
    ich = prog(cfg['intro'])
    pad(s, 'pad', t, ich, key, n=3, lo=key.tonic - 10, hi=key.tonic + 10, vel=40, swell=30)
    s.note('drone', t, c.beats(4), key.tonic - 12, 34)
    s.note('drone', t, c.beats(4), key.tonic - 5, 28)
    texture_layer(c, cfg['texture'], t, ich, key, 40, pen, rng, density=0.6)
    s.ramp('pad', t, t + c.beats(2), 11, 50, 100)
    head = window(theme(LEIT), 0, 4)
    melody(s, 'lead2', t + c.beats(2), head, key, octave=l2o, vel=l2v - 14, swell=20)
    if cfg['perc'] == 'bell':
        s.note('bell', t, 8, key.tonic + 12, 44)
    t += c.beats(4)

    # ---------------- A : thème + variation (16 mesures)
    s.mark(t, 'A')
    harmony(t, CH, key, 46, tex=cfg['texture'], tex_v=42, density=0.8)
    melody(s, 'lead', t, T, key, octave=lo_, vel=lv - 6, dyn=(-4, 4), swell=18)
    perc_layer(c, cfg['perc'], t, 8, 40)
    t += c.beats(8)
    TV = rhythm_vary(ornament(TA, rng, 0.4), rng, 0.3)
    chk(TV, CHA, key, name + ' variation')
    harmony(t, CHA, key, 50, tex=cfg['texture2'], tex_v=44)
    melody(s, 'lead', t, TV, key, octave=lo_, vel=lv, dyn=(0, 4), swell=18)
    counter(s, 'counter', t, CHA, key, key.tonic - 12, key.tonic + 3, rhythm=2, vel=cfg['counter'][1] - 14,
            against=TV)
    perc_layer(c, cfg['perc'], t, 8, 44)
    t += c.beats(8)

    # ---------------- transition (2)
    tch = prog(cfg['trans'])
    harmony(t, tch, key, 48, padn=4, tex=cfg['texture2'], tex_v=42, swell=25)
    roll(s, 'timp', t + 4, 4, timp_pitch(key, 7), 20, 52)
    t += c.beats(2)

    # ---------------- B : nouvelle tonalité, mélodie développée (8)
    s.mark(t, 'B')
    bk = cfg['b_key']
    bch = prog(cfg['b_prog'])
    BL = gen_line(rng, bch, bk, 8, motifs=['1 1 2', '1.5 .5 2', '2 1 1', '1 .5 .5 1 1'],
                  lo=0, hi=8, form='abac', end=4 if 'V' in cfg['b_prog'].split('|')[-1] else 0)
    chk(BL, bch, bk, name + ' B')
    harmony(t, bch, bk, 44, tex=cfg['texture'], tex_v=40, b_style='root')
    melody(s, 'lead2', t, BL, bk, octave=l2o, vel=l2v - 4, dyn=(-4, 6), swell=16)
    counter(s, 'counter', t, bch, bk, bk.tonic - 10, bk.tonic + 5, rhythm=4, vel=cfg['counter'][1] - 18,
            against=BL)
    t += c.beats(8)

    # ---------------- A' : thème avec fin, orchestration allégée (8)
    s.mark(t, "A'")
    TP = ornament(TA, rng, 0.25)
    chk(TP, CHA, key, name + " A'")
    harmony(t, CHA, key, 42, padn=3, tex=cfg['texture2'], tex_v=40, density=0.7)
    melody(s, 'lead2' if cfg['lead'][0] != cfg['lead2'][0] else 'lead', t, TP, key, octave=l2o, vel=l2v - 6,
           swell=16)
    t += c.beats(8)

    # ---------------- C : leitmotiv (8) puis canon pentatonique sur bourdon (4)
    s.mark(t, 'C')
    ck = Key(key.tonic, cfg['c_mode'])
    L = theme(LEIT)
    lch = prog(LEIT_CH[cfg['c_mode']])
    chk(L, lch, ck, name + ' leitmotiv')
    harmony(t, lch, ck, 50, tex='harp' if cfg['texture'] != 'harp' else 'piano', tex_v=42)
    melody(s, 'cl', t, L, ck, octave=cfg['c_lead'][1], vel=cfg['c_lead'][2], dyn=(-4, 6), swell=20)
    counter(s, 'counter', t, lch, ck, ck.tonic - 12, ck.tonic + 2, rhythm=2, vel=cfg['counter'][1] - 16,
            against=L)
    perc_layer(c, cfg['perc'], t, 8, 46)
    t += c.beats(8)
    pk = ck.with_penta(pen)
    drone_ch = prog('i5 | i5 | i5 | i5' if cfg['c_mode'] != 'ionian' else 'I5 | I5 | I5 | I5')
    pad(s, 'pad', t, drone_ch, ck, n=3, lo=ck.tonic - 12, hi=ck.tonic + 7, vel=44)
    s.note('drone', t, c.beats(4), ck.tonic - 12, 40)
    s.note('bass', t, c.beats(4), ck.tonic - 24, 46)
    canon = augment(window(L, 0, 8), 1.0)
    canon = concat(canon, window(L, 16, 24))
    melody(s, 'lead', t, canon, pk, octave=lo_, vel=lv - 10, swell=18)
    melody(s, 'koto', t + 2, canon, pk, octave=1, vel=52)
    perc_layer(c, cfg['perc'] if cfg['perc'] != 'none' else 'taiko_soft', t, 4, 38)
    t += c.beats(4)

    # ---------------- transition (2) : crescendo
    harmony(t, tch, key, 52, tex=cfg['texture2'], tex_v=46, swell=30)
    roll(s, 'timp', t, 8, timp_pitch(key, 7), 18, 58)
    t += c.beats(2)

    # ---------------- A'' : tutti doux, éventuellement modulé (8 + 8)
    s.mark(t, "A''")
    fk = Key(key.tonic + cfg['lift'], key.mode)
    harmony(t, CH, fk, 54, padn=5, tex=cfg['texture'], tex_v=48)
    melody(s, 'lead', t, T, fk, octave=lo_, vel=lv + 2, dyn=(0, 4), swell=14)
    melody(s, 'lead2', t, T, fk, octave=l2o + (1 if l2o == lo_ else 0), vel=l2v - 16)
    counter(s, 'horn', t, CH, fk, fk.tonic - 10, fk.tonic + 4, rhythm=4, vel=52, against=T)
    perc_layer(c, cfg['perc'], t, 8, 48)
    t += c.beats(8)
    TF = ornament(TA, rng, 0.3)
    chk(TF, CHA, fk, name + " A''")
    harmony(t, CHA, fk, 52, padn=5, tex=cfg['texture2'], tex_v=46)
    melody(s, 'lead', t, TF, fk, octave=lo_, vel=lv, dyn=(2, -10), swell=14)
    counter(s, 'counter', t, CHA, fk, fk.tonic - 12, fk.tonic + 3, rhythm=2, vel=cfg['counter'][1] - 14,
            against=TF)
    counter(s, 'horn', t, CHA, fk, fk.tonic - 5, fk.tonic + 9, rhythm=4, vel=46, against=TF)
    perc_layer(c, cfg['perc'], t, 7, 42)
    t += c.beats(8)

    # ---------------- coda (4) : rallentando, dernier accord tenu
    s.mark(t, 'coda')
    och = prog(cfg['outro'])
    pad(s, 'pad', t, och, fk, n=4, lo=fk.tonic - 10, hi=fk.tonic + 12, vel=44)
    s.ramp('pad', t + c.beats(2), t + c.beats(4) + 4, 11, 100, 40)
    bass(s, 'bass', t, och, fk, lo=34, hi=50, vel=44, style='root')
    texture_layer(c, cfg['texture'], t, och[:2], fk, 38, pen, rng, density=0.5)
    tail = window(theme(LEIT), 0, 4)
    melody(s, 'lead2', t + c.beats(1), tail, fk, octave=l2o, vel=l2v - 18, swell=20)
    fin = prog('I' if fk.mode == 'ionian' else 'i')
    arp(s, 'harp', t + c.beats(2), fin + [(4, 4, fin[0][2])], fk, pattern='0 1 2 3 4 5 6 7', sub=0.25,
        lo=fk.tonic - 12, vel=34, ring=8)
    s.rit(t + c.beats(2), t + c.beats(4), cfg['bpm'] * 0.82)
    if cfg['perc'] == 'bell':
        s.note('bell', t + c.beats(3), 8, fk.tonic + 12, 40)
    t += c.beats(4)
    s.end = max(s.end, t + 2)
    return s


# --------------------------------------------------------------- menu (~2 min)
def build_menu():
    rng = random.Random(7)
    s = Song('menu', 96, seed=7)
    for nm, prg, vol, pan, rev in [('horn', HORN, 92, 52, 58), ('horn2', HORN, 76, 70, 62),
                                   ('str', STR, 92, 64, 58), ('vln', STR, 84, 76, 55),
                                   ('pad', SLOWSTR, 74, 64, 62), ('choir', CHOIR, 56, 64, 70),
                                   ('cello', CELLO, 80, 44, 50), ('bass', CBASS, 80, 56, 45),
                                   ('harp', HARP, 82, 36, 55), ('flute', FLUTE, 84, 74, 58),
                                   ('piano', PIANO, 74, 70, 55), ('timp', TIMP, 70, 64, 52),
                                   ('koto', KOTO, 70, 88, 50)]:
        s.part(nm, prg, vol=vol, pan=pan, rev=rev, human=10, legato=1.02)
    D = Key(62, 'ionian')
    L = theme(LEIT)
    lch = prog(LEIT_CH['ionian'])
    chk(L, lch, D, 'menu leitmotiv')
    t = 0.0

    def tutti(t, chords, k, v, tex=True, padn=4, bstyle='root'):
        pad(s, 'pad', t, chords, k, n=padn, lo=k.tonic - 12, hi=k.tonic + 12, vel=v, swell=10)
        bass(s, 'bass', t, chords, k, lo=34, hi=50, vel=v + 6, style=bstyle)
        if tex:
            arp(s, 'harp', t, chords, k, pattern='0 2 4 5 7 5 4 2', sub=0.5, lo=k.tonic - 12, vel=v - 4,
                ring=2.5)

    # intro (4) : appel de cor sur pédale, roulement de timbales
    s.mark(t, 'intro')
    ich = prog('Isus2 | I | IVadd9/I | I')
    pad(s, 'pad', t, ich, D, n=4, lo=50, hi=74, vel=42, swell=30)
    s.note('bass', t, 16, 38, 50)
    melody(s, 'horn', t + 4, window(L, 0, 4), D, octave=-1, vel=64, swell=20)
    melody(s, 'horn2', t + 10, window(L, 0, 4), Key(69, 'ionian'), octave=-1, vel=58, swell=20)
    arp(s, 'harp', t + 8, prog('IVadd9/I | I'), D, pattern='0 1 2 3 4 5 6 7', sub=0.25, lo=50, vel=36,
        ring=6)
    roll(s, 'timp', t + 12, 4, 45, 18, 56)
    t += 16
    # A (8) : leitmotiv aux cors
    s.mark(t, 'A')
    tutti(t, lch, D, 50)
    melody(s, 'horn', t, L, D, octave=-1, vel=78, dyn=(-2, 6), swell=16)
    counter(s, 'cello', t, lch, D, 45, 60, rhythm=2, vel=50, against=L)
    hits(s, 'timp', t, [(0, 0), (16, -6)], 38, 50)
    t += 32
    # A2 (8) : violons à l'octave, cor en contre-chant, variation
    LV = ornament(L, rng, 0.45)
    chk(LV, lch, D, 'menu variation')
    tutti(t, lch, D, 54)
    melody(s, 'vln', t, LV, D, octave=0, vel=76, dyn=(0, 6), swell=14)
    counter(s, 'horn2', t, lch, D, 55, 69, rhythm=4, vel=56, against=LV)
    counter(s, 'cello', t, lch, D, 43, 57, rhythm=2, vel=50, against=LV)
    t += 32
    # B (8) : si mineur, flûte et piano, plus intime
    s.mark(t, 'B')
    Bm = Key(59, 'aeolian')
    bch = prog('i | bVI | bIII | bVII | iv | bVI | iv7 | V')
    BL = gen_line(rng, bch, Bm, 8, motifs=['1 2 .5 .5', '1.5 .5 2', '2 1 1', '1 1 1 1'], lo=2, hi=9,
                  form='abab', end=4)
    chk(BL, bch, Bm, 'menu B')
    pad(s, 'pad', t, bch, Bm, n=3, lo=50, hi=72, vel=42)
    bass(s, 'bass', t, bch, Bm, lo=35, hi=50, vel=44)
    arp(s, 'piano', t, bch, Bm, pattern='0 3 4 . 5 4 3 .', sub=0.5, lo=47, vel=42, pedal=True, ring=2)
    melody(s, 'flute', t, BL, Bm, octave=0, vel=78, dyn=(-4, 6), swell=16)
    t += 32
    # C (8) : développement (rythmes du leitmotiv, séquences), retour en ré
    s.mark(t, 'C')
    cch = prog('IV | V | vi | iii | IV | I | ii7 | V7sus4 V7')
    CL = gen_line(rng, cch, D, 8, motifs=['1 2 .5 .5', '1.5 .5 2', '1 1 1 1'], lo=0, hi=9, form='aabb',
                  end=4)
    chk(CL, cch, D, 'menu C')
    tutti(t, cch, D, 50)
    melody(s, 'str', t, CL, D, octave=0, vel=72, dyn=(-6, 8), swell=16)
    koto(s, 'koto', t, cch, D.with_penta('majp'), figure='0 2 4 2', sub=1, lo=62, vel=40, grace=0.2, rng=rng)
    counter(s, 'horn2', t, cch, D, 55, 69, rhythm=4, vel=50, against=CL)
    roll(s, 'timp', t + 24, 8, 45, 20, 60)
    s.ramp('pad', t + 20, t + 32, 11, 90, 115)
    t += 32
    # A'' (8) : modulé en mi majeur, tutti doux et lumineux
    s.mark(t, "A''")
    E = Key(64, 'ionian')
    tutti(t, lch, E, 58, padn=5)
    pad(s, 'choir', t, lch, E, n=3, lo=55, hi=74, vel=46)
    melody(s, 'horn', t, L, E, octave=-1, vel=84, dyn=(0, 6), swell=12)
    melody(s, 'vln', t, L, E, octave=0, vel=70, swell=10)
    counter(s, 'cello', t, lch, E, 45, 60, rhythm=2, vel=54, against=L)
    hits(s, 'timp', t, [(0, 0), (16, -4), (28, -6)], 40, 56)
    t += 32
    # coda (4)
    s.mark(t, 'coda')
    och = prog('IVadd9 | iii7 | IVadd9 | I')
    pad(s, 'pad', t, och, E, n=4, lo=52, hi=76, vel=46)
    pad(s, 'choir', t, och, E, n=3, lo=56, hi=74, vel=38)
    bass(s, 'bass', t, och, E, lo=36, hi=52, vel=48)
    melody(s, 'horn2', t, window(L, 0, 4), E, octave=-1, vel=58, swell=20)
    arp(s, 'harp', t + 8, prog('IVadd9 | I'), E, pattern='0 1 2 3 4 5 6 7', sub=0.25, lo=52, vel=36,
        ring=8)
    s.ramp('pad', t + 8, t + 20, 11, 100, 40)
    s.rit(t + 8, t + 16, 76, 96)
    t += 16
    s.end = max(s.end, t + 2)
    return s


# --------------------------------------------------------------- jingles
def build_victory():
    s = Song('victory', 92, seed=11)
    for nm, prg, vol, pan in [('horn', HORN, 96, 54), ('str', STR, 88, 70), ('pad', SLOWSTR, 78, 64),
                              ('harp', HARP, 84, 40), ('timp', TIMP, 74, 64), ('bass', CBASS, 78, 56),
                              ('choir', CHOIR, 56, 64)]:
        s.part(nm, prg, vol=vol, pan=pan, rev=60, human=8, legato=1.02)
    D = Key(62, 'ionian')
    mel = theme('0:1 4:2 3:.5 4:.5 | 5:1.5 4:.5 7:2 | 6:1 5:1 4:1 6:1 | 7:4 | r:4')
    ch = prog('I | IV | V | I | I')
    chk(mel, ch, D, 'victory')
    melody(s, 'horn', 0, mel, D, octave=-1, vel=84, swell=12)
    melody(s, 'str', 0, mel, D, octave=0, vel=68)
    pad(s, 'pad', 0, ch, D, n=4, lo=50, hi=74, vel=54)
    pad(s, 'choir', 12, ch[3:], D, n=3, lo=55, hi=74, vel=46)
    bass(s, 'bass', 0, ch, D, lo=36, hi=50, vel=58)
    arp(s, 'harp', 0, ch[:3], D, pattern='0 2 4 5 7 5 4 2', sub=0.5, lo=50, vel=46, ring=2.5)
    arp(s, 'harp', 12, ch[3:4], D, pattern='0 1 2 3 4 5 6 7', sub=0.25, lo=50, vel=44, ring=8)
    roll(s, 'timp', 9, 3, 45, 22, 62)
    hits(s, 'timp', 12, [(0, 0)], 38, 64)
    s.rit(10, 14, 74, 92)
    s.end = 16
    return s


def build_defeat():
    s = Song('defeat', 72, seed=13)
    for nm, prg, vol, pan in [('cello', CELLO, 96, 52), ('pad', SLOWSTR, 78, 64), ('piano', PIANO, 74, 70),
                              ('bass', CBASS, 74, 56), ('oboe', OBOE, 80, 74)]:
        s.part(nm, prg, vol=vol, pan=pan, rev=62, human=10, legato=1.02)
    Dm = Key(50, 'aeolian')
    mel = theme('0:1 4:2 3:.5 4:.5 | 5:1.5 4:.5 1:1 -1:1 | 0:4')
    ch = prog('i | bVI:2 v:2 | i')
    chk(mel, ch, Dm, 'defeat')
    melody(s, 'cello', 0, mel, Dm, octave=0, vel=74, swell=16)
    melody(s, 'oboe', 4, window(mel, 4, 8), Key(62, 'aeolian'), vel=56, swell=16)
    pad(s, 'pad', 0, ch, Dm, n=4, lo=50, hi=70, vel=48)
    bass(s, 'bass', 0, ch, Dm, lo=33, hi=45, vel=50)
    arp(s, 'piano', 8, ch[-1:], Dm, pattern='0 2 4 5', sub=0.75, lo=50, vel=40, pedal=True, ring=4)
    s.rit(6, 12, 58, 72)
    s.end = 14
    return s


def build_check_sting():
    s = Song('check_sting', 100, seed=17)
    s.part('taiko', TAIKO, vol=96, pan=64, rev=50, human=2)
    s.part('timp', TIMP, vol=80, pan=64, rev=55, human=2)
    s.part('trem', TREM, vol=88, pan=64, rev=62, human=4)
    s.part('horn', HORN, vol=70, pan=52, rev=60, human=4)
    s.part('bass', CBASS, vol=78, pan=58, rev=50, human=2)
    s.note('taiko', 0, 2, 41, 96)
    s.note('taiko', 0.5, 2, 36, 64)
    s.note('timp', 0, 3, 38, 70)
    for p, v in [(50, 64), (57, 60), (62, 62), (65, 64), (69, 58)]:
        s.note('trem', 0.02, 4, p, v)
    s.ramp('trem', 0, 1.2, 11, 60, 118)
    s.ramp('trem', 1.4, 4.2, 11, 118, 30)
    s.note('horn', 0.5, 3, 57, 56)
    s.note('horn', 0.5, 3, 50, 52)
    s.note('bass', 0, 4, 38, 64)
    s.end = 5
    return s


def all_songs():
    out = {'menu': build_menu}
    for n in GAMES:
        out[n] = (lambda n=n: build_game(n))
    out['victory'] = build_victory
    out['defeat'] = build_defeat
    out['check_sting'] = build_check_sting
    return out
