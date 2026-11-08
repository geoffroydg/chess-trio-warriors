// Types publics du moteur. Tout l'état est sérialisable en JSON.

/** 0 = Blanc, 1 = Rouge, 2 = Noir. Ordre de jeu 0 → 1 → 2. */
export type Player = 0 | 1 | 2;

/** K roi, Q dame, R tour, B fou, N cavalier, P pion. */
export type PieceType = 'K' | 'Q' | 'R' | 'B' | 'N' | 'P';

export type Mode = 'firstMate' | 'twoMates';

export interface Piece {
  type: PieceType;
  owner: Player;
}

/** Coup : cases au format "<secteur><colonne><rangée>", ex. { from: "0e2", to: "0e4" }. */
export interface Move {
  from: string;
  to: string;
  /** Renseigné par legalMoves pour un roque ('king' = petit roque, 'queen' = grand roque). */
  castle?: 'king' | 'queen';
  /** Renseigné par legalMoves si le coup promeut un pion (toujours en dame). */
  promotion?: 'Q';
  /** Renseigné par legalMoves si le coup prend une pièce. */
  capture?: boolean;
}

export interface CastlingRights {
  king: boolean;
  queen: boolean;
}

export interface CheckInfo {
  /** Joueur dont le roi est attaqué. */
  player: Player;
  /** Adversaires actifs qui l'attaquent. */
  by: Player[];
}

export interface Elimination {
  player: Player;
  /** Joueur crédité du mat (null pour un abandon). */
  by: Player | null;
  reason: 'mate' | 'resign';
  /** Numéro du demi-coup (ply) au moment de l'élimination. */
  ply: number;
}

export type ResultReason =
  | 'mate' // firstMate : premier mat
  | 'lastStanding' // dernier joueur restant (mats et/ou abandons)
  | 'fiftyMoves'
  | 'repetition'
  | 'stalemate'; // plus aucun joueur actif ne peut jouer

export interface GameResult {
  /** Vainqueur, ou null pour une partie nulle. */
  winner: Player | null;
  reason: ResultReason;
}

export interface GameEvent {
  kind: 'move' | 'resign';
  /** Joueur qui a joué (ou abandonné). */
  player: Player;
  move?: { from: string; to: string };
  /** Type de la pièce déplacée (avant promotion). */
  piece?: PieceType;
  captured?: { type: PieceType; owner: Player; frozen: boolean; at: string } | null;
  promotion?: 'Q' | null;
  castle?: { side: 'king' | 'queen'; rookFrom: string; rookTo: string } | null;
  /** Rois en échec après le coup (et la résolution des mats/pats qui ont suivi). */
  checks: CheckInfo[];
  /** Mats constatés en début de tour à la suite de cet évènement. */
  mates: { player: Player; by: Player }[];
  /** Joueurs éliminés par cet évènement (mat en mode twoMates, ou abandon). */
  eliminated: Player[];
  /** Joueurs pats qui ont passé leur tour. */
  passes: Player[];
  /** Fin de partie provoquée par cet évènement. */
  gameOver: GameResult | null;
}

export interface GameState {
  version: 1;
  mode: Mode;
  /** 96 cases, index = secteur*32 + (rangée-1)*8 + colonne. */
  board: (Piece | null)[];
  /** Joueur au trait. */
  turn: Player;
  /** active[p] : le joueur p est encore en jeu. */
  active: [boolean, boolean, boolean];
  castling: [CastlingRights, CastlingRights, CastlingRights];
  /** Nombre de coups (demi-coups individuels) joués. */
  ply: number;
  /** Tours individuels (coups et passes) depuis la dernière prise ou le dernier mouvement de pion. */
  quietTurns: number;
  /** Ply du dernier coup de chaque joueur (-1 s'il n'a pas encore joué). */
  lastMoveAt: [number, number, number];
  /** Compteur d'occurrences des positions depuis le dernier coup irréversible. */
  repetitions: Record<string, number>;
  eliminations: Elimination[];
  result: GameResult | null;
  lastEvent: GameEvent | null;
}

export interface GameStatus {
  mode: Mode;
  over: boolean;
  result: GameResult | null;
  turn: Player | null;
  activePlayers: Player[];
  /** Le joueur au trait est-il en échec ? */
  inCheck: boolean;
  /** Tous les rois actifs actuellement attaqués. */
  checks: CheckInfo[];
  eliminations: Elimination[];
  ply: number;
  quietTurns: number;
  /** Seuil de la règle des 50 coups, en tours individuels (50 × joueurs actifs). */
  fiftyMoveLimit: number;
}
