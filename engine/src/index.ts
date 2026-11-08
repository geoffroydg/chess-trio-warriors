// API publique du moteur de règles d'échecs à 3 joueurs.
export {
  initialState,
  legalMoves,
  applyMove,
  randomMove,
  resign,
  status,
  customState,
  pieceAt,
  isCellAttacked,
  nextPlayer,
} from './rules.ts';
export type { CustomPiece, CustomOptions } from './rules.ts';
export { boardCells, boardOutline } from './geometry.ts';
export type { CellGeometry, Point } from './geometry.ts';
export { cellName, parseCell, NUM_CELLS, FILES } from './topology.ts';
export type * from './types.ts';
