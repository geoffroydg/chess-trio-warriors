// Types publics du moteur. Tout l'état est sérialisable en JSON.

/** 0 = Blanc, 1 = Gris, 2 = Noir. Ordre de jeu 0 → 1 → 2 (sens horaire sur le plateau). */
export type Player = 0 | 1 | 2;

/** K roi, Q dame, R tour, B fou, N cavalier, P pion. */
export type PieceType = 'K' | 'Q' | 'R' | 'B' | 'N' | 'P';

export type Mode = 'firstMate' | 'twoMates';

export interface Piece {
  type: PieceType;
  owner: Player;
  /** Pion ayant traversé le centre (il avance alors vers l'extérieur). Absent sinon. */
  crossed?: true;
}

/** Pièces de promotion (au choix). */
export type PromotionType = 'Q' | 'R' | 'B' | 'N';

/** Coup : cases au format "<équipe><colonne><anneau>", ex. { from: "0e2", to: "0e4" }. */
export interface Move {
  from: string;
  to: string;
  /** Renseigné par legalMoves pour un roque ('king' = petit roque côté a, 'queen' = grand roque côté h). */
  castle?: 'king' | 'queen';
  /**
   * Promotion : legalMoves renvoie une variante par pièce possible (Q, R, B, N). À l'envoi,
   * absent = dame.
   */
  promotion?: PromotionType;
  /** Renseigné par legalMoves si le coup prend une pièce. */
  capture?: boolean;
  /** Renseigné par legalMoves pour une prise en passant. */
  enPassant?: boolean;
}

/** Droit de prise en passant ouvert par une avance de deux cases. */
export interface EnPassant {
  /** Case sautée (où le preneur arrive). */
  target: string;
  /** Case du pion qui a avancé de deux cases. */
  pawn: string;
  owner: Player;
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
  /** mate : mat ou roi emprisonné capturé ; blocked : aucune équipe ne pouvait jouer. */
  reason: 'mate' | 'resign' | 'blocked';
  /** Numéro du demi-coup (ply) au moment de l'élimination. */
  ply: number;
}

export type ResultReason =
  | 'mate' // firstMate : premier mat (ou roi emprisonné capturé)
  | 'blockade' // firstMate : aucune équipe ne peut jouer, l'équipe au trait perd
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
  promotion?: PromotionType | null;
  /** Le coup a traversé le médaillon central. */
  crossedCenter?: boolean;
  /** Prise en passant. */
  enPassant?: boolean;
  /** Roi « emprisonné » capturé par ce coup (équipe matée). */
  kingCaptured?: Player | null;
  /** Poignées (frontières 0..2) ouvertes par cet évènement. */
  hiltsOpened: number[];
  /** Équipe éliminée parce qu'aucune équipe ne pouvait jouer (3 équipes en jeu). */
  blocked?: { player: Player; by: Player } | null;
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
  version: 2;
  mode: Mode;
  /** 144 cases, index = équipe*48 + (anneau-1)*8 + colonne. */
  board: (Piece | null)[];
  /** hilts[b] : la poignée de la frontière b est ouverte (définitivement). */
  hilts: [boolean, boolean, boolean];
  /** Droits de prise en passant en cours. */
  enPassant: EnPassant[];
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
  /** Poignées ouvertes (index = frontière). */
  hilts: [boolean, boolean, boolean];
}
