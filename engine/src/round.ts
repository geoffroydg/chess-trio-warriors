// Géométrie de rendu du plateau ROND (même topologie de 96 cases que le plateau hexagonal).
//
// Repère normalisé : x vers la droite, y vers le BAS, disque de centre (0.5, 0.5) et de
// rayon 0.5. Les angles sont en degrés, sens trigonométrique VU À L'ÉCRAN :
// x = 0.5 + ρ·cos(a), y = 0.5 − ρ·sin(a) (0° à droite, 90° en haut, 270° en bas).
//
// - 24 secteurs angulaires de 15° ; chaque joueur occupe un arc de 120° (8 colonnes).
// - Rang → anneau : rangée 1 = anneau extérieur, rangée 4 = anneau intérieur, autour d'un
//   médaillon central qui n'est pas une case.
// - Colonnes a → h de la gauche vers la droite du propriétaire assis au bord face au centre,
//   c'est-à-dire dans le sens trigonométrique.
// - Le joueur 0 est en bas (arc 210°–330°), le joueur 2 en haut à droite (330°–90°), le
//   joueur 1 en haut à gauche (90°–210°) : l'ordre de jeu 0 → 1 → 2 tourne dans le sens
//   horaire. C'est le seul placement où chaque traversée du centre (rangée 4 → rangée 4)
//   mène au demi-secteur diamétralement opposé.
//
// Traversée du centre. La topologie relie la moitié a-d du joueur s à la moitié e-h du
// joueur s−1 en inversant l'ordre des colonnes (d↔e, c↔f, b↔g, a↔h) : c'est une symétrie
// par rapport au diamètre qui porte la frontière entre ces deux joueurs, et non une
// symétrie centrale. Une symétrie centrale exacte est impossible pour les trois paires de
// moitiés à la fois (elle conserve le sens de rotation alors que la topologie l'inverse ;
// avec trois joueurs le nombre de frontières est impair). Convention retenue : les deux
// cases reliées sont dans des demi-secteurs exactement opposés, et une colonne du milieu
// (d/e) se prolonge par une colonne du milieu, une colonne du bord (a/h) par une colonne du
// bord. L'écart à la case géométriquement opposée est de 45° (a, d, e, h) ou 15° (b, c, f, g).
//
// Enfin, h d'un joueur et a du joueur suivant sont côte à côte sur le disque mais ne sont
// PAS voisines (bord du plateau dans la topologie) : le rendu marque ces trois frontières.

import { NUM_CELLS, cellName, fileOf, rankOf, sectorOf } from './topology.ts';
import type { Player } from './types.ts';
import type { Point } from './geometry.ts';

/** Rayons des bords d'anneaux (fraction du rayon du disque), de l'extérieur vers le centre. */
export const RING_RADII: readonly number[] = [1, 0.83, 0.645, 0.44, 0.22];
/** Rayon du médaillon central (fraction du rayon du disque). */
export const MEDALLION_RADIUS = RING_RADII[4];
/** Points par arc dans les polygones. */
export const ARC_POINTS = 8;
const R = 0.5;

/** Angle (degrés, sens trigonométrique à l'écran) du début de l'arc du joueur s (colonne a). */
export function sectorStartAngle(s: number): number {
  return (((210 - 120 * s) % 360) + 360) % 360;
}

/** Secteur angulaire 0..23 (de 15°, à partir de 0°) de la colonne f du joueur s. */
export function angularSector(s: number, f: number): number {
  return (sectorStartAngle(s) / 15 + f) % 24;
}

export interface RoundCellGeometry {
  id: string;
  index: number;
  sector: Player;
  file: number;
  /** Rangée 1..4. */
  rank: number;
  /** Anneau 1..4 (1 = extérieur) : égal à la rangée. */
  ring: number;
  /** Secteur angulaire 0..23 (secteur k : angles [15k, 15k+15]). */
  wedge: number;
  /** Angle du centre de la case (degrés). */
  angle: number;
  /** Angles de début et de fin (degrés, a1 = a0 + 15, a0 dans [0, 360[). */
  a0: number;
  a1: number;
  /** Rayons intérieur et extérieur (coordonnées normalisées). */
  r0: number;
  r1: number;
  /** Centre de la case. */
  x: number;
  y: number;
  /** Secteur annulaire : arc extérieur de a0 à a1, puis arc intérieur de a1 à a0. */
  polygon: Point[];
  light: boolean;
}

const round = (n: number) => Math.round(n * 1e9) / 1e9;
function polar(rho: number, deg: number): Point {
  const a = (deg * Math.PI) / 180;
  return [round(0.5 + rho * Math.cos(a)), round(0.5 - rho * Math.sin(a))];
}

let cache: RoundCellGeometry[] | null = null;

/** Géométrie circulaire des 96 cases, dans l'ordre des index. */
export function roundBoardCells(): RoundCellGeometry[] {
  if (!cache) {
    cache = [];
    for (let c = 0; c < NUM_CELLS; c++) {
      const s = sectorOf(c);
      const f = fileOf(c);
      const r = rankOf(c);
      const wedge = angularSector(s, f);
      const a0 = wedge * 15;
      const a1 = a0 + 15;
      const r1 = R * RING_RADII[r];
      const r0 = R * RING_RADII[r + 1];
      const poly: Point[] = [];
      for (let i = 0; i < ARC_POINTS; i++) poly.push(polar(r1, a0 + ((a1 - a0) * i) / (ARC_POINTS - 1)));
      for (let i = 0; i < ARC_POINTS; i++) poly.push(polar(r0, a1 - ((a1 - a0) * i) / (ARC_POINTS - 1)));
      const angle = a0 + 7.5;
      const [x, y] = polar((r0 + r1) / 2, angle);
      cache.push({
        id: cellName(c),
        index: c,
        sector: s as Player,
        file: f,
        rank: r + 1,
        ring: r + 1,
        wedge,
        angle,
        a0,
        a1,
        r0: round(r0),
        r1: round(r1),
        x,
        y,
        polygon: poly,
        light: (f + r) % 2 === 1,
      });
    }
  }
  return cache.map((g) => ({ ...g, polygon: g.polygon.map((p) => [p[0], p[1]] as Point) }));
}

/** Contour du disque (n points), en coordonnées normalisées. */
export function roundOutline(n = 96): Point[] {
  return Array.from({ length: n }, (_, i) => polar(R, (360 * i) / n));
}
