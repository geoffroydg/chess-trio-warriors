// Topologie du plateau ROND « Chess for 3 » : 24 colonnes radiales × 6 anneaux = 144 cases,
// autour d'un médaillon central traversable mais non occupable.
//
// Repérage d'une case : équipe propriétaire s ∈ {0,1,2}, colonne f ∈ 0..7 (a..h) et anneau
// r ∈ 0..5 (anneau 1 = extérieur … anneau 6 = intérieur, au bord du médaillon).
// Nom : `${s}${'abcdefgh'[f]}${r + 1}` (ex. "0d1"). Index : s*48 + r*8 + f.
//
// Colonne absolue (« secteur angulaire ») w ∈ 0..23 : secteur de 15° [15w, 15w + 15] en degrés,
// sens trigonométrique vu à l'écran. Chaque équipe occupe 8 colonnes consécutives : l'équipe 0
// commence à w = 14 (210°, en bas), l'équipe 1 à w = 6 (90°, en haut à gauche) et l'équipe 2 à
// w = 22 (330°, en haut à droite). Colonnes a → h dans le sens trigonométrique, si bien que
// l'ordre de jeu 0 → 1 → 2 tourne dans le sens horaire.
//
// Pas élémentaires (rd = sens radial : +1 vers le centre, −1 vers l'extérieur ; s = ±1 sens
// angulaire) :
//  - vertical : (w, r) → (w, r + rd) ; depuis l'anneau 6 vers le centre, on traverse le
//    médaillon et on arrive en (w + 12, anneau 6), puis on continue vers l'extérieur ;
//  - diagonal : (w, r) → (w + s, r + rd) ; depuis l'anneau 6 vers le centre, la traversée du
//    médaillon compte comme une case virtuelle : on ressort en (w + 12 + 2s, anneau 6), puis on
//    continue vers l'extérieur avec le même sens s (la couleur de case est conservée) ;
//    vers l'extérieur, la diagonale s'arrête au bord (pas de rebond) ;
//  - horizontal : (w, r) → (w + s, r), l'anneau boucle sur 24 cases.
//
// Épées : les 3 lignes radiales qui séparent deux équipes. La frontière b est celle qui précède
// la colonne a de l'équipe b. Un pas qui franchit une frontière avec une extrémité sur
// l'anneau 1 traverse la POIGNÉE b ; avec son extrémité la plus extérieure sur l'anneau 2 ou 3,
// il traverse la LAME b.

export const FILES = 'abcdefgh';
export const NUM_RINGS = 6;
export const NUM_WEDGES = 24;
export const NUM_CELLS = 144;

/** Première colonne absolue (colonne a) de chaque équipe. */
export const TEAM_START_WEDGE: readonly number[] = [14, 6, 22];

export const teamOf = (c: number) => (c / 48) | 0;
export const fileOf = (c: number) => c % 8;
/** Anneau 0..5 (0 = anneau 1, extérieur). */
export const ringOf = (c: number) => ((c % 48) / 8) | 0;
export const cellIndex = (s: number, f: number, r: number) => s * 48 + r * 8 + f;
const mod24 = (w: number) => ((w % 24) + 24) % 24;

export function wedgeOf(c: number): number {
  return mod24(TEAM_START_WEDGE[teamOf(c)] + fileOf(c));
}

const WEDGE_TEAM = new Int8Array(24);
const WEDGE_FILE = new Int8Array(24);
for (let s = 0; s < 3; s++) {
  for (let f = 0; f < 8; f++) {
    WEDGE_TEAM[mod24(TEAM_START_WEDGE[s] + f)] = s;
    WEDGE_FILE[mod24(TEAM_START_WEDGE[s] + f)] = f;
  }
}

/** Case de la colonne absolue w et de l'anneau r (0..5). */
export function cellAt(w: number, r: number): number {
  const m = mod24(w);
  return cellIndex(WEDGE_TEAM[m], WEDGE_FILE[m], r);
}

/** Couleur de case : (colonne + anneau) pair → case claire (h1 est claire, comme aux échecs). */
export function isLight(c: number): boolean {
  return (fileOf(c) + ringOf(c) + 1) % 2 === 0;
}

export function cellName(c: number): string {
  if (!(c >= 0 && c < NUM_CELLS) || !Number.isInteger(c)) throw new Error(`case invalide : ${c}`);
  return `${teamOf(c)}${FILES[fileOf(c)]}${ringOf(c) + 1}`;
}

const CELL_RE = /^([0-2])([a-h])([1-6])$/;
export function parseCell(name: string): number {
  const m = typeof name === 'string' ? CELL_RE.exec(name) : null;
  if (!m) throw new Error(`case invalide : ${name}`);
  return cellIndex(Number(m[1]), FILES.indexOf(m[2]), Number(m[3]) - 1);
}

/** Rotation d'une équipe : case correspondante de l'équipe (s + k) mod 3. */
export function rotateCell(c: number, k: number): number {
  return cellIndex((teamOf(c) + k) % 3, fileOf(c), ringOf(c));
}

/** Frontière (0..2) entre deux colonnes absolues voisines, ou −1. */
export function borderBetween(w1: number, w2: number): number {
  const a = mod24(w1);
  const b = mod24(w2);
  const hi = mod24(a + 1) === b ? b : mod24(b + 1) === a ? a : -1;
  if (hi < 0) return -1;
  return WEDGE_FILE[hi] === 0 ? WEDGE_TEAM[hi] : -1;
}

/** Les deux frontières (poignées) d'une équipe : côté colonne a, côté colonne h. */
export const TEAM_BORDERS: readonly (readonly [number, number])[] = [0, 1, 2].map((s) => {
  const after = mod24(TEAM_START_WEDGE[s] + 8);
  return [s, WEDGE_TEAM[after]] as const;
});

// ---------------------------------------------------------------------------
// Pas élémentaires
// ---------------------------------------------------------------------------

/** Position courante d'un trajet : colonne absolue, anneau, sens radial. */
interface Pos {
  w: number;
  r: number;
  rd: number;
}

export interface StepInfo {
  w: number;
  r: number;
  rd: number;
  /** Le pas traverse le médaillon. */
  center: boolean;
  /** Masque (bit b) des poignées franchies par ce pas. */
  hilt: number;
  /** Masque des lames franchies par ce pas. */
  blade: number;
}

function crossing(w1: number, r1: number, w2: number, r2: number): { hilt: number; blade: number } {
  if (w1 === w2) return { hilt: 0, blade: 0 };
  const b = borderBetween(w1, w2);
  if (b < 0) return { hilt: 0, blade: 0 };
  const outer = Math.min(r1, r2); // anneau le plus extérieur (0 = anneau 1)
  if (outer === 0) return { hilt: 1 << b, blade: 0 };
  if (outer <= 2) return { hilt: 0, blade: 1 << b };
  return { hilt: 0, blade: 0 };
}

/** Pas vertical dans le sens radial p.rd (null au bord extérieur). */
export function stepV(p: Pos): StepInfo | null {
  if (p.rd > 0) {
    if (p.r < NUM_RINGS - 1) return { w: p.w, r: p.r + 1, rd: 1, center: false, hilt: 0, blade: 0 };
    return { w: mod24(p.w + 12), r: p.r, rd: -1, center: true, hilt: 0, blade: 0 };
  }
  if (p.r > 0) return { w: p.w, r: p.r - 1, rd: -1, center: false, hilt: 0, blade: 0 };
  return null;
}

/** Pas diagonal (sens radial p.rd, sens angulaire s). */
export function stepD(p: Pos, s: number): StepInfo | null {
  if (p.rd > 0) {
    if (p.r < NUM_RINGS - 1) {
      const w = mod24(p.w + s);
      return { w, r: p.r + 1, rd: 1, center: false, ...crossing(p.w, p.r, w, p.r + 1) };
    }
    return { w: mod24(p.w + 12 + 2 * s), r: p.r, rd: -1, center: true, hilt: 0, blade: 0 };
  }
  if (p.r > 0) {
    const w = mod24(p.w + s);
    return { w, r: p.r - 1, rd: -1, center: false, ...crossing(p.w, p.r, w, p.r - 1) };
  }
  return null;
}

/** Pas horizontal (le sens radial est conservé). */
export function stepH(p: Pos, s: number): StepInfo {
  const w = mod24(p.w + s);
  return { w, r: p.r, rd: p.rd, center: false, ...crossing(p.w, p.r, w, p.r) };
}

const posOf = (c: number, rd: number): Pos => ({ w: wedgeOf(c), r: ringOf(c), rd });

// ---------------------------------------------------------------------------
// Tables précalculées
// ---------------------------------------------------------------------------

/**
 * Directions des pièces à longue portée : 0 vertical vers le centre, 1 vertical vers
 * l'extérieur, 2 et 3 horizontales (+/−), 4 à 7 diagonales (centre +, centre −, extérieur +,
 * extérieur −). Tour : 0-3, fou : 4-7, dame : 0-7.
 */
export const NUM_DIRS = 8;

export interface Ray {
  cells: Int16Array;
  /** Masque cumulé des poignées franchies jusqu'à la case i incluse. */
  hilt: Uint8Array;
  /** 1 si le trajet a traversé le centre jusqu'à la case i incluse. */
  center: Uint8Array;
}

function buildRay(c: number, d: number): Ray {
  const cells: number[] = [];
  const hilt: number[] = [];
  const center: number[] = [];
  let p: Pos = posOf(c, d === 1 || d === 6 || d === 7 ? -1 : 1);
  let mask = 0;
  let cen = 0;
  for (let i = 0; i < 24; i++) {
    let st: StepInfo | null;
    if (d <= 1) st = stepV(p);
    else if (d <= 3) st = stepH(p, d === 2 ? 1 : -1);
    else st = stepD(p, d === 4 || d === 6 ? 1 : -1);
    if (!st) break;
    const to = cellAt(st.w, st.r);
    if (to === c) break; // horizontale : retour sur la case de départ
    mask |= st.hilt;
    if (st.center) cen = 1;
    cells.push(to);
    hilt.push(mask);
    center.push(cen);
    p = st;
  }
  return { cells: Int16Array.from(cells), hilt: Uint8Array.from(hilt), center: Uint8Array.from(center) };
}

/** RAYS[c * 8 + d]. */
export const RAYS: readonly Ray[] = (() => {
  const out: Ray[] = [];
  for (let c = 0; c < NUM_CELLS; c++) for (let d = 0; d < NUM_DIRS; d++) out.push(buildRay(c, d));
  return out;
})();

/**
 * Destination d'un saut (roi, cavalier). Pour le cavalier, les deux décompositions d'un même
 * saut (2 verticaux + 1 horizontal, ou l'inverse) forment UN coup : si l'une d'elles fait son
 * pas horizontal sur l'anneau 1 à travers une frontière, le saut franchit la poignée.
 */
export interface Jump {
  to: number;
  /** Masque (union sur les décompositions) des poignées franchies. */
  mask: number;
  /** Toutes les décompositions traversent le centre. */
  center: boolean;
}

function addJump(map: Map<number, { masks: Set<number>; center: boolean[] }>, from: number, path: (StepInfo | null)[]) {
  if (path.some((x) => x === null)) return;
  const steps = path as StepInfo[];
  const last = steps[steps.length - 1];
  const to = cellAt(last.w, last.r);
  if (to === from) return;
  let mask = 0;
  let cen = false;
  for (const s of steps) {
    mask |= s.hilt;
    cen ||= s.center;
  }
  let e = map.get(to);
  if (!e) map.set(to, (e = { masks: new Set(), center: [] }));
  e.masks.add(mask);
  e.center.push(cen);
}

function finishJumps(map: Map<number, { masks: Set<number>; center: boolean[] }>): Jump[] {
  return [...map.entries()].map(([to, e]) => ({
    to,
    mask: [...e.masks].reduce((a, b) => a | b, 0),
    center: e.center.every(Boolean),
  }));
}

/** Pas du roi : une case dans chacune des 8 directions. */
export const KING_JUMPS: readonly Jump[][] = Array.from({ length: NUM_CELLS }, (_, c) => {
  const map = new Map();
  for (const rd of [1, -1]) {
    addJump(map, c, [stepV(posOf(c, rd))]);
    for (const s of [1, -1]) addJump(map, c, [stepD(posOf(c, rd), s)]);
  }
  for (const s of [1, -1]) addJump(map, c, [stepH(posOf(c, 1), s)]);
  return finishJumps(map);
});

/**
 * Sauts du cavalier : 2 pas verticaux puis 1 pas horizontal, ou 1 pas horizontal puis 2 pas
 * verticaux (le centre se traverse comme pour les autres pièces). Les destinations identiques
 * sont fusionnées. Il n'y a pas de forme « 2 horizontaux + 1 vertical » (règle du jeu).
 */
export const KNIGHT_JUMPS: readonly Jump[][] = Array.from({ length: NUM_CELLS }, (_, c) => {
  const map = new Map();
  for (const rd of [1, -1]) {
    for (const s of [1, -1]) {
      // 2 verticaux puis 1 horizontal.
      const v1 = stepV(posOf(c, rd));
      const v2 = v1 && stepV(v1);
      addJump(map, c, [v1, v2, v2 && stepH(v2, s)]);
      // 1 horizontal puis 2 verticaux.
      const h1 = stepH(posOf(c, rd), s);
      const w1 = stepV(h1);
      addJump(map, c, [h1, w1, w1 && stepV(w1)]);
    }
  }
  return finishJumps(map);
});

export interface PawnStep {
  to: number;
  hilt: number;
  blade: number;
  center: boolean;
}

function pawnStep(st: StepInfo | null): PawnStep | null {
  return st ? { to: cellAt(st.w, st.r), hilt: st.hilt, blade: st.blade, center: st.center } : null;
}

/**
 * Avance d'un pion : PAWN_PUSH[x][c], x = 0 avant la traversée du centre (vers le centre),
 * x = 1 après (vers l'extérieur). null au bord.
 */
export const PAWN_PUSH: readonly (PawnStep | null)[][] = [1, -1].map((rd) =>
  Array.from({ length: NUM_CELLS }, (_, c) => pawnStep(stepV(posOf(c, rd)))),
);

/** Prises d'un pion (diagonales vers l'avant), toutes contraintes comprises dans les champs. */
export const PAWN_CAPTURES: readonly PawnStep[][][] = [1, -1].map((rd) =>
  Array.from({ length: NUM_CELLS }, (_, c) =>
    [1, -1].map((s) => pawnStep(stepD(posOf(c, rd), s))).filter((x): x is PawnStep => x !== null),
  ),
);

/** Une prise de pion est-elle permise (pas de poignée ; pas de lame avant la traversée) ? */
export const pawnCaptureOk = (e: PawnStep, crossed: number) => e.hilt === 0 && (crossed === 1 || e.blade === 0);

/** PAWN_ATTACKERS[x][c] : cases d'où un pion (non traversé x = 0, traversé x = 1) attaque c. */
export const PAWN_ATTACKERS: readonly Int16Array[][] = [0, 1].map((x) => {
  const lists: number[][] = Array.from({ length: NUM_CELLS }, () => []);
  for (let c = 0; c < NUM_CELLS; c++) for (const e of PAWN_CAPTURES[x][c]) if (pawnCaptureOk(e, x)) lists[e.to].push(c);
  return lists.map((l) => Int16Array.from(l));
});

/** Cases d'où un cavalier / un roi attaque c (trajets sans poignée uniquement). */
export const KNIGHT_ATTACKERS: readonly Int16Array[] = KNIGHT_JUMPS.map((js) =>
  Int16Array.from(js.filter((j) => j.mask === 0).map((j) => j.to)),
);
export const KING_ATTACKERS: readonly Int16Array[] = KING_JUMPS.map((js) =>
  Int16Array.from(js.filter((j) => j.mask === 0).map((j) => j.to)),
);

/** LINES[c][x] = 1 si x est sur un rayon (sans poignée) partant de c. */
export const LINES: readonly Uint8Array[] = Array.from({ length: NUM_CELLS }, (_, c) => {
  const m = new Uint8Array(NUM_CELLS);
  for (let d = 0; d < NUM_DIRS; d++) {
    const ray = RAYS[c * NUM_DIRS + d];
    for (let i = 0; i < ray.cells.length && ray.hilt[i] === 0; i++) m[ray.cells[i]] = 1;
  }
  return m;
});

/** Cases de l'anneau 1 (arrières) de chaque équipe. */
export const BACK_CELLS: readonly number[][] = [0, 1, 2].map((s) => Array.from({ length: 8 }, (_, f) => cellIndex(s, f, 0)));
