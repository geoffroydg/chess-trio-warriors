// Géométrie de rendu du plateau hexagonal, pour que le client n'ait rien à recalculer.
//
// Repère écran normalisé : x vers la droite, y vers le BAS, hexagone régulier de
// centre (0.5, 0.5) et de rayon 0.5 (sommets à gauche et à droite). Le joueur 0 (Blanc)
// est en bas, le joueur 1 (Rouge) en haut à droite, le joueur 2 (Noir) en haut à gauche.
//
// L'hexagone est découpé en 6 quadrilatères (« cerfs-volants ») de 4×4 cases, chacun
// autour d'un sommet V_k. Le côté E_2p (de V_2p à V_2p+1) est la rangée 1 du joueur p ;
// la moitié a-d du joueur p est le cerf-volant de V_2p, la moitié e-h celui de V_2p+1.
// Les cases sont obtenues par interpolation bilinéaire dans chaque cerf-volant.

import { NUM_CELLS, cellName, fileOf, rankOf, sectorOf } from './topology.ts';
import type { Player } from './types.ts';

export type Point = [number, number];

export interface CellGeometry {
  /** Nom de la case, ex. "0e2". */
  id: string;
  /** Index interne (0..95) = secteur*32 + (rangée-1)*8 + colonne. */
  index: number;
  sector: Player;
  /** Colonne 0..7 (a..h). */
  file: number;
  /** Rangée 1..4. */
  rank: number;
  /** Centre de la case. */
  x: number;
  y: number;
  /** 4 sommets (sens : (f,r), (f+1,r), (f+1,r+1), (f,r+1) en coordonnées de grille). */
  polygon: [Point, Point, Point, Point];
  /** Couleur de case en damier (true = case claire). */
  light: boolean;
}

const R = 0.5;
const O: Point = [0.5, 0.5];

function vertex(k: number): Point {
  const a = ((240 + 60 * k) * Math.PI) / 180;
  return [0.5 + R * Math.cos(a), 0.5 - R * Math.sin(a)];
}
function mid(k: number): Point {
  const a = vertex(k);
  const b = vertex(k + 1);
  return [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
}
const mod6 = (k: number) => ((k % 6) + 6) % 6;

function bilerp(p00: Point, p10: Point, p01: Point, p11: Point, u: number, v: number): Point {
  const x = (1 - u) * (1 - v) * p00[0] + u * (1 - v) * p10[0] + (1 - u) * v * p01[0] + u * v * p11[0];
  const y = (1 - u) * (1 - v) * p00[1] + u * (1 - v) * p10[1] + (1 - u) * v * p01[1] + u * v * p11[1];
  return [round(x), round(y)];
}
const round = (n: number) => Math.round(n * 1e9) / 1e9;

/** Position (u = colonne 0..8, v = rangée 0..4) d'un point de grille du secteur p. */
function gridPoint(p: number, u: number, v: number): Point {
  if (u <= 4) {
    // Moitié a-d : cerf-volant du sommet V_2p.
    return bilerp(vertex(mod6(2 * p)), mid(mod6(2 * p)), mid(mod6(2 * p - 1)), O, u / 4, v / 4);
  }
  // Moitié e-h : cerf-volant du sommet V_2p+1, colonnes comptées depuis h.
  return bilerp(vertex(mod6(2 * p + 1)), mid(mod6(2 * p)), mid(mod6(2 * p + 1)), O, (8 - u) / 4, v / 4);
}

let cache: CellGeometry[] | null = null;

/** Géométrie des 96 cases, dans l'ordre des index. */
export function boardCells(): CellGeometry[] {
  if (!cache) {
    cache = [];
    for (let c = 0; c < NUM_CELLS; c++) {
      const s = sectorOf(c);
      const f = fileOf(c);
      const r = rankOf(c);
      // Les 4 sommets d'une case appartiennent tous à la même moitié (a-d : u ≤ 4, e-h : u ≥ 4).
      const pt = (u: number, v: number) => (f < 4 ? gridPoint(s, Math.min(u, 4), v) : gridPoint(s, Math.max(u, 4), v));
      const poly: [Point, Point, Point, Point] = [pt(f, r), pt(f + 1, r), pt(f + 1, r + 1), pt(f, r + 1)];
      const center = gridPoint(s, f + 0.5, r + 0.5);
      cache.push({
        id: cellName(c),
        index: c,
        sector: s as Player,
        file: f,
        rank: r + 1,
        x: center[0],
        y: center[1],
        polygon: poly,
        light: (f + r) % 2 === 1,
      });
    }
  }
  return cache.map((g) => ({ ...g, polygon: g.polygon.map((p) => [p[0], p[1]]) as CellGeometry['polygon'] }));
}

/** Sommets de l'hexagone (contour du plateau), en coordonnées normalisées. */
export function boardOutline(): Point[] {
  return [0, 1, 2, 3, 4, 5].map((k) => {
    const v = vertex(k);
    return [round(v[0]), round(v[1])];
  });
}
