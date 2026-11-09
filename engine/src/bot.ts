// Joueurs artificiels (bots). Purs et déterministes : le hasard passe par un rng injectable.
// Chaque niveau a un budget de TEMPS CPU (8 ms par défaut, pour tenir dans la limite de ~10 ms
// par invocation de l'offre Workers gratuite) et une profondeur maximale. Le temps est mesuré
// avec une horloge injectable (performance.now par défaut) ; comme l'horloge d'un Worker peut
// rester figée pendant un calcul synchrone, un plafond de nœuds proportionnel au budget sert de
// garde-fou. Dans tous les cas un coup légal est rendu (repli : difficile → meilleur coup connu,
// moyen → facile).
import { applyInternal, attacks, legalInternal, toPublic } from './rules.ts';
import type { IMove } from './rules.ts';
import { KING_ATTACKERS, KNIGHT_ATTACKERS, NUM_CELLS, NUM_DIRS, PAWN_ATTACKERS, RAYS, ringOf } from './board.ts';
import type { GameState, Move, Piece, PieceType, Player } from './types.ts';

export type BotLevel = 'facile' | 'moyen' | 'difficile';
export const BOT_LEVELS: readonly BotLevel[] = ['facile', 'moyen', 'difficile'];

export interface BotOptions {
  /** Réel dans [0, 1). Par défaut Math.random. */
  rng?: () => number;
  /** Budget de temps CPU (ms). Par défaut celui du profil du niveau. */
  timeBudgetMs?: number;
  /** Horloge en ms (par défaut performance.now, sinon Date.now). */
  now?: () => number;
  /** Profondeur maximale (par défaut celle du profil). */
  maxDepth?: number;
  /** Plafond de nœuds explicite (tests) ; par défaut proportionnel au budget de temps. */
  maxNodes?: number;
}

export interface LevelProfile {
  /** Budget de temps CPU par coup (ms). */
  budgetMs: number;
  /** Profondeur de recherche maximale (demi-coups). */
  maxDepth: number;
}

/** Budget CPU par défaut d'un coup de bot (ms) ; le serveur le règle via BOT_CPU_MS. */
export const DEFAULT_BOT_CPU_MS = 8;

/** Profils des niveaux : budget de temps (plafonné au budget CPU global) + profondeur max. */
export const LEVEL_PROFILES: Record<BotLevel, LevelProfile> = {
  facile: { budgetMs: 2, maxDepth: 1 },
  moyen: { budgetMs: DEFAULT_BOT_CPU_MS, maxDepth: 1 },
  difficile: { budgetMs: DEFAULT_BOT_CPU_MS, maxDepth: 3 },
};

/**
 * Garde-fou si l'horloge ne bouge pas : nœuds autorisés par ms de budget
 * (~45 µs par nœud sur le plateau de 144 cases, génération + évaluation comprises).
 */
export const NODES_PER_MS = 20;

export interface BotDecision {
  move: Move;
  /** Positions générées (appels à applyMove). */
  nodes: number;
  /** Profondeur entièrement explorée (difficile), 1 sinon. */
  depth: number;
  /** Évaluation du coup choisi, du point de vue du bot (centipions). */
  score: number;
  /** Vrai si le budget a été atteint (recherche écourtée ou repli). */
  cutoff?: boolean;
}

const defaultClock: () => number =
  typeof performance !== 'undefined' && typeof performance.now === 'function' ? () => performance.now() : () => Date.now();

/** Budget d'un coup : temps écoulé et nombre de nœuds. */
class Budget {
  nodes = 0;
  private start: number;
  private now: () => number;
  private ms: number;
  private maxNodes: number;
  constructor(ms: number, maxNodes: number, now: () => number) {
    this.now = now;
    this.ms = ms;
    this.maxNodes = maxNodes;
    this.start = now();
  }
  /** Vrai si le budget est épuisé (vérifié avant chaque nouvelle position). */
  get exhausted(): boolean {
    return this.nodes >= this.maxNodes || this.now() - this.start >= this.ms;
  }
  get elapsed(): number {
    return this.now() - this.start;
  }
}

const VAL: Record<PieceType, number> = { P: 100, N: 300, B: 320, R: 500, Q: 900, K: 0 };
const WIN = 1_000_000;
const ELIM_BONUS = 1500;
const PLAYERS: readonly Player[] = [0, 1, 2];

type Board = (Piece | null)[];

// ---------------------------------------------------------------------------
// Évaluation
// ---------------------------------------------------------------------------

/** Prendre un roi « emprisonné » élimine son équipe. */
const KING_TAKE = 5000;

/** Valeur d'une pièce pour le preneur : une pièce gelée ne vaut rien. */
function victimValue(state: GameState, pc: Piece | null): number {
  if (!pc || !state.active[pc.owner]) return 0;
  return pc.type === 'K' ? KING_TAKE : VAL[pc.type];
}

/** Nombre approximatif de cases accessibles (sans allocation ni test de légalité). */
function mobility(b: Board, p: Player): number {
  let n = 0;
  for (let c = 0; c < NUM_CELLS; c++) {
    const pc = b[c];
    if (pc === null || pc.owner !== p) continue;
    switch (pc.type) {
      case 'P':
      case 'K':
        break;
      case 'N':
        for (const y of KNIGHT_ATTACKERS[c]) {
          const t = b[y];
          if (t === null || t.owner !== p) n++;
        }
        break;
      default: {
        const d0 = pc.type === 'B' ? 4 : 0;
        const d1 = pc.type === 'R' ? 4 : 8;
        for (let d = d0; d < d1; d++) {
          const ray = RAYS[c * NUM_DIRS + d];
          const cells = ray.cells;
          // Les longues horizontales comptent peu : on plafonne chaque rayon à 6 cases.
          const lim = Math.min(cells.length, 6);
          for (let i = 0; i < lim; i++) {
            if (ray.hilt[i] !== 0) break;
            const t = b[cells[i]];
            if (t === null) n++;
            else {
              if (t.owner !== p) n++;
              break;
            }
          }
        }
      }
    }
  }
  return n;
}

/** Force d'un joueur actif : matériel, avance des pions, mobilité, sécurité du roi. */
function strength(state: GameState, p: Player, full: boolean): number {
  const b = state.board;
  let s = 0;
  let k = -1;
  for (let c = 0; c < NUM_CELLS; c++) {
    const pc = b[c];
    if (pc === null || pc.owner !== p) continue;
    s += VAL[pc.type];
    if (pc.type === 'K') k = c;
    if (pc.type === 'P') {
      // Avant le centre : anneaux 2 → 6 ; après : vers l'anneau 1 (promotion).
      const r = ringOf(c);
      s += pc.crossed ? 40 + (5 - r) * 14 : (r - 1) * 6;
    }
  }
  // Mobilité (coups pseudo-légaux) : peu coûteuse, et symétrique entre joueurs.
  s += 2 * mobility(b, p);
  // Sécurité du roi : bouclier de pièces amies, cases voisines attaquées (pour le bot
  // lui-même seulement : c'est coûteux), échec.
  if (k >= 0) {
    let shield = 0;
    let danger = 0;
    for (const y of KING_ATTACKERS[k]) {
      const pc = b[y];
      if (pc !== null && pc.owner === p) shield++;
      else if (full) for (const q of PLAYERS) if (q !== p && state.active[q] && attacks(b, y, q)) danger++;
    }
    s += 10 * Math.min(shield, 4) - 8 * danger;
    for (const q of PLAYERS) if (q !== p && state.active[q] && attacks(b, k, q)) s -= 40;
  }
  return s;
}

/** Score terminal ou statique du point de vue de `me` (paranoïaque : moi contre les deux autres). */
function evaluate(state: GameState, me: Player, ply: number): number {
  const r = state.result;
  if (r) return r.winner === null ? 0 : r.winner === me ? WIN - ply : -WIN + ply;
  if (!state.active[me]) return -WIN + ply;
  let v = strength(state, me, true);
  for (const q of PLAYERS) {
    if (q === me) continue;
    if (state.active[q]) v -= strength(state, q, false) / 2;
    else v += ELIM_BONUS;
  }
  return v;
}

/** Plus petite valeur d'une pièce de `by` (actif) qui attaque x, ou Infinity. */
function leastAttacker(b: Board, x: number, by: Player): number {
  let best = Infinity;
  for (let cr = 0; cr < 2; cr++) {
    for (const y of PAWN_ATTACKERS[cr][x]) {
      const pc = b[y];
      if (pc && pc.owner === by && pc.type === 'P' && (pc.crossed ? 1 : 0) === cr) return VAL.P;
    }
  }
  for (const y of KNIGHT_ATTACKERS[x]) {
    const pc = b[y];
    if (pc && pc.owner === by && pc.type === 'N') best = Math.min(best, VAL.N);
  }
  for (let d = 0; d < NUM_DIRS; d++) {
    const slider = d < 4 ? 'R' : 'B';
    const ray = RAYS[x * NUM_DIRS + d];
    const cells = ray.cells;
    for (let i = 0; i < cells.length; i++) {
      if (ray.hilt[i] !== 0) break;
      const pc = b[cells[i]];
      if (pc === null) continue;
      if (pc.owner === by && (pc.type === slider || pc.type === 'Q')) best = Math.min(best, VAL[pc.type]);
      break;
    }
  }
  if (best === Infinity) {
    for (const y of KING_ATTACKERS[x]) {
      const pc = b[y];
      if (pc && pc.owner === by && pc.type === 'K') return 2000;
    }
  }
  return best;
}

/**
 * Meilleur gain matériel immédiat de l'adversaire `opp` contre les pièces de `me`
 * (échange statique simplifié : pièce non défendue, ou défendue mais attaquée par moins cher).
 */
function threatBy(state: GameState, me: Player, opp: Player): number {
  const b = state.board;
  let best = 0;
  for (let c = 0; c < NUM_CELLS; c++) {
    const pc = b[c];
    if (pc === null || pc.owner !== me) continue;
    const att = leastAttacker(b, c, opp);
    if (att === Infinity) continue;
    if (pc.type === 'K') {
      // Roi attaqué hors de son tour : l'adversaire peut le capturer (roi emprisonné).
      best = Math.max(best, KING_TAKE);
      continue;
    }
    const v = VAL[pc.type];
    const gain = attacks(b, c, me) ? v - att : v;
    if (gain > best) best = gain;
  }
  return best;
}

// ---------------------------------------------------------------------------
// Niveaux
// ---------------------------------------------------------------------------

function shuffled<T>(xs: readonly T[], rng: () => number): T[] {
  const a = xs.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.min(i, Math.floor(rng() * (i + 1)));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

/** Facile : coup aléatoire, mais prend une pièce gratuite une fois sur deux. */
function easy(state: GameState, moves: IMove[], rng: () => number, budget: Budget): BotDecision {
  const me = state.turn;
  let nodes = 0;
  if (rng() < 0.5) {
    let best: IMove | null = null;
    let bestGain = 0;
    for (const m of moves) {
      if (!m.capture) continue;
      const victim = victimValue(state, state.board[m.to]);
      if (victim === 0) continue;
      if (budget.exhausted) break;
      const after = applyInternal(state, m);
      budget.nodes++;
      nodes++;
      let defended = false;
      for (const q of PLAYERS) if (q !== me && after.active[q] && attacks(after.board, m.to, q)) defended = true;
      const gain = defended ? victim - VAL[state.board[m.from]!.type] : victim;
      if (gain > bestGain) {
        bestGain = gain;
        best = m;
      }
    }
    if (best) return { move: toPublic(best), nodes, depth: 1, score: bestGain };
  }
  let i = Math.floor(rng() * moves.length);
  if (!(i >= 0)) i = 0;
  if (i >= moves.length) i = moves.length - 1;
  return { move: toPublic(moves[i]), nodes, depth: 1, score: 0 };
}

/** Moyen : un coup, puis menaces de prise des deux adversaires ; évite de laisser une pièce en prise. */
function medium(state: GameState, moves: IMove[], rng: () => number, budget: Budget): BotDecision {
  const me = state.turn;
  let best: IMove | null = null;
  let bestScore = -Infinity;
  let nodes = 0;
  let cutoff = false;
  // Les prises d'abord : si le budget coupe, le meilleur coup partiel reste sensé.
  const ordered = shuffled(moves, rng).sort((a, b) => Number(b.capture) - Number(a.capture));
  for (const m of ordered) {
    if (budget.exhausted) {
      cutoff = true;
      break;
    }
    const after = applyInternal(state, m);
    budget.nodes++;
    nodes++;
    let score: number;
    if (after.result || !after.active[me]) {
      score = evaluate(after, me, 1);
    } else {
      score = evaluate(after, me, 1);
      const threats: number[] = [];
      for (const q of PLAYERS) if (q !== me && after.active[q]) threats.push(threatBy(after, me, q));
      threats.sort((a, b) => b - a);
      // Le prochain adversaire prend la meilleure pièce, l'autre peut-être une seconde.
      score -= (threats[0] ?? 0) * 0.9 + (threats[1] ?? 0) * 0.3;
      score += rng() * 6;
    }
    if (score > bestScore) {
      bestScore = score;
      best = m;
    }
  }
  // Repli garanti : rien d'évalué dans le budget → niveau facile.
  if (best === null) return { ...easy(state, moves, rng, budget), cutoff: true };
  return { move: toPublic(best), nodes, depth: 1, score: Math.round(bestScore), cutoff };
}

// ---------------------------------------------------------------------------
// Difficile : recherche paranoïaque alpha-bêta + quiescence + table de positions
// ---------------------------------------------------------------------------

const ABORT = Symbol('budget');

// Clés de Zobrist (32 bits × 2) générées par un PRNG fixe : déterministes.
const ZOB: Int32Array = (() => {
  let a = 0x9e3779b9;
  const next = () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return t ^ (t >>> 14);
  };
  const out = new Int32Array(NUM_CELLS * 21 * 2 + 32);
  for (let i = 0; i < out.length; i++) out[i] = next();
  return out;
})();
const TYPE_IDX: Record<PieceType, number> = { K: 0, Q: 1, R: 2, B: 3, N: 4, P: 5 };

function hashState(s: GameState): number {
  let h1 = 0;
  let h2 = 0;
  const b = s.board;
  for (let c = 0; c < NUM_CELLS; c++) {
    const pc = b[c];
    if (pc === null) continue;
    const t = pc.crossed ? 6 : TYPE_IDX[pc.type];
    const k = ((c * 21 + pc.owner * 7 + t) << 1) | 0;
    h1 ^= ZOB[k];
    h2 ^= ZOB[k + 1];
  }
  const base = NUM_CELLS * 42;
  h1 ^= ZOB[base + s.turn];
  for (const p of PLAYERS) if (s.active[p]) h2 ^= ZOB[base + 4 + p];
  for (const p of PLAYERS) {
    if (s.castling[p].king) h1 ^= ZOB[base + 8 + p];
    if (s.castling[p].queen) h2 ^= ZOB[base + 11 + p];
    if (s.hilts[p]) h1 ^= ZOB[base + 14 + p];
  }
  for (const e of s.enPassant) h2 ^= ZOB[base + 17 + (e.target.charCodeAt(0) - 48)] ^ ZOB[base + 20 + (e.target.charCodeAt(1) & 7)];
  return (h1 >>> 0) * 2097152 + (h2 >>> 11);
}

interface TTEntry {
  depth: number;
  value: number;
  flag: 0 | 1 | 2; // 0 exact, 1 borne basse, 2 borne haute
  best: number; // index (from*144+to) du meilleur coup, -1 sinon
}

const moveKey = (m: IMove) => m.from * NUM_CELLS + m.to;

class Searcher {
  private tt = new Map<number, TTEntry>();
  private me: Player;
  private budget: Budget;
  /** Heuristique d'historique (par joueur) et coups « tueurs » (par ply). */
  private history = PLAYERS.map(() => new Float64Array(NUM_CELLS * NUM_CELLS));
  private killers: number[][] = Array.from({ length: 16 }, () => [-1, -1]);

  constructor(me: Player, budget: Budget) {
    this.me = me;
    this.budget = budget;
  }

  get nodes(): number {
    return this.budget.nodes;
  }

  child(s: GameState, m: IMove): GameState {
    if (this.budget.exhausted) throw ABORT;
    this.budget.nodes++;
    return applyInternal(s, m);
  }

  /** Ordonnancement : coup de la table, prises MVV-LVA, promotions, puis coups calmes. */
  order(s: GameState, moves: readonly IMove[], ttBest: number, ply = -1): IMove[] {
    const killers = ply >= 0 ? this.killers[ply] : undefined;
    const hist = this.history[s.turn];
    const scored = moves.map((m) => {
      const mk = moveKey(m);
      let k = 0;
      if (mk === ttBest) k = 1e9;
      else {
        if (killers && (killers[0] === mk || killers[1] === mk)) k += 5e5;
        k += Math.min(hist[mk], 4e5);
        if (m.capture) {
          const victim = s.board[m.to];
          const v = victimValue(s, victim);
          // Pour un adversaire (paranoïaque), seules les prises de mes pièces sont prioritaires.
          if (v > 0 && (s.turn === this.me || victim!.owner === this.me)) k += 1e6 + v * 16 - VAL[s.board[m.from]!.type];
        }
        if (m.promo) k += 9e5;
      }
      return { m, k };
    });
    scored.sort((a, b) => b.k - a.k);
    return scored.map((x) => x.m);
  }

  search(s: GameState, depth: number, alpha: number, beta: number, ply: number): number {
    if (s.result || !s.active[this.me]) return evaluate(s, this.me, ply);
    if (depth <= 0) return this.quiesce(s, alpha, beta, ply, 3);
    const key = hashState(s);
    const e = this.tt.get(key);
    if (e && e.depth >= depth) {
      if (e.flag === 0) return e.value;
      if (e.flag === 1 && e.value >= beta) return e.value;
      if (e.flag === 2 && e.value <= alpha) return e.value;
    }
    const maximizing = s.turn === this.me;
    const a0 = alpha;
    const b0 = beta;
    let best = maximizing ? -Infinity : Infinity;
    let bestKey = -1;
    for (const m of this.order(s, legalInternal(s), e ? e.best : -1, ply)) {
      const v = this.search(this.child(s, m), depth - 1, alpha, beta, ply + 1);
      if (maximizing ? v > best : v < best) {
        best = v;
        bestKey = moveKey(m);
      }
      if (maximizing) alpha = Math.max(alpha, v);
      else beta = Math.min(beta, v);
      if (alpha >= beta) {
        const mk = moveKey(m);
        if (!m.capture) {
          this.history[s.turn][mk] += depth * depth;
          const kl = this.killers[ply];
          if (kl && kl[0] !== mk) {
            kl[1] = kl[0];
            kl[0] = mk;
          }
        }
        break;
      }
    }
    const flag: 0 | 1 | 2 = best <= a0 ? 2 : best >= b0 ? 1 : 0;
    this.tt.set(key, { depth, value: best, flag, best: bestKey });
    return best;
  }

  /** Quiescence légère : prises (et promotions) seulement, profondeur limitée. */
  quiesce(s: GameState, alpha: number, beta: number, ply: number, qd: number): number {
    if (s.result || !s.active[this.me]) return evaluate(s, this.me, ply);
    const stand = evaluate(s, this.me, ply);
    if (qd <= 0) return stand;
    const maximizing = s.turn === this.me;
    if (maximizing) {
      if (stand >= beta) return stand;
      alpha = Math.max(alpha, stand);
    } else {
      if (stand <= alpha) return stand;
      beta = Math.min(beta, stand);
    }
    let best = stand;
    const tactical = legalInternal(s).filter((m) => {
      if (m.promo) return true;
      if (!m.capture) return false;
      const victim = s.board[m.to]!;
      return victimValue(s, victim) > 0 && (maximizing || victim.owner === this.me);
    });
    for (const m of this.order(s, tactical, -1)) {
      const v = this.quiesce(this.child(s, m), alpha, beta, ply + 1, qd - 1);
      if (maximizing) {
        if (v > best) best = v;
        alpha = Math.max(alpha, v);
      } else {
        if (v < best) best = v;
        beta = Math.min(beta, v);
      }
      if (alpha >= beta) break;
    }
    return best;
  }
}

function hard(state: GameState, moves: IMove[], rng: () => number, budget: Budget, maxDepth: number): BotDecision {
  const me = state.turn;
  const S = new Searcher(me, budget);
  let cutoff = false;
  // Ordre de départ mélangé (départage aléatoire mais reproductible des coups équivalents).
  let rootOrder = S.order(state, shuffled(moves, rng), -1);
  let bestMove = rootOrder[0];
  let bestScore = -Infinity;
  let depthDone = 0;
  for (let depth = 1; depth <= maxDepth; depth++) {
    let iterBest: IMove | null = null;
    let iterScore = -Infinity;
    const scores = new Map<IMove, number>();
    try {
      let alpha = -Infinity;
      for (const m of rootOrder) {
        const v = S.search(S.child(state, m), depth - 1, alpha, Infinity, 1);
        scores.set(m, v);
        if (v > iterScore) {
          iterScore = v;
          iterBest = m;
        }
        alpha = Math.max(alpha, v);
      }
    } catch (e) {
      if (e !== ABORT) throw e;
      cutoff = true;
      // Itération incomplète : on garde son meilleur coup s'il bat celui de l'itération précédente
      // (le premier coup exploré est l'ancien meilleur, donc la comparaison est sûre).
      if (iterBest && depthDone > 0 && iterBest !== bestMove && iterScore > (scores.get(bestMove) ?? Infinity)) {
        bestMove = iterBest;
        bestScore = iterScore;
      } else if (depthDone === 0 && iterBest) {
        bestMove = iterBest;
        bestScore = iterScore;
      }
      break;
    }
    bestMove = iterBest!;
    bestScore = iterScore;
    depthDone = depth;
    // Mat trouvé : inutile de chercher plus loin.
    if (bestScore >= WIN - 10) break;
    rootOrder = [bestMove, ...rootOrder.filter((m) => m !== bestMove).sort((a, b) => (scores.get(b) ?? 0) - (scores.get(a) ?? 0))];
  }
  // bestMove est toujours un coup légal : au pire le premier de l'ordonnancement (meilleure prise).
  return { move: toPublic(bestMove), nodes: S.nodes, depth: Math.max(depthDone, 1), score: Math.round(bestScore), cutoff };
}

/** Choix détaillé du bot (coup, nœuds explorés, profondeur, score). */
export function botDecision(state: GameState, level: BotLevel, opts: BotOptions = {}): BotDecision {
  const moves = legalInternal(state);
  if (moves.length === 0) throw new Error('aucun coup légal');
  const rng = opts.rng ?? Math.random;
  if (moves.length === 1) return { move: toPublic(moves[0]), nodes: 0, depth: 1, score: 0 };
  const profile = LEVEL_PROFILES[level];
  if (!profile) throw new Error(`niveau inconnu : ${String(level)}`);
  const ms = Math.max(0.5, opts.timeBudgetMs !== undefined ? Math.min(opts.timeBudgetMs, level === 'facile' ? profile.budgetMs : Infinity) : profile.budgetMs);
  const budget = new Budget(ms, opts.maxNodes ?? Math.max(8, Math.floor(ms * NODES_PER_MS)), opts.now ?? defaultClock);
  switch (level) {
    case 'facile':
      return easy(state, moves, rng, budget);
    case 'moyen':
      return medium(state, moves, rng, budget);
    default:
      return hard(state, moves, rng, budget, opts.maxDepth ?? profile.maxDepth);
  }
}

/** Coup légal choisi par un bot du niveau donné pour le joueur au trait. */
export function botMove(state: GameState, level: BotLevel, opts: BotOptions = {}): Move {
  return botDecision(state, level, opts).move;
}

export function isBotLevel(v: unknown): v is BotLevel {
  return v === 'facile' || v === 'moyen' || v === 'difficile';
}
