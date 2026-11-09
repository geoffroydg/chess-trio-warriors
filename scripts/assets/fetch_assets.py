"""Textures de particules CC0 -> app/assets/fx/*.png (+ LICENSE-CC0.txt, CREDITS).

1. Essaie de récupérer le « Particle Pack » de Kenney (CC0) depuis une liste de sources
   (pages HTML analysées pour trouver le .zip, puis URLs directes).
2. Vérifie chaque fichier (signature PNG, taille), le normalise (blanc + alpha, pour être
   teinté à l'exécution en mode « modulate » puis mélangé en additif), le réduit (≤ 256 px)
   et contrôle le budget total (≤ 1,5 Mo).
3. Repli obligatoire : toute texture manquante est générée procéduralement (numpy :
   halo radial, fumée par bruit de Perlin fractal, étincelle en étoile, traînée, flamme...).

Usage : python -I scripts/assets/fetch_assets.py [--offline] [dossier_sortie]
"""
import io
import os
import re
import sys
import urllib.request
import zipfile

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "app", "assets", "fx")
SIZE = 128  # px par texture (≤ 256)
BUDGET = 1_500_000
MAX_DOWNLOAD = 60_000_000
UA = "Mozilla/5.0 (ChessTrioWarriors asset pipeline; +https://github.com)"

# Pages à analyser pour trouver le lien du .zip (le nom contient un hash qui change).
PAGES = [
    "https://kenney.nl/assets/particle-pack",
    "https://www.kenney.nl/assets/particle-pack",
    "https://opengameart.org/content/particle-pack-80-sprites",
]
# URLs directes connues (essayées après les pages).
DIRECT = [
    "https://opengameart.org/sites/default/files/particlePack_1.1.zip",
    "https://opengameart.org/sites/default/files/kenney_particlePack.zip",
    "https://kenney.nl/content/3-assets/104-particle-pack/particlepack_1.1.zip",
]

# Texture du jeu -> fichiers candidats du pack Kenney (premier trouvé).
WANTED = {
    "glow": ["circle_05", "light_01", "circle_04"],
    "smoke_a": ["smoke_04", "smoke_01", "smoke_02"],
    "smoke_b": ["smoke_07", "smoke_08", "smoke_03"],
    "spark": ["spark_05", "spark_04", "spark_01"],
    "star": ["star_06", "star_08", "star_04"],
    "trace": ["trace_01", "trace_04", "trace_02"],
    "flare": ["flare_01", "light_03", "light_02"],
    "flame": ["fire_01", "flame_01", "flame_04", "fire_02"],
}

LICENSE = """Creative Commons Zero v1.0 Universal (CC0 1.0) - Domaine public
https://creativecommons.org/publicdomain/zero/1.0/

Les textures de ce dossier sont soit issues du « Particle Pack » de Kenney
(www.kenney.nl, licence CC0), soit générées procéduralement par
scripts/assets/fetch_assets.py et versées dans le domaine public (CC0) par
les auteurs de Chess Trio Warriors. Aucune attribution n'est requise.
"""


def log(*a):
    print("[assets]", *a, flush=True)


def http_get(url, limit=MAX_DOWNLOAD, timeout=25):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = r.read(limit + 1)
    if len(data) > limit:
        raise ValueError("fichier trop gros")
    return data


def find_zip_links(page_url):
    html = http_get(page_url, limit=3_000_000).decode("utf-8", "replace")
    links = re.findall(r'href="([^"]+\.zip)"', html)
    out = []
    for l in links:
        if l.startswith("//"):
            l = "https:" + l
        elif l.startswith("/"):
            m = re.match(r"(https?://[^/]+)", page_url)
            l = m.group(1) + l
        if "article" in l.lower() and "particle" not in l.lower():
            continue
        out.append(l)
    return out


def try_download_pack():
    candidates = []
    for p in PAGES:
        try:
            found = find_zip_links(p)
            log("page", p, "->", len(found), "lien(s) .zip")
            candidates += found
        except Exception as e:  # noqa: BLE001
            log("page indisponible", p, type(e).__name__, e)
    candidates += DIRECT
    seen = set()
    for url in candidates:
        if url in seen:
            continue
        seen.add(url)
        try:
            data = http_get(url)
            z = zipfile.ZipFile(io.BytesIO(data))
            names = [n for n in z.namelist() if n.lower().endswith(".png")]
            if len(names) < 10:
                raise ValueError("archive sans PNG")
            log("pack téléchargé :", url, len(data), "octets,", len(names), "PNG")
            return url, z, names
        except Exception as e:  # noqa: BLE001
            log("échec", url, type(e).__name__, e)
    return None, None, []


def is_png(data):
    return data[:8] == b"\x89PNG\r\n\x1a\n"


def normalize(img):
    """Image quelconque -> RGBA blanc dont l'alpha porte l'intensité, SIZE x SIZE."""
    img = img.convert("RGBA")
    a = np.asarray(img).astype(np.float32) / 255.0
    lum = a[..., :3].max(axis=2)
    alpha = a[..., 3]
    if alpha.min() > 0.99:  # fond opaque (noir) : la luminance devient l'alpha
        alpha = lum
    else:
        alpha = alpha * np.maximum(lum, 0.0001) ** 0.15
    out = np.zeros(a.shape, np.float32)
    out[..., :3] = 1.0
    out[..., 3] = alpha
    im = Image.fromarray((out * 255).clip(0, 255).astype(np.uint8), "RGBA")
    w, h = im.size
    s = SIZE / max(w, h)
    im = im.resize((max(1, round(w * s)), max(1, round(h * s))), Image.LANCZOS)
    canvas = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    canvas.paste(im, ((SIZE - im.size[0]) // 2, (SIZE - im.size[1]) // 2))
    return canvas


def from_pack(z, names):
    got, credits = {}, {}
    lower = {os.path.basename(n).lower(): n for n in names}
    # Préférer la variante transparente.
    for n in names:
        if "transparent" in n.lower():
            lower[os.path.basename(n).lower()] = n
    for key, cands in WANTED.items():
        for c in cands:
            n = lower.get(c + ".png")
            if not n:
                continue
            data = z.read(n)
            if not is_png(data) or len(data) > 4_000_000:
                log("ignoré (pas un PNG valide)", n)
                continue
            try:
                got[key] = normalize(Image.open(io.BytesIO(data)))
                credits[key] = os.path.basename(n)
                break
            except Exception as e:  # noqa: BLE001
                log("illisible", n, e)
    return got, credits


# ---------------------------------------------------------------- génération procédurale

def _grid(n=SIZE):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    c = (n - 1) / 2
    return (x - c) / c, (y - c) / c


def _fade(t):
    return t * t * t * (t * (t * 6 - 15) + 10)


def perlin(n, cells, seed):
    rng = np.random.default_rng(seed)
    ang = rng.uniform(0, 2 * np.pi, (cells + 1, cells + 1))
    gx, gy = np.cos(ang), np.sin(ang)
    gx[-1, :], gy[-1, :] = gx[0, :], gy[0, :]  # raccord (tuilable)
    gx[:, -1], gy[:, -1] = gx[:, 0], gy[:, 0]
    lin = np.linspace(0, cells, n, endpoint=False)
    x, y = np.meshgrid(lin, lin)
    xi, yi = x.astype(int), y.astype(int)
    xf, yf = x - xi, y - yi

    def dot(ix, iy, dx, dy):
        return gx[iy, ix] * dx + gy[iy, ix] * dy

    n00 = dot(xi, yi, xf, yf)
    n10 = dot(xi + 1, yi, xf - 1, yf)
    n01 = dot(xi, yi + 1, xf, yf - 1)
    n11 = dot(xi + 1, yi + 1, xf - 1, yf - 1)
    u, v = _fade(xf), _fade(yf)
    return (n00 * (1 - u) + n10 * u) * (1 - v) + (n01 * (1 - u) + n11 * u) * v


def fbm(n, seed, octaves=5):
    out = np.zeros((n, n), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += amp * perlin(n, 2 ** (o + 1), seed + o)
        tot += amp
        amp *= 0.5
    return out / tot


def _img(alpha):
    a = np.clip(alpha, 0, 1)
    rgba = np.zeros(a.shape + (4,), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def gen_glow():
    x, y = _grid()
    r = np.sqrt(x * x + y * y)
    return _img(np.exp(-(r ** 2) * 5.5) * 0.9 + np.exp(-(r ** 2) * 40) * 0.6 - 0.004)


def gen_smoke(seed):
    x, y = _grid()
    r = np.sqrt(x * x + y * y)
    n = fbm(SIZE, seed) * 0.5 + 0.5
    mask = np.clip(1 - r, 0, 1) ** 1.4
    return _img((np.clip((n - 0.3) * 3.0, 0, 1) ** 0.8 * 0.85 + 0.15) * mask)


def gen_spark():
    x, y = _grid()
    r = np.sqrt(x * x + y * y) + 1e-6
    ang = np.arctan2(y, x)
    rays = np.abs(np.cos(2 * ang)) ** 60 + 0.6 * np.abs(np.cos(2 * ang + np.pi / 2 * 0.5)) ** 120
    a = rays * np.exp(-r * 3.2) + np.exp(-(r ** 2) * 60)
    return _img(a * (1 - np.clip(r, 0, 1)))


def gen_star():
    x, y = _grid()
    r = np.sqrt(x * x + y * y) + 1e-6
    ang = np.arctan2(y, x) + np.pi / 2
    k = 0.55 + 0.45 * np.cos(5 * ang)
    edge = r / (0.25 + 0.65 * k ** 2)
    a = np.clip(1 - edge, 0, 1) ** 0.6 + np.exp(-(r ** 2) * 25) * 0.5
    return _img(a)


def gen_trace():
    x, y = _grid()
    a = np.exp(-(y ** 2) * 90) * np.clip(1 - np.abs(x), 0, 1) ** 0.7 * (0.55 + 0.45 * (x + 1) / 2)
    return _img(a * 1.1)


def gen_flare():
    x, y = _grid()
    r = np.sqrt(x * x + y * y)
    ring = np.exp(-((r - 0.62) ** 2) * 220) * 0.7
    cross = (np.exp(-(y ** 2) * 900) + np.exp(-(x ** 2) * 900)) * np.clip(1 - r, 0, 1) ** 2
    return _img(ring + cross + np.exp(-(r ** 2) * 30))


def gen_flame():
    x, y = _grid()
    yy = (y + 1) / 2  # 0 en haut, 1 en bas
    width = 0.12 + 0.55 * np.sin(np.clip(yy, 0, 1) * np.pi * 0.85) ** 1.3
    n = fbm(SIZE, 41, 4)
    body = np.clip(1 - np.abs(x + n * 0.25 * (1 - yy)) / width, 0, 1) ** 0.8
    a = body * np.clip(yy * 1.6, 0, 1) * np.clip((1 - yy) * 6, 0, 1)
    return _img(a)


GENERATORS = {
    "glow": gen_glow,
    "smoke_a": lambda: gen_smoke(11),
    "smoke_b": lambda: gen_smoke(23),
    "spark": gen_spark,
    "star": gen_star,
    "trace": gen_trace,
    "flare": gen_flare,
    "flame": gen_flame,
}


def main(argv):
    offline = "--offline" in argv
    args = [a for a in argv if not a.startswith("--")]
    out = args[0] if args else OUT
    os.makedirs(out, exist_ok=True)
    got, credits, source = {}, {}, None
    if not offline:
        source, z, names = try_download_pack()
        if z is not None:
            got, credits = from_pack(z, names)
    missing = [k for k in WANTED if k not in got]
    for k in missing:
        got[k] = GENERATORS[k]()
        credits[k] = "généré (procédural, numpy)"
    log("téléchargées :", len(WANTED) - len(missing), "générées :", len(missing))

    total = 0
    for key, img in got.items():
        path = os.path.join(out, key + ".png")
        img.save(path, optimize=True)
        data = open(path, "rb").read()
        assert is_png(data), path
        assert Image.open(path).size[0] <= 256
        total += len(data)
    assert total <= BUDGET, f"budget dépassé : {total} octets"
    log("total", total, "octets dans", out)

    with open(os.path.join(out, "LICENSE-CC0.txt"), "w", encoding="utf-8") as f:
        f.write(LICENSE)
    with open(os.path.join(out, "CREDITS"), "w", encoding="utf-8") as f:
        f.write("Textures d'effets de Chess Trio Warriors (toutes CC0)\n")
        if source:
            f.write(f"Source : Kenney « Particle Pack » (CC0, www.kenney.nl) - {source}\n")
        else:
            f.write("Source : génération procédurale (scripts/assets/fetch_assets.py)\n")
        f.write("\n")
        for key in WANTED:
            f.write(f"{key}.png : {credits[key]}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
