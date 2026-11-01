/* Turbo Couloirs — prototype de course infinie (Three.js r128).
   Formes simples provisoires : les modèles 3D définitifs (Meshy) remplaceront
   les fonctions make*() plus tard. */
(function () {
  'use strict';

  // ===== Réglages du jeu =====
  const CONFIG = {
    lanes: [-2.4, 0, 2.4],
    startSpeed: 14,      // mètres par seconde au départ
    maxSpeed: 36,
    accel: 0.3,          // gain de vitesse par seconde
    gravity: 40,
    jumpVel: 13.5,
    slideTime: 0.7,
    spawnZ: -120,        // distance où apparaissent les obstacles
    tiltThreshold: 12,   // degrés d'inclinaison pour changer de couloir
    coinValue: 10,
  };

  // ===== Publicité (désactivée) =====
  // Quand AdMob sera branché (voir ETAPES.md), passer enabled à true et
  // remplacer les TODO par les appels du plugin Capacitor AdMob.
  // Règle du projet : jamais de pub plein écran imposée.
  const ADS = {
    enabled: false,
    showBanner() {
      // TODO AdMob : bannière en bas, dans #ad-banner (sous le jeu, jamais par-dessus).
    },
    // Pub récompensée : toujours lancée par un clic du joueur, jamais automatiquement.
    showRewarded() {
      if (ADS.enabled) {
        // TODO AdMob : afficher la vidéo récompensée, résoudre true si elle est vue en entier.
        return Promise.resolve(false);
      }
      return simulateRewarded();
    },
  };

  function simulateRewarded() {
    return new Promise((resolve) => {
      const box = $('ad-sim');
      let n = 3;
      $('adCount').textContent = n;
      box.hidden = false;
      const timer = setInterval(() => {
        n -= 1;
        $('adCount').textContent = n;
        if (n <= 0) { clearInterval(timer); box.hidden = true; resolve(true); }
      }, 1000);
    });
  }

  // ===== Petits outils =====
  function $(id) { return document.getElementById(id); }
  function load(key, fallback) {
    try { const v = localStorage.getItem(key); return v === null ? fallback : JSON.parse(v); } catch (e) { return fallback; }
  }
  function save(key, value) {
    try { localStorage.setItem(key, JSON.stringify(value)); } catch (e) { /* stockage indisponible : on ignore */ }
  }
  function rand(a, b) { return a + Math.random() * (b - a); }
  function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

  // ===== Scène 3D =====
  const canvas = $('game');
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));

  const SKY = 0x8fd3ff;
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(SKY);
  scene.fog = new THREE.Fog(SKY, 45, 120);

  const camera = new THREE.PerspectiveCamera(60, 1, 0.1, 200);
  const CAM = { y: 5, z: 9.5, lookY: 1, lookZ: -8 };

  scene.add(new THREE.HemisphereLight(0xffffff, 0x5b7f4a, 0.85));
  const sun = new THREE.DirectionalLight(0xfff1d6, 0.75);
  sun.position.set(6, 12, 5);
  scene.add(sun);

  const mat = (color, extra) => new THREE.MeshLambertMaterial(Object.assign({ color }, extra || {}));

  // Piste d'athlétisme : texture dessinée sur un canvas, qui défile.
  const TRACK_W = 7.2;
  const TRACK_LEN = 240;
  const TEX_REPEAT = 24;
  const trackTex = (function () {
    const c = document.createElement('canvas');
    c.width = 256; c.height = 256;
    const g = c.getContext('2d');
    g.fillStyle = '#c8553d'; g.fillRect(0, 0, 256, 256);
    for (let i = 0; i < 900; i++) {
      g.fillStyle = Math.random() < 0.5 ? 'rgba(0,0,0,.07)' : 'rgba(255,255,255,.06)';
      g.fillRect(Math.random() * 256, Math.random() * 256, 2, 2);
    }
    g.fillStyle = '#fff6ea';
    [0, 256 / 3, 512 / 3, 256].forEach((x) => g.fillRect(x - 3, 0, 6, 256));
    g.fillStyle = 'rgba(255,246,234,.35)';
    g.fillRect(0, 0, 256, 5);
    const t = new THREE.CanvasTexture(c);
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.repeat.set(1, TEX_REPEAT);
    t.anisotropy = 4;
    return t;
  })();
  const track = new THREE.Mesh(new THREE.PlaneGeometry(TRACK_W, TRACK_LEN), new THREE.MeshLambertMaterial({ map: trackTex }));
  track.rotation.x = -Math.PI / 2;
  track.position.z = 12 - TRACK_LEN / 2;
  scene.add(track);

  const grass = new THREE.Mesh(new THREE.PlaneGeometry(120, TRACK_LEN), mat(0x5cb85c));
  grass.rotation.x = -Math.PI / 2;
  grass.position.set(0, -0.02, 12 - TRACK_LEN / 2);
  scene.add(grass);

  // Bordures blanches de la piste
  [-1, 1].forEach((s) => {
    const curb = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.2, TRACK_LEN), mat(0xfff6ea));
    curb.position.set(s * (TRACK_W / 2 + 0.15), 0.1, 12 - TRACK_LEN / 2);
    scene.add(curb);
  });

  // ===== Décor (arbres, fanions) qui défile sur les côtés =====
  const trunkGeo = new THREE.CylinderGeometry(0.18, 0.25, 1.2, 6);
  const leafGeo = new THREE.ConeGeometry(1.1, 2.6, 7);
  const bushGeo = new THREE.IcosahedronGeometry(0.9, 0);
  const trunkMat = mat(0x8d5a3b);
  const leafMats = [mat(0x2e8b57), mat(0x3fa34d), mat(0x1f7a4a)];
  const flagColors = [0xffc531, 0x3fa7ff, 0xff5d8f, 0xffffff];
  const scenery = [];

  function makeTree() {
    const g = new THREE.Group();
    const trunk = new THREE.Mesh(trunkGeo, trunkMat);
    trunk.position.y = 0.6;
    const leaves = new THREE.Mesh(leafGeo, pick(leafMats));
    leaves.position.y = 2.4;
    g.add(trunk, leaves);
    const s = rand(0.8, 1.4);
    g.scale.set(s, s, s);
    return g;
  }
  function makeBush() {
    const b = new THREE.Mesh(bushGeo, pick(leafMats));
    b.position.y = 0.5;
    b.scale.set(rand(0.8, 1.3), rand(0.6, 0.9), rand(0.8, 1.3));
    const g = new THREE.Group();
    g.add(b);
    return g;
  }
  function makeFlagPole() {
    const g = new THREE.Group();
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.06, 3.4, 5), mat(0xeeeeee));
    pole.position.y = 1.7;
    const flag = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.6, 0.9), mat(pick(flagColors)));
    flag.position.set(0, 3.0, -0.45);
    g.add(pole, flag);
    return g;
  }
  for (let i = 0; i < 44; i++) {
    const side = i % 2 === 0 ? -1 : 1;
    const kind = Math.random();
    const obj = kind < 0.55 ? makeTree() : kind < 0.85 ? makeBush() : makeFlagPole();
    const near = kind >= 0.85; // les fanions longent la piste
    obj.position.set(side * (near ? TRACK_W / 2 + 0.9 : rand(5.2, 12)), 0, 12 - (i / 44) * 130);
    scene.add(obj);
    scenery.push(obj);
  }

  // ===== Le coureur =====
  const player = (function () {
    const g = new THREE.Group();
    const body = new THREE.Group();
    const shirt = mat(0xff6b35);
    const skin = mat(0xffd2a1);
    const shorts = mat(0x2b3a8c);
    const shoe = mat(0xffffff);

    const torso = new THREE.Mesh(new THREE.CylinderGeometry(0.34, 0.3, 0.8, 10), shirt);
    torso.position.y = 1.15;
    const head = new THREE.Mesh(new THREE.SphereGeometry(0.28, 14, 10), skin);
    head.position.y = 1.8;
    const cap = new THREE.Mesh(new THREE.SphereGeometry(0.3, 14, 8, 0, Math.PI * 2, 0, Math.PI / 2), mat(0xffc531));
    cap.position.y = 1.86;
    const hips = new THREE.Mesh(new THREE.BoxGeometry(0.6, 0.25, 0.36), shorts);
    hips.position.y = 0.72;

    function limb(geo, material, x, y) {
      const pivot = new THREE.Group();
      pivot.position.set(x, y, 0);
      const m = new THREE.Mesh(geo, material);
      m.position.y = -geo.parameters.height / 2;
      pivot.add(m);
      return pivot;
    }
    const legGeo = new THREE.BoxGeometry(0.2, 0.62, 0.22);
    const armGeo = new THREE.BoxGeometry(0.14, 0.55, 0.16);
    const legL = limb(legGeo, shorts, -0.16, 0.66);
    const legR = limb(legGeo, shorts, 0.16, 0.66);
    [legL, legR].forEach((leg) => {
      const s = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.12, 0.34), shoe);
      s.position.set(0, -0.64, -0.05);
      leg.add(s);
    });
    const armL = limb(armGeo, skin, -0.44, 1.45);
    const armR = limb(armGeo, skin, 0.44, 1.45);
    body.add(torso, head, cap, hips, legL, legR, armL, armR);
    g.add(body);

    const shadow = new THREE.Mesh(new THREE.CircleGeometry(0.5, 20), new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.25 }));
    shadow.rotation.x = -Math.PI / 2;
    shadow.position.y = 0.02;
    scene.add(shadow);
    scene.add(g);

    return { group: g, body, legL, legR, armL, armR, shadow };
  })();

  // ===== Obstacles et pièces =====
  const GEO = {
    hurdleBar: new THREE.BoxGeometry(1.9, 0.28, 0.12),
    hurdleLeg: new THREE.BoxGeometry(0.1, 0.9, 0.1),
    highBar: new THREE.BoxGeometry(2.2, 0.35, 0.3),
    highPole: new THREE.BoxGeometry(0.16, 2.6, 0.16),
    crate: new THREE.BoxGeometry(1.9, 2.4, 2.8),
    stripe: new THREE.BoxGeometry(1.94, 0.25, 2.84),
    coin: new THREE.CylinderGeometry(0.34, 0.34, 0.08, 18),
  };
  const MAT = {
    white: mat(0xffffff),
    red: mat(0xe63946),
    dark: mat(0x2b2f45),
    yellow: mat(0xffc531),
    crates: [mat(0x3fa7ff), mat(0x9b5de5), mat(0x00b894)],
    coin: new THREE.MeshLambertMaterial({ color: 0xffc531, emissive: 0x6b4a00 }),
  };

  function makeHurdle() { // haie basse : sauter
    const g = new THREE.Group();
    const bar = new THREE.Mesh(GEO.hurdleBar, MAT.white);
    bar.position.y = 0.82;
    const band = new THREE.Mesh(new THREE.BoxGeometry(0.6, 0.29, 0.13), MAT.red);
    band.position.y = 0.82;
    const l1 = new THREE.Mesh(GEO.hurdleLeg, MAT.dark); l1.position.set(-0.85, 0.45, 0);
    const l2 = new THREE.Mesh(GEO.hurdleLeg, MAT.dark); l2.position.set(0.85, 0.45, 0);
    g.add(bar, band, l1, l2);
    return g;
  }
  function makeHighBar() { // barre haute : glisser dessous
    const g = new THREE.Group();
    const bar = new THREE.Mesh(GEO.highBar, MAT.yellow);
    bar.position.y = 1.75;
    const stripe = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.36, 0.31), MAT.dark);
    stripe.position.y = 1.75;
    const p1 = new THREE.Mesh(GEO.highPole, MAT.dark); p1.position.set(-1.05, 1.3, 0);
    const p2 = new THREE.Mesh(GEO.highPole, MAT.dark); p2.position.set(1.05, 1.3, 0);
    g.add(bar, stripe, p1, p2);
    return g;
  }
  function makeCrate() { // grosse caisse : changer de couloir
    const g = new THREE.Group();
    const c = new THREE.Mesh(GEO.crate, pick(MAT.crates));
    c.position.y = 1.2;
    const s = new THREE.Mesh(GEO.stripe, MAT.white);
    s.position.y = 1.9;
    g.add(c, s);
    return g;
  }
  function makeCoin() {
    const m = new THREE.Mesh(GEO.coin, MAT.coin);
    m.rotation.x = Math.PI / 2;
    const g = new THREE.Group();
    g.add(m);
    return g;
  }

  // Boîtes de collision (relatives au centre du couloir)
  const HIT = {
    hurdle: { w: 0.95, y0: 0, y1: 0.95, d: 0.2 },
    high: { w: 1.1, y0: 1.3, y1: 2.6, d: 0.25 },
    crate: { w: 0.95, y0: 0, y1: 2.4, d: 1.4 },
  };

  let things = []; // {type, lane, z, mesh, taken}

  function addThing(type, lane, z, y) {
    const mesh = type === 'coin' ? makeCoin() : type === 'hurdle' ? makeHurdle() : type === 'high' ? makeHighBar() : makeCrate();
    mesh.position.set(CONFIG.lanes[lane], y || 0, z);
    scene.add(mesh);
    things.push({ type, lane, z, y: y || 0, mesh, taken: false });
  }

  function clearThings() {
    things.forEach((t) => scene.remove(t.mesh));
    things = [];
  }

  function spawnRow(z) {
    const lanes = [0, 1, 2].sort(() => Math.random() - 0.5);
    const hard = Math.min(1, run.time / 60);
    const count = Math.random() < 0.35 + hard * 0.4 ? 2 : 1;
    const blocked = lanes.slice(0, count);
    const free = lanes.slice(count);
    blocked.forEach((lane) => {
      const r = Math.random();
      addThing(r < 0.4 ? 'crate' : r < 0.7 ? 'hurdle' : 'high', lane, z);
    });
    if (Math.random() < 0.75) {
      const lane = pick(free);
      for (let i = 0; i < 5; i++) addThing('coin', lane, z - 3 - i * 2.2, 0.9);
    }
  }

  // ===== État de la partie =====
  const run = {
    state: 'menu', // menu | play | pause | dead
    speed: 0, dist: 0, time: 0, coins: 0,
    lane: 1, x: 0, y: 0, vy: 0, slide: 0,
    untilNext: 0, invincible: 0, continued: false, shake: 0, deadTimer: 0,
  };
  let best = load('turbo.best', 0);
  $('bestMenu').textContent = best;

  function score() { return Math.floor(run.dist) + run.coins * CONFIG.coinValue; }

  function show(id) {
    ['menu', 'pause', 'over'].forEach((s) => { $(s).hidden = s !== id; });
    $('hud').hidden = !(run.state === 'play' || run.state === 'pause');
  }

  function startRun() {
    clearThings();
    Object.assign(run, {
      state: 'play', speed: CONFIG.startSpeed, dist: 0, time: 0, coins: 0,
      lane: 1, x: 0, y: 0, vy: 0, slide: 0, untilNext: 20, invincible: 0, continued: false, shake: 0,
    });
    $('coins').textContent = '0';
    show(null);
    ADS.showBanner();
  }

  function die() {
    if (run.state !== 'play') return;
    run.state = 'dead';
    run.shake = 0.4;
    run.deadTimer = 0.7;
    if (navigator.vibrate) { try { navigator.vibrate(120); } catch (e) { /* ignore */ } }
  }

  function showGameOver() {
    const s = score();
    const isBest = s > best;
    if (isBest) { best = s; save('turbo.best', best); }
    $('finalScore').textContent = s;
    $('finalCoins').textContent = run.coins;
    $('finalBest').textContent = best;
    $('bestMenu').textContent = best;
    $('newBest').hidden = !isBest;
    $('continueBtn').hidden = run.continued; // un seul « continuer » par partie
    show('over');
  }

  function continueRun() {
    // On retire les obstacles proches et on donne 2 s d'invincibilité.
    things = things.filter((t) => {
      if (t.z > -35 && t.type !== 'coin') { scene.remove(t.mesh); return false; }
      return true;
    });
    run.continued = true;
    run.state = 'play';
    run.invincible = 2;
    run.y = 0; run.vy = 0; run.slide = 0;
    show(null);
  }

  // ===== Commandes =====
  function moveLane(dir) {
    if (run.state !== 'play') return;
    run.lane = Math.max(0, Math.min(2, run.lane + dir));
  }
  function jump() {
    if (run.state !== 'play') return;
    if (run.y <= 0.001) { run.vy = CONFIG.jumpVel; run.slide = 0; }
  }
  function slide() {
    if (run.state !== 'play') return;
    if (run.y > 0.001) run.vy = -CONFIG.jumpVel * 1.4; // retombe vite
    run.slide = CONFIG.slideTime;
  }

  // Glisser du doigt : l'action part dès que le doigt a assez bougé.
  let touch = null;
  canvas.addEventListener('touchstart', (e) => {
    const t = e.changedTouches[0];
    touch = { x: t.clientX, y: t.clientY, done: false };
    e.preventDefault();
  }, { passive: false });
  canvas.addEventListener('touchmove', (e) => {
    if (!touch || touch.done) return;
    const t = e.changedTouches[0];
    const dx = t.clientX - touch.x;
    const dy = t.clientY - touch.y;
    if (Math.max(Math.abs(dx), Math.abs(dy)) < 28) return;
    touch.done = true;
    if (Math.abs(dx) > Math.abs(dy)) moveLane(dx > 0 ? 1 : -1);
    else if (dy < 0) jump();
    else slide();
    e.preventDefault();
  }, { passive: false });
  canvas.addEventListener('touchend', () => { touch = null; });

  window.addEventListener('keydown', (e) => {
    const k = e.key;
    if (k === 'ArrowLeft' || k === 'a' || k === 'q') moveLane(-1);
    else if (k === 'ArrowRight' || k === 'd') moveLane(1);
    else if (k === 'ArrowUp' || k === 'w' || k === 'z' || k === ' ') jump();
    else if (k === 'ArrowDown' || k === 's') slide();
    else if (k === 'Escape' || k === 'p') { if (run.state === 'play') pauseGame(); else if (run.state === 'pause') resumeGame(); return; }
    else if (k === 'Enter' && (run.state === 'menu' || run.state === 'dead') && document.activeElement === document.body) startRun();
    else return;
    if (run.state === 'play') e.preventDefault();
  });

  // Inclinaison du téléphone (facultatif). Sur iPhone, il faut demander l'autorisation.
  const tilt = { on: false, zone: 1, seen: false };
  function onOrientation(e) {
    if (e.gamma === null || e.gamma === undefined) return;
    tilt.seen = true;
    if (!tilt.on || run.state !== 'play') return;
    const g = e.gamma;
    const zone = g < -CONFIG.tiltThreshold ? 0 : g > CONFIG.tiltThreshold ? 2 : 1;
    if (zone !== tilt.zone) { tilt.zone = zone; run.lane = zone; }
  }
  async function toggleTilt() {
    const note = $('tiltNote');
    if (tilt.on) { tilt.on = false; updateTiltBtn(); note.textContent = ''; return; }
    try {
      if (typeof DeviceOrientationEvent !== 'undefined' && typeof DeviceOrientationEvent.requestPermission === 'function') {
        const answer = await DeviceOrientationEvent.requestPermission();
        if (answer !== 'granted') { note.textContent = 'Autorisation refusée. Les glissements du doigt marchent toujours.'; return; }
      }
    } catch (err) {
      note.textContent = 'Inclinaison non disponible ici. Utilise les glissements du doigt.';
      return;
    }
    window.addEventListener('deviceorientation', onOrientation);
    tilt.on = true;
    updateTiltBtn();
    note.textContent = 'Penche le téléphone à gauche ou à droite.';
    setTimeout(() => {
      if (tilt.on && !tilt.seen) note.textContent = 'Aucun capteur détecté ici. Utilise les glissements du doigt.';
    }, 1500);
  }
  function updateTiltBtn() { $('tiltBtn').textContent = 'Inclinaison : ' + (tilt.on ? 'oui' : 'non'); }

  function pauseGame() { if (run.state === 'play') { run.state = 'pause'; show('pause'); } }
  function resumeGame() { if (run.state === 'pause') { run.state = 'play'; show(null); last = performance.now(); } }
  function toMenu() { clearThings(); run.state = 'menu'; run.lane = 1; show('menu'); }

  $('playBtn').addEventListener('click', startRun);
  $('replayBtn').addEventListener('click', startRun);
  $('tiltBtn').addEventListener('click', toggleTilt);
  $('pauseBtn').addEventListener('click', pauseGame);
  $('resumeBtn').addEventListener('click', resumeGame);
  $('quitBtn').addEventListener('click', toMenu);
  $('menuBtn').addEventListener('click', toMenu);
  $('continueBtn').addEventListener('click', async () => {
    $('continueBtn').disabled = true;
    const ok = await ADS.showRewarded();
    $('continueBtn').disabled = false;
    if (ok) continueRun();
  });
  document.addEventListener('visibilitychange', () => { if (document.hidden) pauseGame(); });

  // ===== Taille de l'écran =====
  function resize() {
    const w = canvas.clientWidth || window.innerWidth;
    const h = canvas.clientHeight || window.innerHeight;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    // En portrait, on élargit le champ pour voir les 3 couloirs.
    const hfov = 50 * Math.PI / 180;
    const vfov = 2 * Math.atan(Math.tan(hfov / 2) / camera.aspect) * 180 / Math.PI;
    camera.fov = Math.max(58, Math.min(88, vfov));
    camera.updateProjectionMatrix();
  }
  window.addEventListener('resize', resize);
  resize();

  // ===== Boucle de jeu =====
  let last = performance.now();
  let clock = 0;

  function overlaps(t) {
    const h = HIT[t.type];
    if (!h) return false;
    const px = run.x;
    const top = run.y + (run.slide > 0 ? 0.85 : 1.95);
    const bottom = run.y;
    const dx = Math.abs(px - CONFIG.lanes[t.lane]);
    return dx < h.w + 0.3 && Math.abs(t.z) < h.d + 0.3 && bottom < h.y1 && top > h.y0;
  }

  function update(dt) {
    clock += dt;
    const playing = run.state === 'play';
    const moving = playing || run.state === 'menu';
    const speed = playing ? run.speed : run.state === 'menu' ? 6 : 0;

    if (playing) {
      run.time += dt;
      run.speed = Math.min(CONFIG.maxSpeed, CONFIG.startSpeed + CONFIG.accel * run.time);
      run.dist += speed * dt;
      run.invincible = Math.max(0, run.invincible - dt);

      // Saut / glissade
      run.vy -= CONFIG.gravity * dt;
      run.y = Math.max(0, run.y + run.vy * dt);
      if (run.y === 0) run.vy = 0;
      run.slide = Math.max(0, run.slide - dt);

      // Apparition des obstacles
      run.untilNext -= speed * dt;
      if (run.untilNext <= 0) {
        spawnRow(CONFIG.spawnZ);
        run.untilNext = rand(17, 26);
      }
    }

    if (moving) {
      const step = speed * dt;
      trackTex.offset.y += step * TEX_REPEAT / TRACK_LEN;
      scenery.forEach((o) => {
        o.position.z += step;
        if (o.position.z > 14) o.position.z -= 130;
      });
      things.forEach((t) => { t.z += step; t.mesh.position.z = t.z; });
    }

    // Collisions et pièces
    if (playing) {
      for (const t of things) {
        if (t.taken) continue;
        if (t.type === 'coin') {
          if (Math.abs(t.z) < 0.8 && Math.abs(run.x - CONFIG.lanes[t.lane]) < 0.8 && run.y < 2.2) {
            t.taken = true;
            t.mesh.visible = false;
            run.coins += 1;
            $('coins').textContent = run.coins;
            const box = $('coinBox');
            box.classList.remove('bump'); void box.offsetWidth; box.classList.add('bump');
          }
        } else if (run.invincible <= 0 && overlaps(t)) {
          die();
          break;
        }
      }
      things = things.filter((t) => {
        if (t.z > 14) { scene.remove(t.mesh); return false; }
        return true;
      });
      $('score').textContent = score();
    }

    if (run.state === 'dead') {
      run.deadTimer -= dt;
      if (run.deadTimer <= 0 && $('over').hidden) showGameOver();
    }

    // Animation du coureur
    const targetX = CONFIG.lanes[run.lane];
    run.x += (targetX - run.x) * Math.min(1, dt * 14);
    const p = player;
    p.group.position.set(run.x, run.y, 0);
    p.shadow.position.x = run.x;
    const sh = Math.max(0.4, 1 - run.y * 0.15);
    p.shadow.scale.set(sh, sh, sh);
    p.group.rotation.z = (run.x - targetX) * 0.12;

    const sliding = run.slide > 0;
    p.body.rotation.x = sliding ? -1.1 : 0;
    p.body.position.y = sliding ? 0.25 : 0;
    p.body.position.z = sliding ? 0.6 : 0;
    const swing = (moving && run.y === 0 && !sliding) ? Math.sin(clock * (8 + speed * 0.35)) * 0.9 : 0;
    const airPose = run.y > 0 ? 0.6 : 0;
    p.legL.rotation.x = swing + airPose;
    p.legR.rotation.x = -swing - airPose * 0.3;
    p.armL.rotation.x = -swing * 0.8;
    p.armR.rotation.x = swing * 0.8;
    p.group.visible = run.invincible > 0 ? Math.floor(clock * 12) % 2 === 0 : true;

    // Pièces qui tournent
    things.forEach((t) => { if (t.type === 'coin') t.mesh.rotation.y = clock * 3; });

    // Caméra
    run.shake = Math.max(0, run.shake - dt);
    const sx = run.shake > 0 ? rand(-1, 1) * run.shake * 0.6 : 0;
    const sy = run.shake > 0 ? rand(-1, 1) * run.shake * 0.6 : 0;
    camera.position.set(run.x * 0.4 + sx, CAM.y + run.y * 0.25 + sy, CAM.z);
    camera.lookAt(run.x * 0.3, CAM.lookY + run.y * 0.2, CAM.lookZ);
  }

  function frame(now) {
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    update(dt);
    renderer.render(scene, camera);
    requestAnimationFrame(frame);
  }
  show('menu');
  requestAnimationFrame(frame);
})();
