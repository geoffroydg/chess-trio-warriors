// Topologie explicite du plateau hexagonal d'échecs à 3 joueurs (96 cases).
//
// Chaque case est repérée par (secteur s, colonne f, rangée r) vue depuis le joueur
// propriétaire du secteur : s ∈ {0,1,2}, f ∈ 0..7 (a..h), r ∈ 0..3 (rangées 1..4).
// Index numérique : s*32 + r*8 + f. Nom textuel : `${s}${'abcdefgh'[f]}${r+1}` (ex. "0e2").
//
// Les directions sont exprimées dans le repère LOCAL de la case : (df, dr) avec
// dr = +1 « vers l'avant » (vers le centre pour le propriétaire du secteur) et
// df = +1 « vers la droite » (vers la colonne h).
//
// Franchir la rangée 4 (r = 3) vers l'avant fait passer dans un secteur voisin :
//  - colonnes a-d (f < 4) → secteur s-1, colonne 7-f, rangée 4 ;
//  - colonnes e-h (f ≥ 4) → secteur s+1, colonne 7-f, rangée 4.
// Le repère du secteur d'arrivée est tourné de 180° : (df, dr) devient (-df, -dr).
//
// Les diagonales sont définies comme la composition de deux pas orthogonaux, dans les
// deux ordres possibles. Partout les deux ordres donnent la même case, sauf autour du
// point central (où 6 cases se touchent) : la diagonale se dédouble alors en deux cases.

export const FILES = 'abcdefgh';
export const NUM_CELLS = 96;
export const NUM_PLAYERS = 3;

export type Vec = readonly [number, number];

/** Les 8 directions locales. Indices 0-3 : orthogonales, 4-7 : diagonales. */
export const DIRS: readonly Vec[] = [
  [0, 1], // avant
  [0, -1], // arrière
  [1, 0], // droite
  [-1, 0], // gauche
  [1, 1], // avant-droite
  [-1, 1], // avant-gauche
  [1, -1], // arrière-droite
  [-1, -1], // arrière-gauche
];

export function dirIndex(df: number, dr: number): number {
  for (let i = 0; i < 8; i++) if (DIRS[i][0] === df && DIRS[i][1] === dr) return i;
  throw new Error(`direction invalide ${df},${dr}`);
}

/** Indice de la direction opposée. */
export const OPPOSITE: readonly number[] = DIRS.map(([df, dr]) => dirIndex(-df, -dr));

export interface Step {
  /** Case d'arrivée (index). */
  to: number;
  /** Vrai si le pas change de repère (rotation de 180°). */
  flip: boolean;
}

export function cellIndex(sector: number, file: number, rank: number): number {
  return sector * 32 + rank * 8 + file;
}
export function sectorOf(c: number): number {
  return Math.floor(c / 32);
}
export function rankOf(c: number): number {
  return Math.floor((c % 32) / 8);
}
export function fileOf(c: number): number {
  return c % 8;
}

export function cellName(c: number): string {
  if (!Number.isInteger(c) || c < 0 || c >= NUM_CELLS) throw new Error(`case invalide : ${c}`);
  return `${sectorOf(c)}${FILES[fileOf(c)]}${rankOf(c) + 1}`;
}

export function parseCell(name: string): number {
  const m = /^([0-2])([a-h])([1-4])$/.exec(name);
  if (!m) throw new Error(`nom de case invalide : ${name}`);
  return cellIndex(Number(m[1]), FILES.indexOf(m[2]), Number(m[3]) - 1);
}

/** Un pas orthogonal élémentaire dans le repère local de la case. */
function orthStep(c: number, df: number, dr: number): Step | null {
  const s = sectorOf(c);
  const f = fileOf(c);
  const r = rankOf(c);
  if (dr === 0) {
    const nf = f + df;
    if (nf < 0 || nf > 7) return null;
    return { to: cellIndex(s, nf, r), flip: false };
  }
  if (dr === -1) {
    if (r === 0) return null;
    return { to: cellIndex(s, f, r - 1), flip: false };
  }
  // dr === +1
  if (r < 3) return { to: cellIndex(s, f, r + 1), flip: false };
  const ns = f < 4 ? (s + 2) % 3 : (s + 1) % 3;
  return { to: cellIndex(ns, 7 - f, 3), flip: true };
}

/**
 * Applique une suite de vecteurs orthogonaux unitaires exprimés dans le repère de
 * départ, en suivant les changements de repère. Renvoie la case finale et le
 * changement de repère cumulé, ou null si l'on sort du plateau.
 */
function walk(c: number, seq: readonly Vec[]): Step | null {
  let cur = c;
  let flip = false;
  for (const [df, dr] of seq) {
    const sign = flip ? -1 : 1;
    const st = orthStep(cur, sign * df, sign * dr);
    if (!st) return null;
    cur = st.to;
    flip = flip !== st.flip;
  }
  return { to: cur, flip };
}

function pushUnique(list: Step[], st: Step | null): void {
  if (!st) return;
  if (!list.some((x) => x.to === st.to && x.flip === st.flip)) list.push(st);
}

function buildNeighbors(): Step[][][] {
  const out: Step[][][] = [];
  for (let c = 0; c < NUM_CELLS; c++) {
    const row: Step[][] = [];
    for (let d = 0; d < 8; d++) {
      const [df, dr] = DIRS[d];
      const list: Step[] = [];
      if (df === 0 || dr === 0) {
        pushUnique(list, walk(c, [[df, dr]]));
      } else {
        pushUnique(list, walk(c, [[df, 0], [0, dr]]));
        pushUnique(list, walk(c, [[0, dr], [df, 0]]));
      }
      row.push(list);
    }
    out.push(row);
  }
  return out;
}

/** NEIGHBORS[case][direction] = liste (0, 1 ou 2) des pas possibles. */
export const NEIGHBORS: readonly (readonly (readonly Step[])[])[] = buildNeighbors();

/** Cases adjacentes (8 directions, diagonales dédoublées incluses) : déplacements du roi. */
export const KING_ADJ: readonly (readonly number[])[] = NEIGHBORS.map((row) => {
  const set = new Set<number>();
  for (const list of row) for (const st of list) set.add(st.to);
  return [...set].sort((a, b) => a - b);
});

/** Sauts du cavalier : deux pas dans une direction orthogonale et un pas perpendiculaire, dans tous les ordres. */
export const KNIGHT_ADJ: readonly (readonly number[])[] = (() => {
  const ortho: Vec[] = [[0, 1], [0, -1], [1, 0], [-1, 0]];
  const out: number[][] = [];
  for (let c = 0; c < NUM_CELLS; c++) {
    const set = new Set<number>();
    for (const D of ortho) {
      for (const P of ortho) {
        if (D[0] * P[0] + D[1] * P[1] !== 0) continue;
        for (const seq of [[D, D, P], [D, P, D], [P, D, D]] as Vec[][]) {
          const st = walk(c, seq);
          if (st) set.add(st.to);
        }
      }
    }
    set.delete(c);
    for (const k of KING_ADJ[c]) set.delete(k);
    out.push([...set].sort((a, b) => a - b));
  }
  return out;
})();

/** Direction « avant » d'un pion du joueur `owner` sur la case c (indice dans DIRS). */
export function pawnForwardDir(owner: number, c: number): number {
  return sectorOf(c) === owner ? 0 : 1;
}

/** Cases attaquées (prises possibles) par un pion de `owner` situé en c. */
export const PAWN_CAPTURES: readonly (readonly (readonly number[])[])[] = [0, 1, 2].map((owner) => {
  const out: number[][] = [];
  for (let c = 0; c < NUM_CELLS; c++) {
    const fwd = pawnForwardDir(owner, c);
    const dr = DIRS[fwd][1];
    const set = new Set<number>();
    for (const df of [-1, 1]) for (const st of NEIGHBORS[c][dirIndex(df, dr)]) set.add(st.to);
    out.push([...set].sort((a, b) => a - b));
  }
  return out;
});

/** Recherche inverse : PAWN_ATTACKERS[owner][x] = cases d'où un pion de owner attaque x. */
export const PAWN_ATTACKERS: readonly (readonly (readonly number[])[])[] = PAWN_CAPTURES.map((table) => {
  const out: number[][] = Array.from({ length: NUM_CELLS }, () => []);
  table.forEach((targets, from) => {
    for (const t of targets) out[t].push(from);
  });
  return out;
});

/** Case d'avance simple d'un pion de owner en c (-1 si aucune). */
export const PAWN_PUSH: readonly (readonly number[])[] = [0, 1, 2].map((owner) => {
  const out: number[] = [];
  for (let c = 0; c < NUM_CELLS; c++) {
    const list = NEIGHBORS[c][pawnForwardDir(owner, c)];
    out.push(list.length ? list[0].to : -1);
  }
  return out;
});

function buildRays(): number[][][][] {
  const out: number[][][][] = [];
  for (let c = 0; c < NUM_CELLS; c++) {
    const row: number[][][] = [];
    for (let d = 0; d < 8; d++) {
      const paths: number[][] = [];
      const extend = (cell: number, dir: number, path: number[]) => {
        const next = NEIGHBORS[cell][dir].filter((st) => st.to !== c && !path.includes(st.to));
        if (next.length === 0) {
          if (path.length) paths.push(path);
          return;
        }
        for (const st of next) extend(st.to, st.flip ? OPPOSITE[dir] : dir, [...path, st.to]);
      };
      extend(c, d, []);
      row.push(paths);
    }
    out.push(row);
  }
  return out;
}

/**
 * RAYS[case][direction] = liste des chemins (suites de cases) d'une pièce glissante.
 * Il y a un seul chemin, sauf quand le rayon traverse le centre et se dédouble : il y en
 * a alors deux, qui partagent leur début.
 */
export const RAYS: readonly (readonly (readonly number[])[])[][] = buildRays();

/**
 * Parcourt les rayons d'une pièce glissante depuis `from` dans la direction `d`.
 * `visit(case)` est appelé une fois par case atteinte ; s'il renvoie false, le rayon
 * s'arrête (case occupée).
 */
export function walkRay(from: number, d: number, visit: (c: number) => boolean): void {
  const seen = new Map<number, boolean>();
  for (const path of RAYS[from][d]) {
    for (const c of path) {
      let cont = seen.get(c);
      if (cont === undefined) {
        cont = visit(c);
        seen.set(c, cont);
      }
      if (!cont) break;
    }
  }
}

/** Rotation d'un joueur : case correspondante dans le secteur (s + k) mod 3. */
export function rotateCell(c: number, k: number): number {
  return cellIndex((sectorOf(c) + k) % 3, fileOf(c), rankOf(c));
}
