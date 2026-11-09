// Géométrie de rendu du plateau ROND (144 cases), pour que le client n'ait rien à recalculer.
//
// Repère normalisé : x vers la droite, y vers le BAS, disque de centre (0.5, 0.5) et de
// rayon 0.5. Angles en degrés, sens trigonométrique VU À L'ÉCRAN :
// x = 0.5 + ρ·cos(a), y = 0.5 − ρ·sin(a) (0° à droite, 90° en haut, 270° en bas).
//
// - 24 colonnes radiales (secteurs de 15°) × 6 anneaux ; anneau 1 = extérieur.
// - Équipe 0 en bas (210°–330°), équipe 1 en haut à gauche (90°–210°), équipe 2 en haut à
//   droite (330°–90°) ; colonnes a → h dans le sens trigonométrique.
// - Médaillon central (≈ 20 % du rayon) : traversable, pas une case.
// - Les anneaux s'amincissent vers le centre (mélange progression linéaire / géométrique)
//   pour garder des cases à peu près carrées sans rendre les anneaux intérieurs minuscules.

import { NUM_CELLS, NUM_RINGS, TEAM_START_WEDGE, cellName, fileOf, isLight, ringOf, teamOf, wedgeOf } from './board.ts';
import type { Player } from './types.ts';

export type Point = [number, number];

/** Rayon du médaillon central (fraction du rayon du disque). */
export const MEDALLION_RADIUS = 0.2;

/** Rayons des bords d'anneaux (fraction du rayon du disque), de l'extérieur (1) au médaillon. */
export const RING_RADII: readonly number[] = (() => {
  const span = 1 - MEDALLION_RADIUS;
  const q = Math.pow(MEDALLION_RADIUS, 1 / NUM_RINGS);
  const widths: number[] = [];
  for (let k = 0; k < NUM_RINGS; k++) {
    const geo = Math.pow(q, k) * (1 - q); // progression géométrique
    widths.push(0.5 * geo + 0.5 * (span / NUM_RINGS));
  }
  const sum = widths.reduce((a, b) => a + b, 0);
  const radii = [1];
  for (const w of widths) radii.push(radii[radii.length - 1] - (w * span) / sum);
  radii[NUM_RINGS] = MEDALLION_RADIUS;
  return radii.map((r) => Math.round(r * 1e6) / 1e6);
})();

/** Points par arc dans les polygones. */
export const ARC_POINTS = 8;
const R = 0.5;

/** Angle (degrés) du début de l'arc de l'équipe s (bord de sa colonne a). */
export function sectorStartAngle(s: number): number {
  return TEAM_START_WEDGE[s] * 15;
}

/** Colonne absolue 0..23 de la colonne f de l'équipe s. */
export function angularSector(s: number, f: number): number {
  return (TEAM_START_WEDGE[s] + f) % 24;
}

export interface RoundCellGeometry {
  id: string;
  index: number;
  sector: Player;
  file: number;
  /** Anneau 1..6 (1 = extérieur). `rank` est conservé comme alias. */
  ring: number;
  rank: number;
  /** Colonne absolue 0..23 (secteur angulaire [15k, 15k+15]). */
  wedge: number;
  /** Angle du centre de la case (degrés). */
  angle: number;
  a0: number;
  a1: number;
  /** Rayons intérieur et extérieur (coordonnées normalisées). */
  r0: number;
  r1: number;
  x: number;
  y: number;
  /** Secteur annulaire : arc extérieur de a0 à a1, puis arc intérieur de a1 à a0. */
  polygon: Point[];
  light: boolean;
}

export interface SwordGeometry {
  /** Frontière b : bord de la colonne a de l'équipe b. */
  border: number;
  /** Les deux équipes séparées (équipe b, puis sa voisine côté colonne a). */
  teams: [Player, Player];
  /** Angle de la ligne frontière (degrés). */
  angle: number;
  /** Poignée : anneau 1 (rayons normalisés). */
  hilt: { r0: number; r1: number; x: number; y: number };
  /** Lame : anneaux 2 et 3. */
  blade: { r0: number; r1: number; x: number; y: number };
}

const round = (n: number) => Math.round(n * 1e9) / 1e9;
function polar(rho: number, deg: number): Point {
  const a = (deg * Math.PI) / 180;
  return [round(0.5 + rho * Math.cos(a)), round(0.5 - rho * Math.sin(a))];
}

let cache: RoundCellGeometry[] | null = null;

/** Géométrie circulaire des 144 cases, dans l'ordre des index. */
export function roundBoardCells(): RoundCellGeometry[] {
  if (!cache) {
    cache = [];
    for (let c = 0; c < NUM_CELLS; c++) {
      const r = ringOf(c);
      const wedge = wedgeOf(c);
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
        sector: teamOf(c) as Player,
        file: fileOf(c),
        ring: r + 1,
        rank: r + 1,
        wedge,
        angle,
        a0,
        a1,
        r0: round(r0),
        r1: round(r1),
        x,
        y,
        polygon: poly,
        light: isLight(c),
      });
    }
  }
  return cache.map((g) => ({ ...g, polygon: g.polygon.map((p) => [p[0], p[1]] as Point) }));
}

/** Les 3 épées (poignée sur l'anneau 1, lame sur les anneaux 2-3) posées sur les frontières. */
export function swordGeometry(): SwordGeometry[] {
  return [0, 1, 2].map((b) => {
    const angle = sectorStartAngle(b);
    const prev = (TEAM_START_WEDGE[b] + 23) % 24;
    const other = [0, 1, 2].find((s) => s !== b && (prev - TEAM_START_WEDGE[s] + 24) % 24 < 8)! as Player;
    const hr1 = R * RING_RADII[0];
    const hr0 = R * RING_RADII[1];
    const br1 = R * RING_RADII[1];
    const br0 = R * RING_RADII[3];
    const [hx, hy] = polar((hr0 + hr1) / 2, angle);
    const [bx, by] = polar((br0 + br1) / 2, angle);
    return {
      border: b,
      teams: [b as Player, other],
      angle,
      hilt: { r0: round(hr0), r1: round(hr1), x: hx, y: hy },
      blade: { r0: round(br0), r1: round(br1), x: bx, y: by },
    };
  });
}

/** Contour du disque (n points), en coordonnées normalisées. */
export function roundOutline(n = 96): Point[] {
  return Array.from({ length: n }, (_, i) => polar(R, (360 * i) / n));
}
