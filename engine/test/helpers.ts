import type { GameState, Move } from '../src/index.ts';
import { legalMoves } from '../src/index.ts';

/** Cases d'arrivée des coups légaux depuis `from`, triées. */
export function targets(state: GameState, from: string): string[] {
  return legalMoves(state)
    .filter((m) => m.from === from)
    .map((m) => m.to)
    .sort();
}

export function mv(from: string, to: string): Move {
  return { from, to };
}

/** Générateur pseudo-aléatoire déterministe (mulberry32). */
export function rngFrom(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export const sorted = (xs: string[]) => [...xs].sort();
