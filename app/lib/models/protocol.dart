// Modèles et parsing des messages du protocole (docs/PROTOCOL.md).
import 'dart:convert';

Map<String, dynamic> jsonDecodeMap(String s) => json.decode(s) as Map<String, dynamic>;


const playerNames = ['Blanc', 'Rouge', 'Noir'];

enum PieceType { king, queen, rook, bishop, knight, pawn }

PieceType pieceTypeFromCode(String c) => switch (c) {
      'K' => PieceType.king,
      'Q' => PieceType.queen,
      'R' => PieceType.rook,
      'B' => PieceType.bishop,
      'N' => PieceType.knight,
      _ => PieceType.pawn,
    };

/// Lettre française affichée sur les pièces placeholders.
String pieceLetter(PieceType t) => switch (t) {
      PieceType.king => 'R',
      PieceType.queen => 'D',
      PieceType.rook => 'T',
      PieceType.bishop => 'F',
      PieceType.knight => 'C',
      PieceType.pawn => 'P',
    };

class Piece {
  const Piece(this.type, this.owner, {this.crossed = false});
  final PieceType type;
  final int owner;

  /// Pion ayant traversé le centre (il avance vers l'extérieur).
  final bool crossed;
  factory Piece.fromJson(Map<String, dynamic> j) => Piece(
      pieceTypeFromCode(j['type'] as String), j['owner'] as int,
      crossed: (j['crossed'] ?? false) as bool);
}

/// Pièces de promotion (codes du protocole), dans l'ordre du sélecteur.
const promotionCodes = ['Q', 'R', 'B', 'N'];

/// Identifiant de case ("0e2" : équipe, colonne a-h, anneau 1-6) -> index 0..143.
int cellIndex(String id) {
  final s = id.codeUnitAt(0) - 48;
  final f = id.codeUnitAt(1) - 97;
  final r = id.codeUnitAt(2) - 49;
  return s * 48 + r * 8 + f;
}

class PlayerInfo {
  const PlayerInfo({
    required this.id,
    required this.pseudo,
    required this.connected,
    required this.push,
    this.isBot = false,
    this.level,
  });
  final int id;
  final String pseudo;
  final bool connected;
  final bool push;

  /// Joueur artificiel joué par le serveur.
  final bool isBot;

  /// Niveau du bot : 'facile', 'moyen' ou 'difficile'.
  final String? level;

  factory PlayerInfo.fromJson(Map<String, dynamic> j) => PlayerInfo(
        id: j['id'] as int,
        pseudo: (j['pseudo'] ?? '') as String,
        connected: (j['connected'] ?? false) as bool,
        push: (j['push'] ?? false) as bool,
        isBot: (j['isBot'] ?? false) as bool,
        level: j['level'] as String?,
      );
}

/// Niveaux des bots (identifiants du protocole).
const botLevels = ['facile', 'moyen', 'difficile'];

String botLevelLabel(String? level) => switch (level) {
      'facile' => 'Facile',
      'difficile' => 'Difficile',
      _ => 'Moyen',
    };

class RoomMsg {
  const RoomMsg({
    required this.code,
    required this.mode,
    required this.players,
    required this.ready,
    required this.started,
    required this.you,
  });
  final String code;
  final String mode;
  final List<PlayerInfo> players;
  final bool ready;
  final bool started;
  final int you;

  factory RoomMsg.fromJson(Map<String, dynamic> j) => RoomMsg(
        code: j['code'] as String,
        mode: j['mode'] as String,
        players: (j['players'] as List)
            .map((e) => PlayerInfo.fromJson(e as Map<String, dynamic>))
            .toList(),
        ready: (j['ready'] ?? false) as bool,
        started: (j['started'] ?? false) as bool,
        you: j['you'] as int,
      );

  PlayerInfo? playerById(int id) {
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }
}

class GameResult {
  const GameResult({this.winner, required this.reason});
  final int? winner;
  final String reason;
  factory GameResult.fromJson(Map<String, dynamic> j) =>
      GameResult(winner: j['winner'] as int?, reason: j['reason'] as String);
}

class Elimination {
  const Elimination(
      {required this.player, this.by, required this.reason, required this.ply});
  final int player;
  final int? by;
  final String reason;
  final int ply;
  factory Elimination.fromJson(Map<String, dynamic> j) => Elimination(
        player: j['player'] as int,
        by: j['by'] as int?,
        reason: j['reason'] as String,
        ply: j['ply'] as int,
      );
}

class Captured {
  const Captured(
      {required this.type,
      required this.owner,
      required this.frozen,
      required this.at});
  final PieceType type;
  final int owner;
  final bool frozen;
  final String at;
}

class CheckInfo {
  const CheckInfo(this.player, this.by);
  final int player;
  final List<int> by;
}

class GameEvent {
  const GameEvent({
    required this.kind,
    required this.player,
    this.from,
    this.to,
    this.piece,
    this.captured,
    this.promotion = false,
    this.promotionType,
    this.crossedCenter = false,
    this.enPassant = false,
    this.kingCaptured,
    this.hiltsOpened = const [],
    this.castleRookFrom,
    this.castleRookTo,
    this.checks = const [],
    this.mates = const [],
    this.eliminated = const [],
    this.passes = const [],
    this.gameOver,
    this.auto = false,
  });

  final String kind; // 'move' | 'resign'
  final int player;
  final String? from;
  final String? to;
  final PieceType? piece;
  final Captured? captured;
  final bool promotion;

  /// Pièce choisie pour la promotion ('Q', 'R', 'B', 'N').
  final String? promotionType;

  /// Le coup a traversé le médaillon central.
  final bool crossedCenter;
  final bool enPassant;

  /// Équipe dont le roi « emprisonné » vient d'être capturé.
  final int? kingCaptured;

  /// Frontières (0..2) dont la poignée vient de s'ouvrir.
  final List<int> hiltsOpened;
  final String? castleRookFrom;
  final String? castleRookTo;
  final List<CheckInfo> checks;
  final List<int> mates;
  final List<int> eliminated;
  final List<int> passes;
  final GameResult? gameOver;
  final bool auto;

  bool get isMove => kind == 'move';

  factory GameEvent.fromJson(Map<String, dynamic> j, {bool auto = false}) {
    final mv = j['move'] as Map<String, dynamic>?;
    final cap = j['captured'] as Map<String, dynamic>?;
    final castle = j['castle'] as Map<String, dynamic>?;
    return GameEvent(
      kind: j['kind'] as String,
      player: j['player'] as int,
      from: mv?['from'] as String?,
      to: mv?['to'] as String?,
      piece: j['piece'] == null ? null : pieceTypeFromCode(j['piece'] as String),
      captured: cap == null
          ? null
          : Captured(
              type: pieceTypeFromCode(cap['type'] as String),
              owner: cap['owner'] as int,
              frozen: (cap['frozen'] ?? false) as bool,
              at: cap['at'] as String,
            ),
      promotion: j['promotion'] != null,
      promotionType: j['promotion'] as String?,
      crossedCenter: (j['crossedCenter'] ?? false) as bool,
      enPassant: (j['enPassant'] ?? false) as bool,
      kingCaptured: j['kingCaptured'] as int?,
      hiltsOpened: ((j['hiltsOpened'] ?? const []) as List).map((e) => e as int).toList(),
      castleRookFrom: castle?['rookFrom'] as String?,
      castleRookTo: castle?['rookTo'] as String?,
      checks: ((j['checks'] ?? const []) as List)
          .map((e) => CheckInfo(
              e['player'] as int, (e['by'] as List).map((x) => x as int).toList()))
          .toList(),
      mates: ((j['mates'] ?? const []) as List)
          .map((e) => (e as Map<String, dynamic>)['player'] as int)
          .toList(),
      eliminated:
          ((j['eliminated'] ?? const []) as List).map((e) => e as int).toList(),
      passes: ((j['passes'] ?? const []) as List).map((e) => e as int).toList(),
      gameOver: j['gameOver'] == null
          ? null
          : GameResult.fromJson(j['gameOver'] as Map<String, dynamic>),
      auto: auto || (j['auto'] ?? false) as bool,
    );
  }
}

class GameState {
  const GameState({
    required this.mode,
    required this.board,
    required this.turn,
    required this.active,
    required this.ply,
    required this.eliminations,
    this.result,
    this.hilts = const [false, false, false],
  });
  final String mode;

  /// hilts[b] : la poignée de la frontière b est ouverte.
  final List<bool> hilts;
  final List<Piece?> board;
  final int turn;
  final List<bool> active;
  final int ply;
  final List<Elimination> eliminations;
  final GameResult? result;

  factory GameState.fromJson(Map<String, dynamic> j) => GameState(
        mode: j['mode'] as String,
        board: (j['board'] as List)
            .map((e) => e == null ? null : Piece.fromJson(e as Map<String, dynamic>))
            .toList(),
        turn: j['turn'] as int,
        active: (j['active'] as List).map((e) => e as bool).toList(),
        ply: (j['ply'] ?? 0) as int,
        eliminations: ((j['eliminations'] ?? const []) as List)
            .map((e) => Elimination.fromJson(e as Map<String, dynamic>))
            .toList(),
        result: j['result'] == null
            ? null
            : GameResult.fromJson(j['result'] as Map<String, dynamic>),
        hilts: ((j['hilts'] ?? const [false, false, false]) as List).map((e) => e as bool).toList(),
      );
}

class LegalMove {
  const LegalMove(this.from, this.to, {this.promotion});
  final String from;
  final String to;

  /// Variante de promotion ('Q', 'R', 'B', 'N') ; null si le coup ne promeut pas.
  final String? promotion;
}

class GameMsg {
  const GameMsg({
    required this.state,
    this.lastEvent,
    this.turn,
    this.legalMoves = const [],
    this.turnDeadline,
    required this.over,
    this.result,
    this.players = const [],
  });
  final GameState state;
  final GameEvent? lastEvent;
  final int? turn;
  final List<LegalMove> legalMoves;
  final int? turnDeadline;
  final bool over;
  final GameResult? result;
  final List<PlayerInfo> players;

  factory GameMsg.fromJson(Map<String, dynamic> j) {
    final le = j['lastEvent'] as Map<String, dynamic>?;
    return GameMsg(
      state: GameState.fromJson(j['state'] as Map<String, dynamic>),
      lastEvent: le == null ? null : GameEvent.fromJson(le),
      turn: j['turn'] as int?,
      legalMoves: ((j['legalMoves'] ?? const []) as List)
          .map((e) => LegalMove(e['from'] as String, e['to'] as String,
              promotion: e['promotion'] as String?))
          .toList(),
      turnDeadline: (j['turnDeadline'] as num?)?.toInt(),
      over: (j['over'] ?? false) as bool,
      result: j['result'] == null
          ? null
          : GameResult.fromJson(j['result'] as Map<String, dynamic>),
      players: ((j['players'] ?? const []) as List)
          .map((e) => PlayerInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ErrorMsg {
  const ErrorMsg(this.code, this.message);
  final String code;
  final String message;
}

class PongMsg {
  const PongMsg(this.now);
  final int now;
}

/// Parse un message serveur ; renvoie RoomMsg, GameMsg, ErrorMsg, PongMsg ou null (inconnu / invalide).
Object? parseServerMessage(dynamic raw) {
  try {
    final j = (raw is String ? jsonDecodeMap(raw) : raw) as Map<String, dynamic>;
    switch (j['type']) {
      case 'room':
        return RoomMsg.fromJson(j);
      case 'game':
        return GameMsg.fromJson(j);
      case 'error':
        return ErrorMsg((j['code'] ?? '') as String, (j['message'] ?? '') as String);
      case 'pong':
        return PongMsg((j['now'] as num).toInt());
    }
  } catch (_) {}
  return null;
}

/// Classement final : [(joueur, rang)] ; rang 1 = vainqueur, ex æquo possibles (nulle).
class RankEntry {
  const RankEntry(this.player, this.rank, this.note);
  final int player;
  final int rank;
  final String note;
}

List<RankEntry> computeRanking(GameState s, GameResult? result) {
  final winner = result?.winner;
  final elimPly = <int, int>{for (final e in s.eliminations) e.player: e.ply};
  if (winner == null) {
    return [
      for (var p = 0; p < 3; p++)
        RankEntry(p, 1, s.active[p] ? 'Partie nulle' : 'Éliminé'),
    ];
  }
  final others = [0, 1, 2].where((p) => p != winner).toList()
    ..sort((a, b) {
      // Encore en jeu d'abord, puis éliminé le plus tard.
      final ea = elimPly[a] ?? 1 << 30;
      final eb = elimPly[b] ?? 1 << 30;
      return eb.compareTo(ea);
    });
  return [
    RankEntry(winner, 1, 'Vainqueur'),
    for (var i = 0; i < others.length; i++)
      RankEntry(others[i], i + 2, s.active[others[i]] ? 'Battu' : 'Éliminé'),
  ];
}

String reasonLabel(String reason) => switch (reason) {
      'mate' => 'Échec et mat',
      'lastStanding' => 'Dernier joueur en jeu',
      'fiftyMoves' => 'Règle des 50 coups',
      'repetition' => 'Triple répétition',
      'stalemate' => 'Plus aucun coup possible',
      'blockade' => 'Blocage : aucune équipe ne peut jouer',
      _ => reason,
    };
