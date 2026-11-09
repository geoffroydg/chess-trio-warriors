import { test } from 'node:test';
import assert from 'node:assert/strict';
import { RoomLogic, TURN_MS, FINISHED_TTL_MS, INACTIVITY_TTL_MS, CODE_ALPHABET, generateCode, BOT_DELAY_MIN_MS, BOT_DELAY_MAX_MS, BOT_NAMES } from '../src/room-logic.ts';
import type { PushMessage, RoomData, ServerMessage } from '../src/room-logic.ts';
import { customState } from '../../engine/src/index.ts';

function rngFrom(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function harness(seed = 1) {
  let now = 1_000_000;
  let stored: RoomData | null = null;
  let alarm: number | null = null;
  let deleted = false;
  const connected = new Set<number>();
  const inbox: Record<number, ServerMessage[]> = { 0: [], 1: [], 2: [] };
  const pushes: PushMessage[][] = [];
  const mk = () =>
    new RoomLogic({
      now: () => now,
      rng: rngFrom(seed),
      load: async () => (stored ? structuredClone(stored) : null),
      save: async (d) => void (stored = structuredClone(d)),
      deleteAll: async () => void ((stored = null), (alarm = null), (deleted = true)),
      setAlarm: async (at) => void (alarm = at),
      isConnected: (id) => connected.has(id),
      send: (id, m) => void inbox[id].push(structuredClone(m)),
      notify: (m) => void pushes.push(m),
    });
  const h = {
    logic: mk(),
    mk,
    inbox,
    pushes,
    connected,
    get now() { return now; },
    advance(ms: number) { now += ms; },
    get alarm() { return alarm; },
    get deleted() { return deleted; },
    get stored() { return stored; },
    last(id: number, type: string) {
      return [...inbox[id]].reverse().find((m) => m.type === type) as any;
    },
    async send(id: number, msg: object) { await h.logic.onMessage(id as 0, JSON.stringify(msg)); },
    async fireAlarm() { now = Math.max(now, alarm!); await h.logic.onAlarm(); },
  };
  return h;
}

async function fullRoom(mode: 'firstMate' | 'twoMates' = 'firstMate', seed = 1) {
  const h = harness(seed);
  const c = await h.logic.create('ABC234', { pseudo: 'Ana', password: 'secret', mode });
  assert.ok(c.ok);
  const j1 = await h.logic.join({ pseudo: 'Bob', password: 'secret' });
  const j2 = await h.logic.join({ pseudo: 'Cléo', password: 'secret' });
  assert.ok(j1.ok && j2.ok);
  for (const id of [0, 1, 2]) h.connected.add(id);
  return { h, tokens: [c.value.playerToken, (j1 as any).value.playerToken, (j2 as any).value.playerToken] };
}

test('code salon : 6 caractères sans ambiguïté', () => {
  for (let i = 0; i < 200; i++) {
    const c = generateCode();
    assert.equal(c.length, 6);
    for (const ch of c) assert.ok(CODE_ALPHABET.includes(ch));
  }
  assert.ok(!/[O0I1]/.test(CODE_ALPHABET));
});

test('création, join, mot de passe haché', async () => {
  const h = harness();
  const c = await h.logic.create('ABC234', { pseudo: ' Ana ', password: 'secret', mode: 'twoMates' });
  assert.ok(c.ok);
  assert.equal(c.value.playerId, 0);
  assert.equal(h.stored!.players[0].pseudo, 'Ana');
  assert.ok(!JSON.stringify(h.stored).includes('secret'));
  assert.match(h.stored!.passwordHash, /^[0-9a-f]{64}$/);
  const j = await h.logic.join({ pseudo: 'Bob', password: 'secret' });
  assert.ok(j.ok && j.value.playerId === 1);
  const j2 = await h.logic.join({ pseudo: 'Cléo', password: 'secret' });
  assert.ok(j2.ok && j2.value.playerId === 2);
  const j3 = await h.logic.join({ pseudo: 'Dan', password: 'secret' });
  assert.ok(!j3.ok && j3.status === 409 && j3.error === 'roomFull');
});

test('validation des champs, mauvais mot de passe, salon inconnu', async () => {
  const h = harness();
  const bad = [
    { pseudo: '', password: 'x', mode: 'firstMate' },
    { pseudo: 'x'.repeat(17), password: 'x', mode: 'firstMate' },
    { pseudo: 'ok', password: '', mode: 'firstMate' },
    { pseudo: 'ok', password: 'x'.repeat(65), mode: 'firstMate' },
    { pseudo: 'ok', password: 'x', mode: 'zzz' },
    { pseudo: 42, password: 'x', mode: 'firstMate' },
  ];
  for (const b of bad) {
    const r = await h.logic.create('ABC234', b);
    assert.ok(!r.ok && r.status === 400);
  }
  const none = await h.logic.join({ pseudo: 'a', password: 'b' });
  assert.ok(!none.ok && none.status === 404);
  await h.logic.create('ABC234', { pseudo: 'Ana', password: 'secret', mode: 'firstMate' });
  const wrong = await h.logic.join({ pseudo: 'Bob', password: 'nope' });
  assert.ok(!wrong.ok && wrong.status === 403 && wrong.error === 'wrongPassword');
  const dup = await h.logic.create('ABC234', { pseudo: 'x', password: 'y', mode: 'firstMate' });
  assert.ok(!dup.ok && dup.status === 409);
});

test('start : hôte seulement, 3 joueurs requis', async () => {
  const h = harness();
  await h.logic.create('ABC234', { pseudo: 'Ana', password: 'p', mode: 'firstMate' });
  await h.send(0, { type: 'start' });
  assert.equal(h.last(0, 'error').code, 'notEnoughPlayers');
  await h.logic.join({ pseudo: 'Bob', password: 'p' });
  await h.logic.join({ pseudo: 'Cléo', password: 'p' });
  await h.send(1, { type: 'start' });
  assert.equal(h.last(1, 'error').code, 'notHost');
  await h.send(0, { type: 'start' });
  const g = h.last(2, 'game');
  assert.equal(g.turn, 0);
  assert.ok(g.legalMoves.length > 0);
  assert.equal(g.turnDeadline, h.now + TURN_MS);
  assert.equal(h.alarm, g.turnDeadline);
  assert.equal(h.last(1, 'room').started, true);
  await h.send(0, { type: 'start' });
  assert.equal(h.last(0, 'error').code, 'alreadyStarted');
  const late = await h.logic.join({ pseudo: 'Eve', password: 'p' });
  assert.ok(!late.ok);
});

test('coup légal, illégal, hors tour', async () => {
  const { h } = await fullRoom();
  await h.send(0, { type: 'move', from: '0e2', to: '0e4' });
  assert.equal(h.last(0, 'error').code, 'notStarted');
  h.inbox[0].length = 0;
  await h.send(0, { type: 'start' });
  await h.send(0, { type: 'move', from: '0e2', to: '0e4' });
  assert.deepEqual(h.inbox[0].filter((m) => m.type === 'error'), []);
  const g = h.last(1, 'game');
  assert.equal(g.turn, 1);
  assert.equal(g.lastEvent.player, 0);
  assert.equal(g.lastEvent.auto, undefined);
  assert.equal(g.state.ply, 1);
  await h.send(0, { type: 'move', from: '0d2', to: '0d4' });
  assert.equal(h.last(0, 'error').code, 'notYourTurn');
  await h.send(1, { type: 'move', from: '1a1', to: '1a5' });
  assert.equal(h.last(1, 'error').code, 'illegalMove');
  await h.send(1, { type: 'move', from: '1e1', to: '1e3' });
  assert.equal(h.last(1, 'error').code, 'illegalMove');
  await h.logic.onMessage(1, 'pas du json');
  assert.equal(h.last(1, 'error').code, 'badMessage');
  await h.send(1, { type: 'ping' });
  assert.equal(h.last(1, 'pong').now, h.now);
});

test('timeout : coup auto pour le joueur au trait, même déconnecté', async () => {
  const { h } = await fullRoom();
  await h.send(0, { type: 'start' });
  h.connected.delete(0);
  await h.logic.onAlarm(); // pas encore échu : sans effet
  assert.equal(h.stored!.state!.ply, 0);
  h.advance(TURN_MS);
  await h.logic.onAlarm();
  const g = h.last(1, 'game');
  assert.equal(g.state.ply, 1);
  assert.equal(g.lastEvent.auto, true);
  assert.equal(g.lastEvent.player, 0);
  assert.equal(g.turn, 1);
  assert.equal(g.turnDeadline, h.now + TURN_MS);
  assert.equal(h.alarm, g.turnDeadline);
  assert.equal(g.players[0].connected, false);
});

test('reconnexion par jeton', async () => {
  const { h, tokens } = await fullRoom();
  assert.equal(await h.logic.authenticate(tokens[1]), 1);
  assert.equal(await h.logic.authenticate('faux'), null);
  assert.equal(await h.logic.authenticate(null), null);
  await h.send(0, { type: 'start' });
  // nouvelle instance (réveil du DO) : l'état est rechargé depuis le stockage
  const h2 = h.logic;
  void h2;
  const fresh = h.mk();
  assert.equal(await fresh.authenticate(tokens[2]), 2);
  h.inbox[2].length = 0;
  await fresh.onConnect(2);
  assert.deepEqual(h.inbox[2].map((m) => m.type), ['room', 'game']);
  assert.equal(h.last(2, 'game').state.ply, 0);
  assert.equal(h.last(2, 'room').you, 2);
});

test('registerPush et notifications ciblées', async () => {
  const { h } = await fullRoom();
  await h.send(0, { type: 'registerPush', fcmToken: 'tok0' });
  await h.send(1, { type: 'registerPush', fcmToken: 'tok1' });
  await h.send(2, { type: 'registerPush', fcmToken: 'tok2' });
  assert.equal(h.last(0, 'room').players[0].push, true);
  await h.send(0, { type: 'registerPush', fcmToken: 42 });
  assert.equal(h.last(0, 'error').code, 'badMessage');
  await h.send(0, { type: 'start' });
  await h.send(0, { type: 'move', from: '0e2', to: '0e4' });
  const p = h.pushes.at(-1)!;
  assert.equal(p.length, 2);
  const byTok = Object.fromEntries(p.map((m) => [m.fcmToken, m]));
  assert.equal(byTok.tok1.title, "C'est ton tour !");
  assert.equal(byTok.tok1.data.type, 'turn');
  assert.equal(byTok.tok1.data.roomCode, 'ABC234');
  assert.match(byTok.tok1.body, /0e2/);
  assert.equal(byTok.tok2.title, 'Ana a joué');
  assert.equal(byTok.tok2.data.type, 'move');
  assert.equal(byTok.tok0, undefined);
  // joueur 2 sans jeton : pas de notification pour lui
  await h.send(2, { type: 'registerPush', fcmToken: '' });
  assert.equal(h.last(2, 'error').code, 'badMessage');
});

test('promotion au choix : variantes dans legalMoves, champ promotion du message move', async () => {
  const { h } = await fullRoom('twoMates');
  for (const i of [0, 1, 2]) await h.send(i, { type: 'registerPush', fcmToken: `t${i}` });
  await h.send(0, { type: 'start' });
  // Position injectée : pion blanc ayant traversé le centre, prêt à promouvoir en 2b1.
  h.stored!.state = customState('twoMates', [
    { cell: '0d1', type: 'K', owner: 0 },
    { cell: '2b2', type: 'P', owner: 0, crossed: true },
    { cell: '1d1', type: 'K', owner: 1 },
    { cell: '2d1', type: 'K', owner: 2 },
  ]);
  h.logic = h.mk();
  await h.send(0, { type: 'move', from: '2b2', to: '2b1', promotion: 'K' });
  assert.equal(h.last(0, 'error').code, 'illegalMove');
  await h.send(0, { type: 'move', from: '2b2', to: '2b1', promotion: 'N' });
  const g = h.last(1, 'game');
  assert.equal(g.state.board.find((p: any) => p?.owner === 0 && p.type === 'N') !== undefined, true);
  assert.equal(g.lastEvent.promotion, 'N');
  assert.match(h.pushes.at(-1)![0].body, /promotion : cavalier/);
  // Les coups légaux envoyés au client contiennent les 4 variantes ; sans champ promotion : dame.
  h.stored!.state = customState('twoMates', [
    { cell: '0d1', type: 'K', owner: 0 },
    { cell: '1d1', type: 'K', owner: 1 },
    { cell: '2d1', type: 'K', owner: 2 },
    { cell: '0b2', type: 'P', owner: 2, crossed: true },
  ], { turn: 2 });
  h.logic = h.mk();
  await h.send(2, { type: 'move', from: '2d1', to: '2c1' });
  await h.send(0, { type: 'move', from: '0d1', to: '0e1' });
  await h.send(1, { type: 'move', from: '1d1', to: '1c1' });
  assert.deepEqual(h.inbox[2].filter((m) => m.type === 'error'), []);
  const g4 = h.last(2, 'game');
  assert.deepEqual(
    g4.legalMoves.filter((m: any) => m.from === '0b2' && m.to === '0b1').map((m: any) => m.promotion).sort(),
    ['B', 'N', 'Q', 'R'],
  );
  await h.send(2, { type: 'move', from: '0b2', to: '0b1' });
  assert.equal(h.last(0, 'game').lastEvent.promotion, 'Q');
});

test('abandon : élimination et notification', async () => {
  const { h } = await fullRoom('twoMates');
  for (const i of [0, 1, 2]) await h.send(i, { type: 'registerPush', fcmToken: `t${i}` });
  await h.send(0, { type: 'start' });
  await h.send(1, { type: 'resign' }); // hors tour mais autorisé
  const g = h.last(0, 'game');
  assert.equal(g.state.active[1], false);
  assert.equal(g.turn, 0);
  const p = h.pushes.at(-1)!;
  assert.deepEqual(p.map((m) => m.fcmToken).sort(), ['t0', 't2']);
  assert.equal(p.find((m) => m.fcmToken === 't0')!.title, "C'est ton tour !");
  assert.equal(p.find((m) => m.fcmToken === 't2')!.data.type, 'resign');
  await h.send(0, { type: 'resign' });
  const over = h.last(2, 'game');
  assert.equal(over.over, true);
  assert.equal(over.result.winner, 2);
  assert.equal(over.turnDeadline, null);
  assert.deepEqual(over.legalMoves, []);
  // 1 a déjà abandonné (jeton supprimé), 0 vient d'abandonner : seul 2 reçoit la fin de partie.
  assert.deepEqual(h.pushes.at(-1)!.map((m) => [m.fcmToken, m.data.type]), [['t2', 'gameOver']]);
  assert.ok(h.stored!.players.every((p) => !p.fcmToken));
  await h.send(2, { type: 'move', from: '2e2', to: '2e4' });
  assert.equal(h.last(2, 'error').code, 'gameOver');
});

test('partie aléatoire complète par minuteur, puis suppression à +24 h', async () => {
  const { h } = await fullRoom('twoMates', 7);
  await h.send(0, { type: 'start' });
  // mélange de coups joués par les clients et de coups automatiques
  let n = 0;
  while (!h.stored!.state!.result && n < 20000) {
    n++;
    const g = h.last(0, 'game');
    if (n % 2 === 0) {
      const m = g.legalMoves[0];
      await h.send(g.turn, { type: 'move', from: m.from, to: m.to });
    } else {
      h.advance(TURN_MS);
      await h.logic.onAlarm();
    }
  }
  const st = h.stored!.state!;
  assert.ok(st.result, 'la partie doit se terminer');
  const g = h.last(0, 'game');
  assert.equal(g.over, true);
  assert.equal(g.turnDeadline, null);
  assert.equal(h.stored!.finishedAt, h.now);
  assert.equal(h.alarm, h.now + FINISHED_TTL_MS);
  // l'alarme avant 24 h ne supprime rien
  h.advance(FINISHED_TTL_MS - 1);
  await h.logic.onAlarm();
  assert.equal(h.deleted, false);
  h.advance(1);
  await h.logic.onAlarm();
  assert.equal(h.deleted, true);
  assert.equal(h.stored, null);
  assert.equal(await h.logic.isInitialised(), false);
});

test('suppression après 7 jours d\'inactivité', async () => {
  const h = harness();
  await h.logic.create('ABC234', { pseudo: 'Ana', password: 'p', mode: 'firstMate' });
  assert.equal(h.alarm, h.now + INACTIVITY_TTL_MS);
  h.advance(INACTIVITY_TTL_MS);
  await h.logic.onAlarm();
  assert.equal(h.deleted, true);
});

// ---------- Bots ----------

test('ajout / retrait de bot en salle d\'attente (hôte seulement)', async () => {
  const h = harness();
  await h.logic.create('ABC234', { pseudo: 'Ana', password: 'p', mode: 'firstMate' });
  h.connected.add(0);
  await h.send(0, { type: 'addBot', seat: 2, level: 'difficile' });
  let r = h.last(0, 'room');
  assert.equal(r.players.length, 2);
  const bot = r.players.find((p: any) => p.id === 2);
  assert.equal(bot.isBot, true);
  assert.equal(bot.level, 'difficile');
  assert.equal(bot.connected, true);
  assert.ok(BOT_NAMES.includes(bot.pseudo));
  assert.equal(r.players[0].isBot, false);
  await h.send(0, { type: 'addBot', seat: 2, level: 'facile' });
  assert.equal(h.last(0, 'error').code, 'seatTaken');
  await h.send(0, { type: 'addBot', seat: 1, level: 'expert' });
  assert.equal(h.last(0, 'error').code, 'badMessage');
  await h.send(0, { type: 'addBot', seat: 0, level: 'facile' });
  assert.equal(h.last(0, 'error').code, 'badMessage');
  // un humain rejoint : il prend le siège libre (1)
  const j = await h.logic.join({ pseudo: 'Bob', password: 'p' });
  assert.ok(j.ok && j.value.playerId === 1);
  await h.send(1, { type: 'addBot', level: 'facile' });
  assert.equal(h.last(1, 'error').code, 'notHost');
  await h.send(1, { type: 'removeBot', seat: 2 });
  assert.equal(h.last(1, 'error').code, 'notHost');
  await h.send(0, { type: 'removeBot', seat: 1 });
  assert.equal(h.last(0, 'error').code, 'notBot');
  await h.send(0, { type: 'addBot', level: 'moyen' });
  assert.equal(h.last(0, 'error').code, 'roomFull');
  assert.equal(h.last(0, 'room').ready, true);
  await h.send(0, { type: 'removeBot', seat: 2 });
  r = h.last(0, 'room');
  assert.equal(r.players.length, 2);
  assert.equal(r.ready, false);
  // siège libéré : un nouvel humain peut le prendre
  const j2 = await h.logic.join({ pseudo: 'Cléo', password: 'p' });
  assert.ok(j2.ok && j2.value.playerId === 2);
  // le jeton d'un bot ne permet jamais de se connecter
  assert.equal(await h.logic.authenticate(''), null);
  await h.send(0, { type: 'start' });
  await h.send(0, { type: 'addBot', seat: 1, level: 'moyen' });
  assert.equal(h.last(0, 'error').code, 'alreadyStarted');
});

test('salon solo : 2 bots, démarré aussitôt, mot de passe facultatif', async () => {
  const h = harness(3);
  const bad = await h.logic.create('ABC234', { pseudo: 'Ana', mode: 'firstMate', bots: [{ level: 'moyen' }, { level: 'nul' }] });
  assert.ok(!bad.ok && bad.status === 400);
  const bad2 = await h.logic.create('ABC234', { pseudo: 'Ana', mode: 'firstMate', bots: [{ level: 'moyen' }] });
  assert.ok(!bad2.ok && bad2.status === 400, 'un seul bot : mot de passe requis');
  const c = await h.logic.create('ABC234', { pseudo: 'Ana', mode: 'twoMates', bots: [{ level: 'facile' }, { level: 'difficile' }] });
  assert.ok(c.ok && c.value.playerId === 0);
  const d = h.stored!;
  assert.equal(d.started, true);
  assert.equal(d.state!.turn, 0);
  assert.deepEqual(d.players.map((p) => [p.id, !!p.isBot, p.botLevel]), [[0, false, undefined], [1, true, 'facile'], [2, true, 'difficile']]);
  assert.notEqual(d.players[1].pseudo, d.players[2].pseudo);
  assert.equal(d.botMoveAt, null);
  assert.equal(h.alarm, d.turnDeadline);
  const late = await h.logic.join({ pseudo: 'Bob', password: '' });
  assert.ok(!late.ok);
  h.connected.add(0);
  await h.logic.onConnect(0);
  assert.deepEqual(h.inbox[0].map((m) => m.type), ['room', 'game']);
  const room = h.last(0, 'room');
  assert.equal(room.started, true);
  assert.equal(room.players[2].isBot, true);
  assert.equal(room.players[2].level, 'difficile');
});

test('partie complète : 1 humain + 2 bots, alarme unique sur la prochaine échéance, pas de push aux bots', async () => {
  const h = harness(11);
  const c = await h.logic.create('ABC234', { pseudo: 'Ana', password: '', mode: 'firstMate', bots: [{ level: 'moyen' }, { level: 'facile' }] });
  assert.ok(c.ok);
  h.connected.add(0);
  await h.send(0, { type: 'registerPush', fcmToken: 'tok0' });
  let botMoves = 0;
  let humanMoves = 0;
  for (let n = 0; n < 3000 && !h.stored!.state!.result; n++) {
    const d = h.stored!;
    const turn = d.state!.turn;
    if (turn === 0) {
      assert.equal(d.botMoveAt, null);
      assert.equal(h.alarm, d.turnDeadline);
      // l'humain joue vite (coup légal), ou laisse parfois filer le temps
      if (n % 9 === 0) {
        h.advance(TURN_MS);
        await h.logic.onAlarm();
      } else {
        const g = h.last(0, 'game');
        const m = g.legalMoves[n % g.legalMoves.length];
        await h.send(0, { type: 'move', from: m.from, to: m.to });
      }
      humanMoves++;
    } else {
      // au tour d'un bot : alarme = délai naturel (avant le minuteur de 60 s)
      const at = d.botMoveAt!;
      assert.ok(at - h.now >= BOT_DELAY_MIN_MS && at - h.now <= BOT_DELAY_MAX_MS, `délai ${at - h.now}`);
      assert.equal(h.alarm, at);
      assert.ok(at < d.turnDeadline!);
      // une alarme précoce (avant l'échéance) ne fait rien
      await h.logic.onAlarm();
      assert.equal(h.stored!.state!.ply, d.state!.ply);
      const ply = d.state!.ply;
      await h.fireAlarm();
      assert.equal(h.stored!.state!.ply, ply + 1, 'le bot a joué');
      assert.equal(h.last(0, 'game').lastEvent.auto, undefined);
      botMoves++;
    }
  }
  const st = h.stored!.state!;
  assert.ok(st.result, 'la partie doit se terminer');
  assert.ok(botMoves > 0 && humanMoves > 0);
  assert.equal(h.stored!.botMoveAt, null);
  assert.equal(h.alarm, h.now + FINISHED_TTL_MS);
  // aucun message n'a été envoyé aux sièges des bots, et les push ne visent que l'humain
  assert.equal(h.inbox[1].length, 0);
  assert.equal(h.inbox[2].length, 0);
  for (const batch of h.pushes) for (const m of batch) assert.equal(m.fcmToken, 'tok0');
  assert.equal(h.last(0, 'game').over, true);
});

test('2 humains + 1 bot : le bot joue à son tour, le minuteur reste celui des humains', async () => {
  const h = harness(5);
  await h.logic.create('ABC234', { pseudo: 'Ana', password: 'p', mode: 'twoMates' });
  await h.send(0, { type: 'addBot', seat: 1, level: 'difficile' });
  const j = await h.logic.join({ pseudo: 'Bob', password: 'p' });
  assert.ok(j.ok && j.value.playerId === 2);
  h.connected.add(0).add(2);
  await h.send(0, { type: 'start' });
  assert.equal(h.alarm, h.stored!.turnDeadline);
  await h.send(0, { type: 'move', from: '0e2', to: '0e4' });
  const d = h.stored!;
  assert.equal(d.state!.turn, 1);
  assert.equal(h.alarm, d.botMoveAt);
  await h.fireAlarm();
  const g = h.last(2, 'game');
  assert.equal(g.state.ply, 2);
  assert.equal(g.lastEvent.player, 1);
  assert.equal(g.turn, 2);
  assert.equal(h.stored!.botMoveAt, null);
  assert.equal(h.alarm, h.stored!.turnDeadline);
});

test('BOT_CPU_MS : lecture de la variable d\'env', async () => {
  const { parseBotCpuMs } = await import('../src/room-logic.ts');
  assert.equal(parseBotCpuMs('8'), 8);
  assert.equal(parseBotCpuMs('2.5'), 2.5);
  assert.equal(parseBotCpuMs(undefined), undefined);
  assert.equal(parseBotCpuMs('abc'), undefined);
  assert.equal(parseBotCpuMs('0'), undefined);
});

test('abandon : plus aucune notification pour celui qui abandonne, et rien pour lui', async () => {
  const { h } = await fullRoom('twoMates');
  for (const i of [0, 1, 2]) await h.send(i, { type: 'registerPush', fcmToken: `t${i}` });
  await h.send(0, { type: 'start' });
  await h.send(1, { type: 'resign' });
  assert.ok(h.pushes.at(-1)!.every((m) => m.fcmToken !== 't1'));
  assert.equal(h.stored!.players[1].fcmToken, undefined);
  const n = h.pushes.length;
  await h.send(0, { type: 'move', from: '0e2', to: '0e4' });
  assert.deepEqual(h.pushes.slice(n).flat().map((m) => m.fcmToken), ['t2']);
});

test('unregisterPush, jeton unique par siège', async () => {
  const { h } = await fullRoom();
  await h.send(0, { type: 'registerPush', fcmToken: 'same' });
  await h.send(1, { type: 'registerPush', fcmToken: 'same' });
  assert.equal(h.stored!.players[0].fcmToken, undefined);
  assert.equal(h.stored!.players[1].fcmToken, 'same');
  await h.send(1, { type: 'unregisterPush' });
  assert.equal(h.stored!.players[1].fcmToken, undefined);
});

test('leave : en cours = abandon + jeton supprimé ; en attente = siège libéré', async () => {
  const { h } = await fullRoom();
  for (const i of [0, 1, 2]) await h.send(i, { type: 'registerPush', fcmToken: `t${i}` });
  await h.send(2, { type: 'leave' });
  assert.equal(h.stored!.players.length, 2);
  assert.equal(h.last(0, 'room').players.length, 2);
  await h.send(2, { type: 'registerPush', fcmToken: 'x' }); // ignoré : plus dans le salon
  assert.equal(h.stored!.players.length, 2);
  const h2 = (await fullRoom()).h;
  for (const i of [0, 1, 2]) await h2.send(i, { type: 'registerPush', fcmToken: `t${i}` });
  await h2.send(0, { type: 'start' });
  await h2.send(1, { type: 'leave' });
  assert.equal(h2.stored!.state!.active[1], false);
  assert.equal(h2.stored!.players[1].fcmToken, undefined);
  assert.ok(h2.pushes.at(-1)!.every((m) => m.fcmToken !== 't1'));
});

test('fin de partie : notification à tous puis suppression de tous les jetons', async () => {
  const { h } = await fullRoom('firstMate', 3);
  for (const i of [0, 1, 2]) await h.send(i, { type: 'registerPush', fcmToken: `t${i}` });
  await h.send(0, { type: 'start' });
  await h.send(1, { type: 'resign' });
  await h.send(0, { type: 'resign' });
  const last = h.pushes.at(-1)!;
  assert.equal(last[0].data.type, 'gameOver');
  assert.ok(h.stored!.players.every((p) => !p.fcmToken));
});

test('twoMates : un joueur maté reçoit au plus une notification finale puis plus rien', async () => {
  let sawElim = false;
  for (let seed = 1; seed <= 15 && !sawElim; seed++) {
    const { h } = await fullRoom('twoMates', seed);
    for (const i of [0, 1, 2]) await h.send(i, { type: 'registerPush', fcmToken: `t${i}` });
    await h.send(0, { type: 'start' });
    const rnd = rngFrom(seed * 31);
    const tokens = ['t0', 't1', 't2'];
    const gone = new Set<number>();
    let n = 0;
    while (!h.stored!.state!.result && n < 3000) {
      n++;
      const g = h.last(0, 'game');
      const before = h.pushes.length;
      const act = [...h.stored!.state!.active];
      const m = g.legalMoves[Math.floor(rnd() * g.legalMoves.length)];
      await h.send(g.turn, { type: 'move', from: m.from, to: m.to });
      const batch = h.pushes.slice(before).flat();
      for (const id of gone) assert.ok(batch.every((x) => x.fcmToken !== tokens[id]), 'notif à un éliminé');
      for (const i of [0, 1, 2]) {
        if (act[i] && !h.stored!.state!.active[i]) {
          gone.add(i);
          sawElim = true;
          assert.equal(h.stored!.players[i].fcmToken, undefined);
        }
      }
    }
  }
  assert.ok(sawElim);
});
