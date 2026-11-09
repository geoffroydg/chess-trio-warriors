// Smoke test du worker déployé : partie solo contre 2 bots « difficile ».
// Usage : node scripts/smoke.mjs [URL]   (défaut : SMOKE_URL ou le worker de production)
// Échoue si un bot met plus de 6 s à jouer, si le serveur renvoie une erreur ou si rien n'avance.
import { appendFileSync } from 'node:fs';

const BASE = (process.argv[2] || process.env.SMOKE_URL || 'https://chess-trio-warriors.geoffroyd.workers.dev').replace(/\/+$/, '');
const HUMAN_TURNS = Number(process.env.SMOKE_TURNS || 8);
const BOT_LIMIT_MS = 6000;
const GLOBAL_TIMEOUT_MS = 150_000;

const rows = [];
let failure = null;

function summary(ok) {
  const lines = [
    `## Smoke test du serveur ${ok ? '✅' : '❌'}`,
    `Worker : \`${BASE}\``,
    '',
    '| # | Joueur | Coup | Délai (ms) |',
    '|---|--------|------|-----------:|',
    ...rows.map((r, i) => `| ${i + 1} | ${r.who} | ${r.move} | ${r.ms} |`),
  ];
  const bots = rows.filter((r) => r.who !== 'humain').map((r) => r.ms);
  if (bots.length) lines.push('', `Bots : ${bots.length} coups, max ${Math.max(...bots)} ms, moyenne ${Math.round(bots.reduce((a, b) => a + b, 0) / bots.length)} ms.`);
  if (failure) lines.push('', `**Échec :** ${failure}`);
  const text = lines.join('\n') + '\n';
  console.log(text);
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, text);
}

async function waitHealthy() {
  for (let i = 0; i < 10; i++) {
    try {
      const r = await fetch(`${BASE}/health`);
      if (r.ok) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 3000));
  }
  throw new Error('/health ne répond pas');
}

async function main() {
  await waitHealthy();
  const res = await fetch(`${BASE}/rooms`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ pseudo: 'Smoke', mode: 'firstMate', bots: [{ level: 'difficile' }, { level: 'difficile' }] }),
  });
  const created = await res.json();
  if (res.status !== 201) throw new Error(`POST /rooms : ${res.status} ${JSON.stringify(created)}`);
  const { code, playerToken } = created;
  console.log(`Salon solo ${code} créé.`);

  const wsUrl = `${BASE.replace(/^http/, 'ws')}/rooms/${code}/ws?token=${encodeURIComponent(playerToken)}`;
  const ws = new WebSocket(wsUrl);

  await new Promise((resolve, reject) => {
    let humanTurns = 0;
    let lastPly = -1;
    let waitingSince = Date.now();
    let botTimer = null;
    const done = (err) => {
      clearTimeout(botTimer);
      clearTimeout(global);
      try { ws.close(); } catch {}
      err ? reject(err) : resolve();
    };
    const global = setTimeout(() => done(new Error('délai global dépassé')), GLOBAL_TIMEOUT_MS);
    ws.addEventListener('error', () => done(new Error('erreur WebSocket')));
    ws.addEventListener('close', (e) => done(humanTurns >= HUMAN_TURNS ? null : new Error(`WebSocket fermé (${e.code})`)));
    ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(String(ev.data));
      if (msg.type === 'error') return done(new Error(`erreur serveur : ${msg.code} ${msg.message}`));
      if (msg.type !== 'game') return;
      const ply = msg.state.ply;
      if (ply === lastPly) return; // rediffusion sans nouveau coup
      const now = Date.now();
      const ev2 = msg.lastEvent;
      if (ev2 && ev2.kind === 'move') {
        const who = ev2.player === 0 ? 'humain' : `bot ${ev2.player}`;
        rows.push({ who, move: `${ev2.move.from}-${ev2.move.to}`, ms: now - waitingSince });
        if (ev2.player !== 0 && ev2.auto) return done(new Error(`le bot ${ev2.player} a été joué par le minuteur`));
      }
      lastPly = ply;
      waitingSince = now;
      clearTimeout(botTimer);
      if (msg.over) return done(null);
      if (msg.turn === 0) {
        if (humanTurns >= HUMAN_TURNS) return done(null);
        humanTurns++;
        const m = msg.legalMoves[Math.floor(Math.random() * msg.legalMoves.length)];
        ws.send(JSON.stringify({ type: 'move', from: m.from, to: m.to }));
      } else {
        botTimer = setTimeout(
          () => done(new Error(`le bot ${msg.turn} n'a pas joué en moins de ${BOT_LIMIT_MS / 1000} s`)),
          BOT_LIMIT_MS,
        );
      }
    });
  });
}

main()
  .then(() => summary(true))
  .catch((e) => {
    failure = e.message;
    summary(false);
    process.exit(1);
  });
