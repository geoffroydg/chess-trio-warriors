/* Turbo Couloirs — course infinie (Three.js r128).
   Tout est dessiné dans le code (formes + textures peintes sur canvas).
   Les modèles 3D Meshy pourront remplacer les fonctions make*() plus tard. */
(function () {
  'use strict';

  // =====================================================================
  // Réglages
  // =====================================================================
  const CONFIG = {
    lanes: [-2.4, 0, 2.4],
    startSpeed: 14,       // m/s au départ
    gravity: 42,
    jumpVel: 14,
    slideTime: 0.7,
    spawnZ: -140,         // distance où apparaissent les obstacles
    levelLength: 400,     // mètres par niveau
    tiltThreshold: 12,
    coinValue: 10,
  };

  // Difficulté : la vitesse accélère sans plafond, les rangées se resserrent,
  // les obstacles se multiplient. Vers 2 min 30 la course devient impossible.
  const speedAt = (t) => CONFIG.startSpeed + 0.25 * t + 0.0012 * t * t;
  const gapAt = (t) => Math.max(8, 24 - 0.07 * t);

  // ----- Bonus et boutique -----
  const ICONS = {
    magnet: 'M5 3h5v8a2 2 0 0 0 4 0V3h5v8a7 7 0 0 1-14 0V3zm0 2v2h5V5H5zm9 0v2h5V5h-5z',
    shield: 'M12 2l8 3v6c0 5.2-3.4 9.4-8 11-4.6-1.6-8-5.8-8-11V5l8-3z',
    double: 'M9 3a6 6 0 1 1 0 12A6 6 0 0 1 9 3zm6 6a6 6 0 1 1 0 12 6 6 0 0 1 0-12z',
    rocket: 'M12 1.5c3.4 2.2 5.2 6.2 5.2 10.4l-2.3 3.4H9.1l-2.3-3.4C6.8 7.7 8.6 3.7 12 1.5zm0 6a2 2 0 1 0 0 4 2 2 0 0 0 0-4zM8.6 16.3L5.5 21l4.4-1.4zm6.8 0l3.1 4.7-4.4-1.4zM10.6 17h2.8L12 22.5z',
    slow: 'M6 2h12v2.5l-4.6 7.5 4.6 7.5V22H6v-2.5l4.6-7.5L6 4.5V2zm3 3l3 4.8L15 5H9z',
    luck: 'M12 2l2.9 6.6 7.1.6-5.4 4.7 1.6 7L12 17.2 5.8 20.9l1.6-7L2 9.2l7.1-.6z',
    pause: 'M6 4h4v16H6zM14 4h4v16h-4z',
  };
  const POWERS = {
    magnet: { name: 'Aimant', color: '#ff4f6d', base: 6, per: 2, unlock: 0 },
    shield: { name: 'Bouclier', color: '#3d9cff', base: 7, per: 2.5, unlock: 0 },
    double: { name: 'Pièces x2', color: '#f5a300', base: 8, per: 3, unlock: 0 },
    rocket: { name: 'Fusée', color: '#ff7a1a', base: 3, per: 1, unlock: 1500 },
    slow: { name: 'Sablier', color: '#9b5de5', base: 4, per: 1.2, unlock: 2500 },
  };
  const LUCK = { name: 'Chance', color: '#2fd18b' };
  const LEVEL_COST = [250, 600, 1400, 3000, 6000];
  const LUCK_COST = [400, 900, 2000, 4500, 9000];
  const MAX_LVL = 5;

  // Valeurs qui dépendent des achats
  const dur = (id, lvl) => Math.round((POWERS[id].base + POWERS[id].per * lvl) * 10) / 10;
  const shieldHits = (lvl) => (lvl >= 4 ? 2 : 1);
  const coinMult = (lvl) => (lvl >= 5 ? 3 : 2);
  const magnetRadius = (lvl) => (lvl >= 3 ? 22 : 14);
  const slowFactor = (lvl) => (lvl >= 5 ? 0.5 : lvl >= 3 ? 0.58 : 0.65);
  const bonusInterval = (luck) => 650 - 85 * luck;          // mètres entre deux bonus
  const doubleChance = (luck) => (luck >= 5 ? 0.5 : luck >= 3 ? 0.3 : 0);

  // =====================================================================
  // Publicité (désactivée)
  // =====================================================================
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

  // =====================================================================
  // Outils
  // =====================================================================
  function $(id) { return document.getElementById(id); }
  function load(key, fallback) {
    try { const v = localStorage.getItem(key); return v === null ? fallback : JSON.parse(v); } catch (e) { return fallback; }
  }
  function save(key, value) {
    try { localStorage.setItem(key, JSON.stringify(value)); } catch (e) { /* stockage indisponible */ }
  }
  const rand = (a, b) => a + Math.random() * (b - a);
  const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const fmt = (n) => Math.floor(n).toLocaleString('fr-FR');
  function shuffle(a) { for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; }
  const svg = (id) => '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill-rule="evenodd" d="' + ICONS[id] + '"/></svg>';

  // =====================================================================
  // Rendu
  // =====================================================================
  const canvas = $('game');
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  const maxAniso = Math.min(8, renderer.capabilities.getMaxAnisotropy());

  const scene = new THREE.Scene();
  scene.fog = new THREE.Fog(0xbfe6ff, 60, 165);
  const camera = new THREE.PerspectiveCamera(60, 1, 0.1, 420);

  // ----- Textures peintes -----
  function canvasTex(w, h, draw, rx, ry) {
    const c = document.createElement('canvas');
    c.width = w; c.height = h;
    draw(c.getContext('2d'), w, h);
    const t = new THREE.CanvasTexture(c);
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.repeat.set(rx || 1, ry || 1);
    t.anisotropy = maxAniso;
    return t;
  }
  // Textures avec texte : redessinées quand la police Bungee est chargée.
  const textTextures = [];
  function textTex(w, h, draw) {
    const t = canvasTex(w, h, draw);
    t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping;
    textTextures.push({ t, draw });
    return t;
  }
  const DISPLAY_FONT = (px) => px + 'px Bungee, "Arial Black", Impact, sans-serif';
  if (document.fonts && document.fonts.load) {
    document.fonts.load(DISPLAY_FONT(64)).then(() => {
      textTextures.forEach(({ t, draw }) => {
        const g = t.image.getContext('2d');
        g.clearRect(0, 0, t.image.width, t.image.height);
        draw(g, t.image.width, t.image.height);
        t.needsUpdate = true;
      });
    }).catch(() => {});
  }
  function speckle(g, w, h, n, dark, light) {
    for (let i = 0; i < n; i++) {
      g.fillStyle = Math.random() < 0.5 ? dark : light;
      g.fillRect(Math.random() * w, Math.random() * h, 1 + Math.random() * 2, 1 + Math.random() * 2);
    }
  }
  const glowTex = canvasTex(128, 128, (g) => {
    const r = g.createRadialGradient(64, 64, 0, 64, 64, 64);
    r.addColorStop(0, 'rgba(255,255,255,1)');
    r.addColorStop(0.25, 'rgba(255,255,255,.55)');
    r.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = r; g.fillRect(0, 0, 128, 128);
  });
  const dotTex = canvasTex(32, 32, (g) => {
    const r = g.createRadialGradient(16, 16, 0, 16, 16, 16);
    r.addColorStop(0, 'rgba(255,255,255,1)');
    r.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = r; g.fillRect(0, 0, 32, 32);
  });

  const std = (color, o) => new THREE.MeshStandardMaterial(Object.assign({ color, roughness: 0.7, metalness: 0 }, o || {}));
  const lam = (color, o) => new THREE.MeshLambertMaterial(Object.assign({ color }, o || {}));
  const additive = (color, opacity, o) => new THREE.MeshBasicMaterial(Object.assign({
    color, transparent: true, opacity, blending: THREE.AdditiveBlending, depthWrite: false,
  }, o || {}));

  // ----- Ciel (dégradé + soleil) -----
  const skyMat = new THREE.ShaderMaterial({
    uniforms: {
      top: { value: new THREE.Color() }, hor: { value: new THREE.Color() }, bottom: { value: new THREE.Color() },
      sunColor: { value: new THREE.Color() }, sunDir: { value: new THREE.Vector3(0.3, 0.3, -1).normalize() },
      stars: { value: 0 },
    },
    vertexShader: 'varying vec3 vDir; void main(){ vDir = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
    fragmentShader: [
      'uniform vec3 top; uniform vec3 hor; uniform vec3 bottom; uniform vec3 sunColor; uniform vec3 sunDir; uniform float stars;',
      'varying vec3 vDir;',
      'float hash(vec3 p){ return fract(sin(dot(p, vec3(12.9898,78.233,45.164))) * 43758.5453); }',
      'void main(){',
      '  float h = vDir.y;',
      '  vec3 c = h > 0.0 ? mix(hor, top, pow(clamp(h,0.0,1.0), 0.6)) : mix(hor, bottom, pow(clamp(-h,0.0,1.0), 0.35));',
      '  float s = max(dot(vDir, normalize(sunDir)), 0.0);',
      '  c += sunColor * (pow(s, 900.0) * 1.6 + pow(s, 24.0) * 0.28 + pow(s, 4.0) * 0.08);',
      '  vec3 q = floor(vDir * 220.0);',
      '  float st = step(0.9965, hash(q)) * smoothstep(0.05, 0.4, h) * stars;',
      '  c += vec3(st);',
      '  gl_FragColor = vec4(c, 1.0);',
      '}',
    ].join('\n'),
    side: THREE.BackSide, depthWrite: false,
  });
  const sky = new THREE.Mesh(new THREE.SphereGeometry(300, 32, 16), skyMat);
  sky.renderOrder = -1;
  scene.add(sky);

  // ----- Lumières -----
  const hemi = new THREE.HemisphereLight(0xdff1ff, 0x6b8f5a, 0.8);
  scene.add(hemi);
  const sun = new THREE.DirectionalLight(0xfff1d6, 1);
  sun.castShadow = true;
  sun.shadow.mapSize.set(1024, 1024);
  const sc = sun.shadow.camera;
  sc.left = -9; sc.right = 9; sc.top = 14; sc.bottom = -14; sc.near = 1; sc.far = 60;
  sun.shadow.bias = -0.0008;
  scene.add(sun, sun.target);
  sun.target.position.set(0, 0, -8);
  const flood = new THREE.DirectionalLight(0xe8f0ff, 0); // projecteurs du stade, la nuit
  flood.position.set(0, 20, 10);
  scene.add(flood);

  // ----- Ambiances : elles changent à chaque niveau -----
  const PHASES = [
    { name: 'Matin', top: 0x3f8fef, hor: 0xcdeeff, bottom: 0x8fbf8a, sun: 0xfff0d0, sunI: 1.0, hemiSky: 0xe3f2ff, hemiGround: 0x6b8f5a, hemiI: 0.78, lamps: 0, flood: 0, stars: 0, dir: [0.5, 0.42, -1] },
    { name: 'Plein soleil', top: 0x1f6fe0, hor: 0xffe8c0, bottom: 0x96b77a, sun: 0xffffff, sunI: 1.15, hemiSky: 0xfff6e0, hemiGround: 0x7a8f50, hemiI: 0.8, lamps: 0, flood: 0, stars: 0, dir: [-0.2, 0.8, -1] },
    { name: 'Coucher de soleil', top: 0x2b2c78, hor: 0xff8a55, bottom: 0x6a4a60, sun: 0xffa060, sunI: 0.95, hemiSky: 0xffc2a0, hemiGround: 0x5a4060, hemiI: 0.62, lamps: 0.55, flood: 0.25, stars: 0.2, dir: [-0.6, 0.08, -1] },
    { name: 'Nuit sous les projecteurs', top: 0x050920, hor: 0x24306c, bottom: 0x101530, sun: 0x9fb4ff, sunI: 0.35, hemiSky: 0x7080d0, hemiGround: 0x1a2040, hemiI: 0.5, lamps: 1, flood: 0.75, stars: 1, dir: [0.4, 0.5, -1] },
  ];
  const phaseNow = {
    top: new THREE.Color(), hor: new THREE.Color(), bottom: new THREE.Color(), sun: new THREE.Color(),
    hemiSky: new THREE.Color(), hemiGround: new THREE.Color(), dir: new THREE.Vector3(),
    sunI: 1, hemiI: 0.8, lamps: 0, flood: 0, stars: 0,
  };
  let phaseTarget = PHASES[0];
  const COLOR_KEYS = ['top', 'hor', 'bottom', 'sun', 'hemiSky', 'hemiGround'];
  PHASES.forEach((p) => {
    p.c = {};
    COLOR_KEYS.forEach((c) => { p.c[c] = new THREE.Color(p[c]); });
    p.v = new THREE.Vector3().fromArray(p.dir).normalize();
  });
  function applyPhase(p, k) {
    COLOR_KEYS.forEach((c) => phaseNow[c].lerp(p.c[c], k));
    phaseNow.dir.lerp(p.v, k);
    ['sunI', 'hemiI', 'lamps', 'flood', 'stars'].forEach((c) => { phaseNow[c] += (p[c] - phaseNow[c]) * k; });
    skyMat.uniforms.top.value.copy(phaseNow.top);
    skyMat.uniforms.hor.value.copy(phaseNow.hor);
    skyMat.uniforms.bottom.value.copy(phaseNow.bottom);
    skyMat.uniforms.sunColor.value.copy(phaseNow.sun);
    skyMat.uniforms.sunDir.value.copy(phaseNow.dir);
    skyMat.uniforms.stars.value = phaseNow.stars;
    scene.fog.color.copy(phaseNow.hor);
    hemi.color.copy(phaseNow.hemiSky);
    hemi.groundColor.copy(phaseNow.hemiGround);
    hemi.intensity = phaseNow.hemiI;
    sun.color.copy(phaseNow.sun);
    sun.intensity = phaseNow.sunI;
    sun.position.set(phaseNow.dir.x * 20, Math.max(6, phaseNow.dir.y * 30), 10);
    flood.intensity = phaseNow.flood;
    lampMat.color.setScalar(0.25 + phaseNow.lamps * 0.75);
    lampGlowMat.opacity = phaseNow.lamps * 0.85;
  }

  // =====================================================================
  // Piste et stade
  // =====================================================================
  const TRACK_W = 7.2;
  const TRACK_LEN = 300;
  const TRACK_Z = 14 - TRACK_LEN / 2;
  const TILE = 20; // mètres par motif de texture

  const trackTex = canvasTex(512, 512, (g, w, h) => {
    const grd = g.createLinearGradient(0, 0, w, 0);
    grd.addColorStop(0, '#c24b30'); grd.addColorStop(0.5, '#d2573a'); grd.addColorStop(1, '#c24b30');
    g.fillStyle = grd; g.fillRect(0, 0, w, h);
    speckle(g, w, h, 9000, 'rgba(60,10,0,.10)', 'rgba(255,220,200,.07)');
    g.fillStyle = '#fbf3e6';
    [0, w / 3, (2 * w) / 3, w].forEach((x) => g.fillRect(x - 4, 0, 8, h));
    g.fillStyle = 'rgba(251,243,230,.55)';
    g.fillRect(0, h - 10, w, 6);
    g.font = '900 40px Nunito, "Arial Black", sans-serif';
    g.textAlign = 'center';
    g.fillStyle = 'rgba(251,243,230,.55)';
    ['1', '2', '3'].forEach((n, i) => g.fillText(n, (w / 3) * (i + 0.5), h - 26));
  }, 1, TRACK_LEN / TILE);
  const track = new THREE.Mesh(new THREE.PlaneGeometry(TRACK_W, TRACK_LEN), std(0xffffff, { map: trackTex, roughness: 0.85 }));
  track.rotation.x = -Math.PI / 2;
  track.position.z = TRACK_Z;
  track.receiveShadow = true;
  scene.add(track);

  const grassTex = canvasTex(64, 256, (g, w, h) => {
    g.fillStyle = '#4fae4f'; g.fillRect(0, 0, w, h);
    g.fillStyle = '#5fc05c'; g.fillRect(0, 0, w, h / 2);
    speckle(g, w, h, 900, 'rgba(0,60,0,.12)', 'rgba(220,255,200,.08)');
  }, 6, TRACK_LEN / TILE);
  const grass = new THREE.Mesh(new THREE.PlaneGeometry(60, TRACK_LEN), lam(0xffffff, { map: grassTex }));
  grass.rotation.x = -Math.PI / 2;
  grass.position.set(0, -0.03, TRACK_Z);
  grass.receiveShadow = true;
  scene.add(grass);

  [-1, 1].forEach((s) => {
    const curb = new THREE.Mesh(new THREE.BoxGeometry(0.34, 0.16, TRACK_LEN), std(0xf4ede0));
    curb.position.set(s * (TRACK_W / 2 + 0.17), 0.08, TRACK_Z);
    curb.receiveShadow = true;
    scene.add(curb);
  });

  // ----- Tribunes : segments qui défilent et se recyclent -----
  const SEG = 40;
  const NSEG = 5;
  const lampMat = new THREE.MeshBasicMaterial({ color: 0x404040 });
  const lampGlowMat = new THREE.SpriteMaterial({ map: glowTex, color: 0xfff4d6, transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false });
  const STAND_COLORS = [0x2b6fd6, 0xe0453a, 0x1aa37a, 0xf2b31b];
  const CROWD_COLORS = [0xffffff, 0xff5a36, 0x3d9cff, 0xffc531, 0x2fd18b, 0x9b5de5, 0xff7ab8, 0x1d2340, 0xf4ede0];
  const SKIN_COLORS = [0xffd7b0, 0xe8b48a, 0xb9825a, 0x8a5a3a, 0x5c3a24];
  const BOARD_TEXTS = [
    { t: 'TURBO COULOIRS', bg: '#141834', fg: '#ffc531' },
    { t: 'ALLEZ ! ALLEZ !', bg: '#ffc531', fg: '#141834' },
    { t: '100 M · 200 M · 400 M', bg: '#e0453a', fg: '#fff8ec' },
    { t: 'RECORD DU STADE', bg: '#2b6fd6', fg: '#fff8ec' },
    { t: 'PISTE N°7', bg: '#1aa37a', fg: '#fff8ec' },
  ];
  const boardMats = BOARD_TEXTS.map((b) => new THREE.MeshBasicMaterial({
    map: textTex(1024, 96, (g, w, h) => {
      g.fillStyle = b.bg; g.fillRect(0, 0, w, h);
      g.fillStyle = b.fg; g.font = DISPLAY_FONT(54); g.textAlign = 'center'; g.textBaseline = 'middle';
      g.fillText(b.t, w / 4, h / 2 + 3); g.fillText(b.t, (3 * w) / 4, h / 2 + 3);
    }),
  }));
  const stepGeos = [0, 1, 2, 3].map((s) => new THREE.BoxGeometry(1.4, 0.7 * (s + 1), SEG));
  const concrete = [lam(0xd9d3e3), lam(0xc7c0d4)];
  const personGeo = new THREE.BoxGeometry(0.36, 0.55, 0.3);
  const headGeo = new THREE.SphereGeometry(0.15, 8, 6);
  const crowdMat = lam(0xffffff);
  const stands = [];

  function makeStand(side, idx, colorIdx) {
    const g = new THREE.Group();
    const seat = lam(STAND_COLORS[colorIdx % STAND_COLORS.length]);
    const x0 = TRACK_W / 2 + 4.2;
    for (let s = 0; s < 4; s++) {
      const step = new THREE.Mesh(stepGeos[s], concrete[s % 2]);
      step.position.set(side * (x0 + s * 1.4 + 0.7), 0.35 * (s + 1), 0);
      const strip = new THREE.Mesh(new THREE.BoxGeometry(1.4, 0.12, SEG), seat);
      strip.position.set(step.position.x, 0.7 * (s + 1) + 0.06, 0);
      g.add(step, strip);
    }
    // Mur du fond et auvent
    const wall = new THREE.Mesh(new THREE.BoxGeometry(0.6, 6, SEG), lam(0x262c55));
    wall.position.set(side * (x0 + 4 * 1.4 + 0.3), 3, 0);
    const band = new THREE.Mesh(new THREE.BoxGeometry(0.62, 0.5, SEG), seat);
    band.position.set(wall.position.x, 5.2, 0);
    const roof = new THREE.Mesh(new THREE.BoxGeometry(6.6, 0.25, SEG), lam(0xf4ede0));
    roof.position.set(side * (x0 + 2.8), 6.2, 0);
    roof.rotation.z = side * -0.12;
    g.add(wall, band, roof);

    // Public
    const per = 15;
    const bodies = new THREE.InstancedMesh(personGeo, crowdMat, 4 * per);
    const heads = new THREE.InstancedMesh(headGeo, crowdMat, 4 * per);
    const m = new THREE.Matrix4();
    const col = new THREE.Color();
    let n = 0;
    for (let s = 0; s < 4; s++) {
      for (let i = 0; i < per; i++) {
        const empty = Math.random() < 0.18;
        const x = side * (x0 + s * 1.4 + 0.7 + rand(-0.25, 0.25));
        const y = 0.7 * (s + 1) + 0.12 + 0.27;
        const z = -SEG / 2 + (i + rand(0.15, 0.85)) * (SEG / per);
        m.makeScale(empty ? 0.001 : 1, empty ? 0.001 : rand(0.85, 1.15), empty ? 0.001 : 1).setPosition(x, y, z);
        bodies.setMatrixAt(n, m);
        bodies.setColorAt(n, col.setHex(pick(CROWD_COLORS)));
        m.makeScale(empty ? 0.001 : 1, empty ? 0.001 : 1, empty ? 0.001 : 1).setPosition(x, y + 0.42, z);
        heads.setMatrixAt(n, m);
        heads.setColorAt(n, col.setHex(pick(SKIN_COLORS)));
        n++;
      }
    }
    bodies.frustumCulled = false; // les instances sont loin de l'origine du maillage
    heads.frustumCulled = false;
    const crowd = new THREE.Group();
    crowd.add(bodies, heads);
    g.add(crowd);

    // Panneaux publicitaires au bord de la piste
    [-1, 1].forEach((half) => {
      const board = new THREE.Mesh(new THREE.PlaneGeometry(SEG / 2 - 0.6, 0.9), pick(boardMats));
      board.rotation.y = side < 0 ? Math.PI / 2 : -Math.PI / 2;
      board.position.set(side * (TRACK_W / 2 + 1.5), 0.55, half * SEG / 4);
      const back = new THREE.Mesh(new THREE.BoxGeometry(0.1, 1.1, SEG / 2 - 0.4), lam(0x141834));
      back.position.set(side * (TRACK_W / 2 + 1.56), 0.55, half * SEG / 4);
      g.add(back, board);
    });

    // Pylône d'éclairage
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.34, 17, 8), lam(0x9aa0b8));
    pole.position.set(side * (x0 + 7.5), 8.5, -SEG / 2);
    const head = new THREE.Mesh(new THREE.BoxGeometry(0.5, 2, 3.6), lam(0x2a2f4f));
    head.position.set(pole.position.x, 17.4, -SEG / 2);
    const lamps = new THREE.Mesh(new THREE.PlaneGeometry(3.2, 1.6), lampMat);
    lamps.rotation.y = side < 0 ? Math.PI / 2 : -Math.PI / 2;
    lamps.position.set(pole.position.x - side * 0.27, 17.4, -SEG / 2);
    const glow = new THREE.Sprite(lampGlowMat);
    glow.scale.set(11, 11, 1);
    glow.position.copy(lamps.position);
    g.add(pole, head, lamps, glow);

    g.position.z = 14 - SEG / 2 - idx * SEG;
    g.userData.crowd = crowd;
    g.userData.phase = Math.random() * 6;
    scene.add(g);
    stands.push(g);
  }
  for (let i = 0; i < NSEG; i++) { makeStand(-1, i, i); makeStand(1, i, i + 2); }

  // Lignes de vitesse (visibles quand ça va très vite)
  const speedLineMat = additive(0xffffff, 0);
  const speedLines = [];
  for (let i = 0; i < 34; i++) {
    const l = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.03, rand(3, 6)), speedLineMat);
    const side = Math.random() < 0.5 ? -1 : 1;
    l.position.set(side * rand(2.5, 7), rand(0.4, 6.5), rand(-50, 10));
    scene.add(l);
    speedLines.push(l);
  }

  // =====================================================================
  // Particules
  // =====================================================================
  const PN = 400;
  const pPos = new Float32Array(PN * 3);
  const pCol = new Float32Array(PN * 3);
  const pVel = new Float32Array(PN * 3);
  const pLife = new Float32Array(PN);
  for (let i = 0; i < PN; i++) pPos[i * 3 + 1] = -999;
  const pGeo = new THREE.BufferGeometry();
  pGeo.setAttribute('position', new THREE.BufferAttribute(pPos, 3));
  pGeo.setAttribute('color', new THREE.BufferAttribute(pCol, 3));
  const particles = new THREE.Points(pGeo, new THREE.PointsMaterial({
    size: 0.28, map: dotTex, vertexColors: true, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
  }));
  particles.frustumCulled = false;
  scene.add(particles);
  let pNext = 0;
  function burst(x, y, z, color, n, power) {
    const c = new THREE.Color(color);
    for (let k = 0; k < n; k++) {
      const i = pNext; pNext = (pNext + 1) % PN;
      pPos[i * 3] = x; pPos[i * 3 + 1] = y; pPos[i * 3 + 2] = z;
      const a = Math.random() * Math.PI * 2;
      const e = rand(-0.3, 1);
      const v = rand(0.4, 1) * power;
      pVel[i * 3] = Math.cos(a) * v; pVel[i * 3 + 1] = e * v + power * 0.4; pVel[i * 3 + 2] = Math.sin(a) * v;
      pCol[i * 3] = c.r; pCol[i * 3 + 1] = c.g; pCol[i * 3 + 2] = c.b;
      pLife[i] = rand(0.4, 0.8);
    }
  }
  function updateParticles(dt, step) {
    for (let i = 0; i < PN; i++) {
      if (pLife[i] <= 0) continue;
      pLife[i] -= dt;
      if (pLife[i] <= 0) { pPos[i * 3 + 1] = -999; continue; }
      pVel[i * 3 + 1] -= 9 * dt;
      pPos[i * 3] += pVel[i * 3] * dt;
      pPos[i * 3 + 1] += pVel[i * 3 + 1] * dt;
      pPos[i * 3 + 2] += pVel[i * 3 + 2] * dt + step * 0.6;
      const f = Math.min(1, pLife[i] * 2.5);
      pCol[i * 3] *= 0.985 + 0.015 * f; pCol[i * 3 + 1] *= 0.985 + 0.015 * f; pCol[i * 3 + 2] *= 0.985 + 0.015 * f;
    }
    pGeo.attributes.position.needsUpdate = true;
    pGeo.attributes.color.needsUpdate = true;
  }

  // =====================================================================
  // Le coureur
  // =====================================================================
  const player = (function () {
    const root = new THREE.Group();
    const body = new THREE.Group();
    const shirt = std(0xff5a36, { roughness: 0.55 });
    const skin = std(0xffcf9f, { roughness: 0.6 });
    const shorts = std(0x1f2a7a, { roughness: 0.6 });
    const shoe = std(0x19e0c0, { roughness: 0.4 });
    const hair = std(0x3a2418, { roughness: 0.8 });
    const band = std(0xffc531, { roughness: 0.4 });

    const torso = new THREE.Mesh(new THREE.SphereGeometry(0.4, 18, 14), shirt);
    torso.scale.set(0.95, 1.12, 0.7);
    torso.position.y = 1.22;
    // Dossard dans le dos (face caméra)
    const bib = new THREE.Mesh(new THREE.PlaneGeometry(0.42, 0.34), new THREE.MeshStandardMaterial({
      map: textTex(128, 104, (g, w, h) => {
        g.fillStyle = '#fff8ec'; g.fillRect(0, 0, w, h);
        g.fillStyle = '#141834'; g.font = DISPLAY_FONT(70); g.textAlign = 'center'; g.textBaseline = 'middle';
        g.fillText('7', w / 2, h / 2 + 4);
      }), roughness: 0.7,
    }));
    bib.position.set(0, 1.25, 0.285);
    const neck = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.1, 0.16, 10), skin);
    neck.position.y = 1.68;
    const head = new THREE.Mesh(new THREE.SphereGeometry(0.27, 18, 14), skin);
    head.position.y = 1.9;
    const hairCap = new THREE.Mesh(new THREE.SphereGeometry(0.285, 18, 12, 0, Math.PI * 2, 0, Math.PI * 0.55), hair);
    hairCap.position.y = 1.92;
    hairCap.rotation.x = 0.25;
    const headband = new THREE.Mesh(new THREE.TorusGeometry(0.272, 0.045, 8, 24), band);
    headband.position.y = 1.96;
    headband.rotation.x = Math.PI / 2 + 0.18;
    const pony = new THREE.Mesh(new THREE.SphereGeometry(0.11, 10, 8), hair);
    pony.scale.set(0.8, 1.6, 0.8);
    pony.position.set(0, 1.86, 0.3);
    const hips = new THREE.Mesh(new THREE.SphereGeometry(0.3, 14, 10), shorts);
    hips.scale.set(1.1, 0.7, 0.85);
    hips.position.y = 0.78;

    function limb(len, rTop, rBot, material, x, y, endMat, endGeo) {
      const pivot = new THREE.Group();
      pivot.position.set(x, y, 0);
      const m = new THREE.Mesh(new THREE.CylinderGeometry(rTop, rBot, len, 10), material);
      m.position.y = -len / 2;
      m.castShadow = true;
      pivot.add(m);
      if (endMat) {
        const e = new THREE.Mesh(endGeo, endMat);
        e.position.y = -len;
        e.castShadow = true;
        pivot.add(e);
        pivot.userData.end = e;
      }
      return pivot;
    }
    const shoeGeo = new THREE.BoxGeometry(0.2, 0.13, 0.36);
    shoeGeo.translate(0, -0.02, -0.07);
    const legL = limb(0.66, 0.11, 0.08, skin, -0.15, 0.74, shoe, shoeGeo);
    const legR = limb(0.66, 0.11, 0.08, skin, 0.15, 0.74, shoe, shoeGeo);
    const handGeo = new THREE.SphereGeometry(0.075, 8, 6);
    const armL = limb(0.56, 0.08, 0.06, skin, -0.42, 1.5, skin, handGeo);
    const armR = limb(0.56, 0.08, 0.06, skin, 0.42, 1.5, skin, handGeo);
    // manches courtes
    [armL, armR].forEach((a) => {
      const sleeve = new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.095, 0.18, 10), shirt);
      sleeve.position.y = -0.06;
      a.add(sleeve);
    });

    // Fusée dorsale (visible pendant le bonus Fusée)
    const jet = new THREE.Group();
    const tank = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.12, 0.55, 10), std(0xd8dde8, { metalness: 0.6, roughness: 0.3 }));
    const tank2 = tank.clone();
    tank.position.set(-0.14, 1.25, 0.32); tank2.position.set(0.14, 1.25, 0.32);
    const flameMat = additive(0xffa030, 0.9);
    const flame1 = new THREE.Mesh(new THREE.ConeGeometry(0.11, 0.6, 10), flameMat);
    flame1.rotation.x = Math.PI;
    flame1.position.set(-0.14, 0.7, 0.32);
    const flame2 = flame1.clone();
    flame2.position.x = 0.14;
    jet.add(tank, tank2, flame1, flame2);
    jet.visible = false;

    [torso, head, hips, hairCap].forEach((m) => { m.castShadow = true; });
    body.add(torso, bib, neck, head, hairCap, headband, pony, hips, legL, legR, armL, armR, jet);
    root.add(body);

    // Bulle du bouclier et anneau de l'aimant
    const bubble = new THREE.Mesh(new THREE.SphereGeometry(1.25, 24, 16), additive(0x3d9cff, 0.22));
    bubble.position.y = 1.1;
    bubble.visible = false;
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.85, 0.05, 8, 40), additive(0xff4f6d, 0.9));
    ring.rotation.x = Math.PI / 2;
    ring.position.y = 0.08;
    ring.visible = false;
    root.add(bubble, ring);

    const shadow = new THREE.Mesh(new THREE.CircleGeometry(0.55, 24), new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.22, depthWrite: false }));
    shadow.rotation.x = -Math.PI / 2;
    shadow.position.y = 0.02;
    scene.add(shadow);
    scene.add(root);
    return { root, body, legL, legR, armL, armR, jet, flame1, flame2, bubble, ring, shadow, torso };
  })();

  // =====================================================================
  // Obstacles, pièces, bonus, arches de niveau
  // =====================================================================
  const containerMats = ['#2b6fd6', '#e0453a', '#1aa37a', '#8b5cf6', '#f2b31b'].map((c) => std(0xffffff, {
    roughness: 0.55,
    map: canvasTex(256, 128, (g, w, h) => {
      g.fillStyle = c; g.fillRect(0, 0, w, h);
      for (let x = 0; x < w; x += 16) { g.fillStyle = 'rgba(0,0,0,.16)'; g.fillRect(x, 0, 5, h); g.fillStyle = 'rgba(255,255,255,.12)'; g.fillRect(x + 5, 0, 2, h); }
      g.fillStyle = 'rgba(0,0,0,.28)'; g.fillRect(0, 0, w, 9); g.fillRect(0, h - 9, w, 9);
      speckle(g, w, h, 400, 'rgba(0,0,0,.08)', 'rgba(255,255,255,.06)');
    }),
  }));
  const hurdleMat = std(0xffffff, {
    map: canvasTex(128, 32, (g, w, h) => {
      g.fillStyle = '#fbf3e6'; g.fillRect(0, 0, w, h);
      g.fillStyle = '#141834'; g.fillRect(0, 0, 20, h); g.fillRect(54, 0, 20, h); g.fillRect(108, 0, 20, h);
    }), roughness: 0.4,
  });
  const chevronMat = std(0xffffff, {
    map: canvasTex(256, 32, (g, w, h) => {
      g.fillStyle = '#ffc531'; g.fillRect(0, 0, w, h);
      g.fillStyle = '#141834';
      for (let x = -32; x < w + 32; x += 32) { g.beginPath(); g.moveTo(x, 0); g.lineTo(x + 16, 0); g.lineTo(x + 32, h); g.lineTo(x + 16, h); g.fill(); }
    }), roughness: 0.45,
  });
  const metal = std(0x3a4060, { metalness: 0.5, roughness: 0.4 });
  const containerRoof = std(0xd4d9e6, { roughness: 0.5 }); // clair : bien visible vu d'en haut (Fusée)
  const poleMat = std(0xffffff, {
    map: canvasTex(16, 64, (g, w, h) => { for (let y = 0; y < h; y += 16) { g.fillStyle = y % 32 ? '#e0453a' : '#fbf3e6'; g.fillRect(0, y, w, 16); } }),
  });
  const beaconMat = new THREE.MeshBasicMaterial({ color: 0xff3020 });
  const coinGeo = new THREE.CylinderGeometry(0.36, 0.36, 0.09, 26);
  const coinRimGeo = new THREE.TorusGeometry(0.33, 0.035, 8, 26);
  const coinMat = std(0xffc531, { metalness: 0.45, roughness: 0.25, emissive: 0x6a4200 });

  function shadowed(g) { g.traverse((o) => { if (o.isMesh) o.castShadow = true; }); return g; }

  function makeHurdle() { // haie basse : sauter
    const g = new THREE.Group();
    const bar = new THREE.Mesh(new THREE.BoxGeometry(1.95, 0.26, 0.08), hurdleMat);
    bar.position.y = 0.84;
    [-0.88, 0.88].forEach((x) => {
      const leg = new THREE.Mesh(new THREE.BoxGeometry(0.07, 0.86, 0.07), metal);
      leg.position.set(x, 0.43, 0);
      const foot = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.06, 0.7), metal);
      foot.position.set(x, 0.03, 0.25);
      g.add(leg, foot);
    });
    g.add(bar);
    return shadowed(g);
  }
  function makeHighBar() { // barre haute : glisser dessous
    const g = new THREE.Group();
    const bar = new THREE.Mesh(new THREE.BoxGeometry(2.2, 0.42, 0.22), chevronMat);
    bar.position.y = 1.62;
    [-1.06, 1.06].forEach((x) => {
      const p = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.08, 2.4, 10), poleMat);
      p.position.set(x, 1.2, 0);
      const cap = new THREE.Mesh(new THREE.SphereGeometry(0.11, 10, 8), beaconMat);
      cap.position.set(x, 2.45, 0);
      g.add(p, cap);
    });
    g.add(bar);
    return shadowed(g);
  }
  function makeContainer(len) { // conteneur : changer de couloir
    const g = new THREE.Group();
    const c = new THREE.Mesh(new THREE.BoxGeometry(1.9, 2.4, len), pick(containerMats));
    c.position.y = 1.2;
    const roof = new THREE.Mesh(new THREE.BoxGeometry(1.96, 0.1, len + 0.06), containerRoof);
    roof.position.y = 2.42;
    g.add(c, roof);
    return shadowed(g);
  }
  function makeCoin() {
    const g = new THREE.Group();
    const inner = new THREE.Group();
    const disc = new THREE.Mesh(coinGeo, coinMat);
    disc.rotation.x = Math.PI / 2;
    const rim = new THREE.Mesh(coinRimGeo, coinMat);
    rim.position.z = 0.05;
    const rim2 = rim.clone(); rim2.position.z = -0.05;
    inner.add(disc, rim, rim2);
    g.add(inner);
    g.userData.spin = inner;
    return g;
  }
  const iconTextures = {};
  function iconTex(id, color) {
    if (iconTextures[id]) return iconTextures[id];
    const t = canvasTex(128, 128, (g) => {
      g.beginPath(); g.arc(64, 64, 58, 0, Math.PI * 2);
      g.fillStyle = color; g.fill();
      g.lineWidth = 7; g.strokeStyle = '#ffffff'; g.stroke();
      g.save(); g.translate(64 - 36, 64 - 36); g.scale(3, 3);
      g.fillStyle = '#ffffff'; g.fill(new Path2D(ICONS[id]), 'evenodd');
      g.restore();
    });
    t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping;
    iconTextures[id] = t;
    return t;
  }
  function makeBonus(id) {
    const P = POWERS[id];
    const g = new THREE.Group();
    const icon = new THREE.Sprite(new THREE.SpriteMaterial({ map: iconTex(id, P.color), depthWrite: false }));
    icon.scale.set(1, 1, 1);
    const halo = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTex, color: P.color, transparent: true, opacity: 0.9, blending: THREE.AdditiveBlending, depthWrite: false }));
    halo.scale.set(2.6, 2.6, 1);
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.72, 0.05, 8, 40), additive(P.color, 0.9));
    const beam = new THREE.Mesh(new THREE.CylinderGeometry(0.55, 0.55, 14, 20, 1, true), additive(P.color, 0.13, { side: THREE.DoubleSide }));
    beam.position.y = 6.5;
    g.add(halo, beam, ring, icon);
    g.userData.ring = ring;
    return g;
  }
  function makeArch(level, phaseName) {
    const g = new THREE.Group();
    const w = TRACK_W + 3.6;
    const dark = lam(0x1d2340);
    [-1, 1].forEach((s) => {
      const p = new THREE.Mesh(new THREE.BoxGeometry(0.6, 7, 0.6), dark);
      p.position.set(s * (w / 2 - 0.3), 3.5, 0);
      g.add(p);
    });
    const tex = textTex(1024, 160, (c, W, H) => {
      c.fillStyle = '#141834'; c.fillRect(0, 0, W, H);
      c.fillStyle = '#ffc531'; c.fillRect(0, 0, W, 10); c.fillRect(0, H - 10, W, 10);
      c.textAlign = 'center'; c.textBaseline = 'middle';
      c.fillStyle = '#ffc531'; c.font = DISPLAY_FONT(76); c.fillText('NIVEAU ' + level, W / 2, H / 2 - 14);
      c.fillStyle = '#fff8ec'; c.font = '900 34px Nunito, sans-serif'; c.fillText(phaseName.toUpperCase(), W / 2, H / 2 + 46);
    });
    const front = new THREE.MeshBasicMaterial({ map: tex });
    const beam = new THREE.Mesh(new THREE.BoxGeometry(w, 1.6, 0.5), [dark, dark, dark, dark, front, dark]);
    beam.position.y = 7.2;
    const led = new THREE.Mesh(new THREE.BoxGeometry(w, 0.12, 0.55), new THREE.MeshBasicMaterial({ color: 0xffc531 }));
    led.position.y = 6.35;
    g.add(beam, led);
    return g;
  }

  // Boîtes de collision
  const HIT = {
    hurdle: { w: 0.95, y0: 0, y1: 0.98, d: 0.15 },
    high: { w: 1.1, y0: 1.38, y1: 2.6, d: 0.2 },
    crate: { w: 0.95, y0: 0, y1: 2.45 },
  };

  let things = []; // {kind, type, lane, x, y, z, len, mesh, taken, move}

  function addThing(kind, type, lane, z, opts) {
    opts = opts || {};
    let mesh;
    if (kind === 'coin') mesh = makeCoin();
    else if (kind === 'bonus') mesh = makeBonus(type);
    else if (kind === 'arch') mesh = makeArch(opts.level, opts.phase);
    else if (type === 'hurdle') mesh = makeHurdle();
    else if (type === 'high') mesh = makeHighBar();
    else mesh = makeContainer(opts.len || 2.8);
    const x = kind === 'arch' ? 0 : CONFIG.lanes[lane];
    const y = opts.y || 0;
    mesh.position.set(x, y, z);
    scene.add(mesh);
    const t = { kind, type, lane, x, y, z, len: opts.len || 0, mesh, taken: false, move: opts.move || null, level: opts.level };
    if (t.move) {
      const b = new THREE.Mesh(new THREE.SphereGeometry(0.16, 10, 8), beaconMat);
      b.position.y = 2.6;
      mesh.add(b);
      t.beacon = b;
    }
    things.push(t);
    return t;
  }
  function removeThing(t) { scene.remove(t.mesh); t.dead = true; }
  function clearThings() { things.forEach((t) => scene.remove(t.mesh)); things = []; }

  function unlockedPowers() { return Object.keys(POWERS).filter((id) => up[id] >= 0); }

  function spawnRow(z) {
    const t = run.time;
    const p3 = clamp((t - 35) / 120, 0, 0.55);
    const p2 = clamp(0.3 + t / 90, 0, 0.92);
    const r = Math.random();
    const count = r < p3 ? 3 : r < p3 + p2 * (1 - p3) ? 2 : 1;
    const lanes = shuffle([0, 1, 2]);
    const types = [];
    for (let i = 0; i < count; i++) { const q = Math.random(); types.push(q < 0.4 ? 'crate' : q < 0.7 ? 'hurdle' : 'high'); }
    if (count === 3 && types.every((x) => x === 'crate')) types[0] = Math.random() < 0.5 ? 'hurdle' : 'high';
    const blocked = lanes.slice(0, count);
    const free = lanes.slice(count);

    blocked.forEach((lane, i) => {
      const type = types[i];
      const opts = {};
      if (type === 'crate') {
        opts.len = 2.8 + (t > 25 && Math.random() < 0.5 ? rand(0, Math.min(14, (t - 25) / 4)) : 0);
        // Conteneur qui change de couloir sous tes yeux
        if (t > 50 && count < 3 && Math.random() < Math.min(0.4, (t - 50) / 120)) {
          const to = lane === 1 ? pick([0, 2]) : 1;
          opts.move = { to, at: -rand(30, 50), done: false };
        }
      }
      addThing('obs', type, lane, z - (opts.len ? opts.len / 2 : 0), opts);
    });

    // Pièces : en ligne dans un couloir libre, ou en arc au-dessus d'une haie
    if (Math.random() < 0.5) {
      const n = 3 + Math.floor(Math.random() * 3);
      if (free.length) {
        const lane = pick(free);
        for (let i = 0; i < n; i++) addThing('coin', null, lane, z - 3 - i * 2.2, { y: 0.9 });
      } else {
        const hi = blocked.find((l, i) => types[i] === 'hurdle');
        if (hi !== undefined) for (let i = 0; i < 5; i++) addThing('coin', null, hi, z + 4.4 - i * 2.2, { y: 0.9 + Math.sin((i / 4) * Math.PI) * 1.6 });
      }
    }

    // Bonus
    if (run.bonusDue && free.length) {
      run.bonusDue = false;
      const owned = unlockedPowers();
      const lanesForBonus = shuffle(free.slice());
      const howMany = Math.random() < doubleChance(up.luck) && lanesForBonus.length > 1 ? 2 : 1;
      for (let i = 0; i < howMany; i++) addThing('bonus', pick(owned), lanesForBonus[i], z - 9, { y: 1.2 });
    }

    // Pendant la fusée : des pièces dans le ciel
    if (run.fx.rocket > 0) {
      const lane = Math.floor(Math.random() * 3);
      for (let i = 0; i < 6; i++) addThing('coin', null, lane, z - i * 2.4, { y: 3.9 });
    }
  }

  // =====================================================================
  // Sauvegarde : record, porte-monnaie, améliorations
  // =====================================================================
  let best = load('turbo.best', 0);
  let wallet = load('turbo.wallet', 0);
  const up = Object.assign({ magnet: 0, shield: 0, double: 0, rocket: -1, slow: -1, luck: 0 }, load('turbo.up', {}));
  function saveProgress() { save('turbo.wallet', wallet); save('turbo.up', up); }

  // =====================================================================
  // État de la partie
  // =====================================================================
  const FX_IDS = Object.keys(POWERS);
  const run = {
    state: 'menu', // menu | shop | play | pause | dead
    speed: 0, dist: 0, time: 0, coins: 0, banked: 0, level: 1,
    lane: 1, x: 0, y: 0, vy: 0, slide: 0,
    untilNext: 0, untilBonus: 0, bonusDue: false, nextArchAt: 0,
    invincible: 0, continued: false, shake: 0, deadTimer: 0, cheer: 0,
    fx: {}, fxMax: {}, shieldHits: 0,
  };
  let screenBeforeShop = 'menu';

  const score = () => Math.floor(run.dist) + run.coins * CONFIG.coinValue;

  function show(id) {
    ['menu', 'pause', 'over', 'shop'].forEach((s) => { $(s).hidden = s !== id; });
    const inGame = run.state === 'play' || run.state === 'pause';
    $('hud').hidden = !inGame;
    $('fx').hidden = !inGame;
    $('bestMenu').textContent = fmt(best);
    $('walletMenu').textContent = fmt(wallet);
  }

  function resetFx() { FX_IDS.forEach((id) => { run.fx[id] = 0; run.fxMax[id] = 1; }); run.shieldHits = 0; renderFxChips(); }

  function startRun() {
    clearThings();
    Object.assign(run, {
      state: 'play', speed: CONFIG.startSpeed, dist: 0, time: 0, coins: 0, banked: 0, level: 1,
      lane: 1, x: 0, y: 0, vy: 0, slide: 0, untilNext: 24, untilBonus: bonusInterval(up.luck) * rand(0.5, 0.8),
      bonusDue: false, nextArchAt: CONFIG.levelLength + CONFIG.spawnZ, invincible: 0, continued: false, shake: 0, cheer: 0,
    });
    resetFx();
    phaseTarget = PHASES[0];
    $('coins').textContent = '0';
    $('lvl').textContent = '1';
    show(null);
    ADS.showBanner();
  }

  function bank() {
    const earned = run.coins - run.banked;
    run.banked = run.coins;
    wallet += earned;
    saveProgress();
    return earned;
  }

  function die() {
    if (run.state !== 'play') return;
    run.state = 'dead';
    run.shake = 0.45;
    run.deadTimer = 0.8;
    burst(run.x, 1.2, 0, 0xffffff, 40, 6);
    if (navigator.vibrate) { try { navigator.vibrate(140); } catch (e) { /* ignore */ } }
  }

  function showGameOver() {
    const s = score();
    const isBest = s > best;
    if (isBest) { best = s; save('turbo.best', best); }
    const earned = bank();
    $('finalScore').textContent = fmt(s);
    $('finalDist').textContent = fmt(run.dist) + ' m';
    $('finalLvl').textContent = run.level;
    $('finalBest').textContent = fmt(best);
    $('earned').textContent = '+' + fmt(earned);
    $('walletOver').textContent = fmt(wallet);
    $('newBest').hidden = !isBest;
    $('continueBtn').hidden = run.continued; // un seul « continuer » par partie
    show('over');
  }

  function continueRun() {
    things.forEach((t) => { if (t.z > -40 && t.kind === 'obs') removeThing(t); });
    things = things.filter((t) => !t.dead);
    run.continued = true;
    run.state = 'play';
    run.invincible = 2.5;
    run.y = 0; run.vy = 0; run.slide = 0;
    show(null);
  }

  function activate(id) {
    const lvl = up[id];
    const d = dur(id, lvl);
    run.fx[id] = d;
    run.fxMax[id] = d;
    if (id === 'shield') run.shieldHits = shieldHits(lvl);
    if (id === 'rocket') {
      run.slide = 0;
      // Une traînée de pièces dans le ciel, devant le joueur
      let lane = run.lane;
      for (let i = 0; i < 24; i++) {
        if (i % 8 === 7) lane = clamp(lane + pick([-1, 1]), 0, 2);
        addThing('coin', null, lane, -16 - i * 2.4, { y: 3.9 });
      }
    }
    toast(POWERS[id].name, null, POWERS[id].color);
    renderFxChips();
    if (navigator.vibrate) { try { navigator.vibrate(30); } catch (e) { /* ignore */ } }
  }

  function levelUp(level) {
    run.level = level;
    $('lvl').textContent = level;
    const phase = PHASES[(level - 1) % PHASES.length];
    phaseTarget = phase;
    run.cheer = 2.5;
    toast('Niveau ' + level, 'Plus vite ! · ' + phase.name);
  }

  // =====================================================================
  // HUD : bonus actifs et messages
  // =====================================================================
  let toastTimer = null;
  function toast(title, sub, color) {
    const el = $('toast');
    $('toastTitle').textContent = title;
    $('toastSub').textContent = sub || '';
    $('toastSub').hidden = !sub;
    el.style.setProperty('--tc', color || '');
    el.hidden = false;
    el.classList.remove('show'); void el.offsetWidth; el.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { el.hidden = true; }, 1900);
  }

  let chipKey = '';
  function renderFxChips() {
    const active = FX_IDS.filter((id) => run.fx[id] > 0);
    const key = active.join(',') + '|' + run.shieldHits;
    if (key === chipKey) return;
    chipKey = key;
    $('fx').innerHTML = active.map((id) => {
      const label = id === 'shield' && run.shieldHits > 1 ? POWERS[id].name + ' ×' + run.shieldHits : POWERS[id].name;
      return '<div class="chip" style="--c:' + POWERS[id].color + '"><div class="ring" id="ring-' + id + '"><span>' + svg(id) + '</span></div>' + label + '</div>';
    }).join('');
  }
  function updateFxRings() {
    FX_IDS.forEach((id) => {
      if (run.fx[id] <= 0) return;
      const el = document.getElementById('ring-' + id);
      if (el) el.style.setProperty('--p', (run.fx[id] / run.fxMax[id]).toFixed(3));
    });
  }

  // =====================================================================
  // Boutique
  // =====================================================================
  function itemInfo(id, lvl) {
    if (id === 'luck') {
      const dc = doubleChance(lvl);
      return 'Un bonus tous les ' + bonusInterval(lvl) + ' m' + (dc ? ' · ' + Math.round(dc * 100) + ' % de bonus double' : '');
    }
    const d = dur(id, Math.max(0, lvl)) + ' s';
    if (id === 'magnet') return 'Attire les pièces · ' + d + (lvl >= 3 ? ' · grand rayon' : '');
    if (id === 'shield') return 'Encaisse ' + shieldHits(lvl) + ' choc' + (shieldHits(lvl) > 1 ? 's' : '') + ' · ' + d;
    if (id === 'double') return 'Pièces x' + coinMult(lvl) + ' · ' + d;
    if (id === 'rocket') return 'Vole au-dessus des obstacles · ' + d;
    if (id === 'slow') return 'Ralentit la course de ' + Math.round((1 - slowFactor(lvl)) * 100) + ' % · ' + d;
    return '';
  }
  function itemCost(id) {
    const lvl = up[id];
    if (lvl < 0) return POWERS[id].unlock;
    if (lvl >= MAX_LVL) return null;
    return (id === 'luck' ? LUCK_COST : LEVEL_COST)[lvl];
  }
  function renderShop() {
    $('walletShop').textContent = fmt(wallet);
    const ids = ['magnet', 'shield', 'double', 'rocket', 'slow', 'luck'];
    $('shopList').innerHTML = ids.map((id) => {
      const meta = id === 'luck' ? LUCK : POWERS[id];
      const lvl = up[id];
      const locked = lvl < 0;
      const cost = itemCost(id);
      const pips = Array.from({ length: MAX_LVL }, (_, i) => '<i class="' + (i < lvl ? 'on' : '') + '"></i>').join('');
      const now = locked ? 'À débloquer · ' + itemInfo(id, 0) : itemInfo(id, lvl);
      // Niveau suivant : seulement ce qui change
      const nowParts = itemInfo(id, lvl).split(' · ');
      const diff = itemInfo(id, lvl + 1).split(' · ').filter((x) => nowParts.indexOf(x) < 0);
      const next = !locked && lvl < MAX_LVL && diff.length ? '<br><em>Ensuite : ' + diff.join(' · ') + '</em>' : '';
      let btn;
      if (cost === null) btn = '<button class="buy max" disabled>Max</button>';
      else btn = '<button class="buy" data-id="' + id + '"' + (wallet < cost ? ' disabled' : '') + '><i class="coin-ico"></i>' + fmt(cost) + '</button>';
      return '<div class="card' + (locked ? ' locked' : '') + '" style="--c:' + meta.color + '">' +
        '<div class="ico">' + svg(id) + '</div>' +
        '<div><h3>' + meta.name + '</h3><p>' + now + next + '</p><div class="pips">' + pips + '</div></div>' +
        btn + '</div>';
    }).join('');
  }
  $('shopList').addEventListener('click', (e) => {
    const b = e.target.closest('.buy');
    if (!b || b.disabled) return;
    const id = b.dataset.id;
    const cost = itemCost(id);
    if (cost === null || wallet < cost) return;
    wallet -= cost;
    up[id] = up[id] < 0 ? 0 : up[id] + 1;
    saveProgress();
    renderShop();
    const nb = $('shopList').querySelector('[data-id="' + id + '"]');
    if (nb) nb.classList.add('flash');
  });
  function openShop() {
    screenBeforeShop = run.state === 'dead' ? 'over' : 'menu';
    if (run.state !== 'dead') run.state = 'shop';
    renderShop();
    show('shop');
  }
  function closeShop() {
    if (screenBeforeShop === 'over') { $('walletOver').textContent = fmt(wallet); show('over'); }
    else { run.state = 'menu'; show('menu'); }
  }

  // =====================================================================
  // Commandes
  // =====================================================================
  function moveLane(dir) {
    if (run.state !== 'play') return;
    run.lane = clamp(run.lane + dir, 0, 2);
  }
  function jump() {
    if (run.state !== 'play' || run.fx.rocket > 0) return;
    if (run.y <= 0.001) { run.vy = CONFIG.jumpVel * speedK(); run.slide = 0; }
  }
  function slide() {
    if (run.state !== 'play' || run.fx.rocket > 0) return;
    if (run.y > 0.001) run.vy = -CONFIG.jumpVel * 1.5 * speedK(); // retombe vite
    run.slide = CONFIG.slideTime / speedK();
  }
  // Plus on va vite, plus les sauts et glissades sont courts (même hauteur).
  function speedK() { return Math.sqrt(Math.max(run.speed, CONFIG.startSpeed) / CONFIG.startSpeed); }

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
    if (Math.max(Math.abs(dx), Math.abs(dy)) < 26) return;
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
  function toMenu() {
    if (run.state === 'pause') bank();
    clearThings();
    resetFx();
    run.state = 'menu'; run.lane = 1; run.y = 0; run.slide = 0; run.invincible = 0;
    phaseTarget = PHASES[0];
    show('menu');
  }

  $('playBtn').addEventListener('click', startRun);
  $('replayBtn').addEventListener('click', startRun);
  $('tiltBtn').addEventListener('click', toggleTilt);
  $('pauseBtn').addEventListener('click', pauseGame);
  $('resumeBtn').addEventListener('click', resumeGame);
  $('quitBtn').addEventListener('click', toMenu);
  $('menuBtn').addEventListener('click', toMenu);
  $('shopBtn').addEventListener('click', openShop);
  $('overShopBtn').addEventListener('click', openShop);
  $('shopBack').addEventListener('click', closeShop);
  $('continueBtn').addEventListener('click', async () => {
    $('continueBtn').disabled = true;
    const ok = await ADS.showRewarded();
    $('continueBtn').disabled = false;
    if (ok) continueRun();
  });
  document.addEventListener('visibilitychange', () => { if (document.hidden) pauseGame(); });

  // =====================================================================
  // Taille de l'écran et caméra
  // =====================================================================
  let baseFov = 60;
  function resize() {
    const w = canvas.clientWidth || window.innerWidth;
    const h = canvas.clientHeight || window.innerHeight;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    // En portrait, on élargit le champ pour voir les 3 couloirs.
    const hfov = 52 * Math.PI / 180;
    baseFov = clamp(2 * Math.atan(Math.tan(hfov / 2) / camera.aspect) * 180 / Math.PI, 58, 86);
    camera.fov = baseFov;
    camera.updateProjectionMatrix();
  }
  window.addEventListener('resize', resize);
  resize();

  // =====================================================================
  // Boucle de jeu
  // =====================================================================
  let last = performance.now();
  let clock = 0;

  function overlaps(t) {
    const h = HIT[t.type];
    const top = run.y + (run.slide > 0 ? 0.85 : 2.05);
    const d = t.type === 'crate' ? t.len / 2 : h.d;
    return Math.abs(run.x - t.x) < h.w + 0.3 && Math.abs(t.z) < d + 0.3 && run.y < h.y1 && top > h.y0;
  }

  function collect(t) {
    t.taken = true;
    t.mesh.visible = false;
    if (t.kind === 'coin') {
      const gain = run.fx.double > 0 ? coinMult(up.double) : 1;
      run.coins += gain;
      $('coins').textContent = fmt(run.coins);
      const box = $('coinBox');
      box.classList.remove('bump'); void box.offsetWidth; box.classList.add('bump');
      burst(t.x, t.y, t.z, 0xffd34d, 6, 2.2);
    } else {
      burst(t.x, t.y, t.z, POWERS[t.type].color, 30, 4);
      activate(t.type);
    }
  }

  function hit(t) {
    if (run.fx.shield > 0 && run.shieldHits > 0) {
      run.shieldHits -= 1;
      if (run.shieldHits <= 0) run.fx.shield = 0;
      burst(t.x, 1.2, t.z, 0x3d9cff, 50, 7);
      burst(t.x, 1.2, t.z, 0xffffff, 20, 5);
      removeThing(t);
      run.invincible = 1;
      run.shake = 0.25;
      renderFxChips();
      return;
    }
    die();
  }

  function collide() {
    const air = run.y + 0.9;
    for (const t of things) {
      if (t.taken || t.dead) continue;
      if (t.kind === 'coin') {
        if (Math.abs(t.z) < 0.9 && Math.abs(t.x - run.x) < 0.9 && Math.abs(t.y - air) < 1.5) collect(t);
      } else if (t.kind === 'bonus') {
        if (Math.abs(t.z) < 1.1 && Math.abs(t.x - run.x) < 1.1 && Math.abs(t.y - air) < 1.8) collect(t);
      } else if (t.kind === 'arch') {
        if (t.z > 0 && !t.taken) { t.taken = true; levelUp(t.level); }
      } else if (run.fx.rocket <= 0 && run.invincible <= 0 && overlaps(t)) {
        hit(t);
        if (run.state !== 'play') return;
      }
    }
  }

  function update(dt) {
    clock += dt;
    const playing = run.state === 'play';

    // Temps des bonus
    if (playing) {
      let ended = false;
      FX_IDS.forEach((id) => {
        if (run.fx[id] > 0) {
          run.fx[id] = Math.max(0, run.fx[id] - dt);
          if (run.fx[id] === 0) {
            ended = true;
            if (id === 'rocket') run.invincible = Math.max(run.invincible, 1.2);
            if (id === 'shield') run.shieldHits = 0;
          }
        }
      });
      if (ended) renderFxChips();
    }
    const slowMul = run.fx.slow > 0 ? slowFactor(up.slow) : 1;
    if (playing) {
      run.time += dt * slowMul;
      run.speed = speedAt(run.time) * slowMul;
    }
    const speed = playing ? run.speed : (run.state === 'menu' || run.state === 'shop') ? 8 : 0;
    const k = speedK();

    if (playing) {
      if (run.fx.rocket > 0) {
        run.y += (3.4 - run.y) * Math.min(1, dt * 4);
        run.vy = 0;
      } else {
        run.vy -= CONFIG.gravity * k * k * dt;
        run.y = Math.max(0, run.y + run.vy * dt);
        if (run.y === 0) run.vy = 0;
      }
      run.slide = Math.max(0, run.slide - dt);
      run.invincible = Math.max(0, run.invincible - dt);
    }

    const step = speed * dt;
    if (step > 0) {
      // Décor qui défile
      trackTex.offset.y += step / TILE;
      grassTex.offset.y += step / TILE;
      stands.forEach((s) => {
        s.position.z += step;
        if (s.position.z - SEG / 2 > 16) s.position.z -= NSEG * SEG;
      });
      speedLineMat.opacity = clamp((run.speed - 30) / 50, 0, 0.55) * (playing ? 1 : 0);
      speedLines.forEach((l) => {
        l.position.z += step * 1.3;
        if (l.position.z > 12) { l.position.z -= 60; l.position.x = (Math.random() < 0.5 ? -1 : 1) * rand(2.5, 7); }
      });

      // Objets : on avance par petits pas pour ne rien traverser à grande vitesse.
      const n = Math.max(1, Math.ceil(step / 0.6));
      const s = step / n;
      for (let i = 0; i < n; i++) {
        for (const t of things) t.z += s;
        if (playing) { collide(); if (run.state !== 'play') break; }
      }

      if (playing) {
        run.dist += step;
        run.untilNext -= step;
        if (run.untilNext <= 0) {
          spawnRow(CONFIG.spawnZ);
          const gap = gapAt(run.time) * rand(0.85, 1.2);
          run.untilNext = run.time > 25 && Math.random() < 0.22 ? gap * 0.6 : gap;
        }
        run.untilBonus -= step;
        if (run.untilBonus <= 0) {
          run.bonusDue = true;
          run.untilBonus = bonusInterval(up.luck) * rand(0.8, 1.2);
        }
        if (run.dist >= run.nextArchAt) {
          const level = Math.round((run.nextArchAt - CONFIG.spawnZ) / CONFIG.levelLength) + 1;
          addThing('arch', null, 1, CONFIG.spawnZ, { level, phase: PHASES[(level - 1) % PHASES.length].name });
          run.nextArchAt += CONFIG.levelLength;
        }
      }
    }

    // Aimant : les pièces proches viennent vers le joueur
    if (playing && run.fx.magnet > 0) {
      const R = magnetRadius(up.magnet);
      const f = Math.min(1, dt * 9);
      for (const t of things) {
        if (t.kind !== 'coin' || t.taken || t.z < -R || t.z > 2) continue;
        t.x += (run.x - t.x) * f;
        t.y += (run.y + 0.9 - t.y) * f;
        t.z += (0 - t.z) * Math.min(1, dt * 5);
      }
    }

    // Conteneurs mobiles, positions, animations
    for (const t of things) {
      if (t.move && !t.move.done && t.z > t.move.at) {
        const tx = CONFIG.lanes[t.move.to];
        t.x += (tx - t.x) * Math.min(1, dt * 3.2);
        if (Math.abs(tx - t.x) < 0.02) { t.x = tx; t.lane = t.move.to; t.move.done = true; }
      }
      if (t.beacon) t.beacon.visible = Math.floor(clock * 6) % 2 === 0;
      t.mesh.position.set(t.x, t.y, t.z);
      if (t.kind === 'coin') t.mesh.userData.spin.rotation.y = clock * 3.2 + t.z * 0.15;
      if (t.kind === 'bonus') {
        t.mesh.position.y = t.y + Math.sin(clock * 3 + t.z) * 0.15;
        t.mesh.userData.ring.rotation.set(clock * 1.7, clock * 2.3, 0);
      }
    }
    if (playing || run.state === 'dead') {
      things = things.filter((t) => {
        if (t.dead) return false;
        if (t.z - (t.len || 0) / 2 > 16) { scene.remove(t.mesh); return false; }
        return true;
      });
    }

    updateParticles(dt, step);

    if (playing) {
      $('score').textContent = fmt(score());
      const into = (run.dist - (run.level - 1) * CONFIG.levelLength) / CONFIG.levelLength;
      $('lvlFill').style.width = (clamp(into, 0, 1) * 100).toFixed(1) + '%';
      updateFxRings();
    }

    if (run.state === 'dead') {
      run.deadTimer -= dt;
      if (run.deadTimer <= 0 && $('over').hidden && $('shop').hidden) showGameOver();
    }

    // Ambiance (ciel, lumière) : transition douce
    applyPhase(phaseTarget, Math.min(1, dt * 0.8));

    // Public qui saute à chaque niveau
    run.cheer = Math.max(0, run.cheer - dt);
    stands.forEach((s) => {
      s.userData.crowd.position.y = run.cheer > 0 ? Math.abs(Math.sin(clock * 9 + s.userData.phase)) * 0.18 : 0;
    });

    animatePlayer(dt, speed, k);
    updateCamera(dt);
  }

  function animatePlayer(dt, speed, k) {
    const p = player;
    const targetX = CONFIG.lanes[run.lane];
    run.x += (targetX - run.x) * Math.min(1, dt * 13 * Math.min(k, 1.8));
    p.root.position.set(run.x, run.y, 0);
    p.shadow.position.x = run.x;
    const sh = Math.max(0.35, 1 - run.y * 0.18);
    p.shadow.scale.set(sh, sh, sh);
    p.root.rotation.z = (run.x - targetX) * 0.14;

    const moving = speed > 0 && run.state !== 'dead';
    const sliding = run.slide > 0 && run.fx.rocket <= 0;
    const flying = run.fx.rocket > 0;
    const freq = 8 + speed * 0.3;
    const phase = clock * freq;
    const swing = moving && run.y === 0 && !sliding ? Math.sin(phase) : 0;
    p.body.rotation.x = sliding ? -1.15 : flying ? -0.5 : -0.12;
    p.body.position.y = sliding ? 0.28 : moving && run.y === 0 ? Math.abs(Math.cos(phase)) * 0.07 : 0;
    p.body.position.z = sliding ? 0.6 : 0;
    const air = run.y > 0 && !flying;
    p.legL.rotation.x = swing * 0.95 + (air ? 0.9 : 0) + (flying ? 0.3 : 0);
    p.legR.rotation.x = -swing * 0.95 + (air ? -0.4 : 0) + (flying ? 0.5 : 0);
    p.armL.rotation.x = -swing * 0.9 + (air ? -1.2 : 0) + (flying ? 0.4 : 0);
    p.armR.rotation.x = swing * 0.9 + (air ? -1.2 : 0) + (flying ? 0.4 : 0);
    p.armL.rotation.z = air ? -0.4 : 0;
    p.armR.rotation.z = air ? 0.4 : 0;

    p.jet.visible = flying;
    if (flying) {
      const f = 0.8 + Math.random() * 0.5;
      p.flame1.scale.set(1, f, 1); p.flame2.scale.set(1, 1.3 - f + 0.8, 1);
      if (Math.random() < 0.6) burst(run.x + rand(-0.15, 0.15), run.y + 0.5, 0.35, 0xff9a30, 1, 1.2);
    }
    p.bubble.visible = run.fx.shield > 0;
    if (p.bubble.visible) {
      const s = 1 + Math.sin(clock * 6) * 0.04;
      p.bubble.scale.set(s, s, s);
      p.bubble.material.opacity = run.fx.shield < 1.5 && Math.floor(clock * 8) % 2 ? 0.08 : 0.22;
    }
    p.ring.visible = run.fx.magnet > 0;
    if (p.ring.visible) { p.ring.rotation.z = clock * 4; const s = 1 + Math.sin(clock * 10) * 0.08; p.ring.scale.set(s, s, s); }
    p.root.visible = run.invincible > 0 && run.fx.rocket <= 0 ? Math.floor(clock * 12) % 2 === 0 : true;
  }

  const CAM = { y: 4.7, z: 8.8, lookY: 1.2, lookZ: -10 };
  let fovNow = 60;
  function updateCamera(dt) {
    run.shake = Math.max(0, run.shake - dt);
    const sx = run.shake > 0 ? rand(-1, 1) * run.shake * 0.6 : 0;
    const sy = run.shake > 0 ? rand(-1, 1) * run.shake * 0.6 : 0;
    const lift = run.fx.rocket > 0 ? run.y * 0.55 : run.y * 0.25;
    camera.position.set(run.x * 0.42 + sx, CAM.y + lift + sy, CAM.z);
    camera.lookAt(run.x * 0.3, CAM.lookY + lift * 0.8, CAM.lookZ);
    camera.rotateZ((CONFIG.lanes[run.lane] - run.x) * 0.018);
    const kick = run.state === 'play' ? Math.min(14, (run.speed - CONFIG.startSpeed) * 0.13) : 0;
    const target = baseFov + kick;
    if (Math.abs(target - fovNow) > 0.05) {
      fovNow += (target - fovNow) * Math.min(1, dt * 2);
      camera.fov = fovNow;
      camera.updateProjectionMatrix();
    }
    sky.position.copy(camera.position);
  }

  function frame(now) {
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    update(dt);
    renderer.render(scene, camera);
    requestAnimationFrame(frame);
  }

  applyPhase(PHASES[0], 1);
  resetFx();
  show('menu');
  requestAnimationFrame(frame);

  // Outils de test (seulement avec ?debug dans l'adresse)
  if (/debug/.test(location.search)) {
    window.__turbo = { run, up, activate, speedAt, gapAt, setWallet(v) { wallet = v; saveProgress(); show(run.state === 'menu' ? 'menu' : null); } };
  }
})();
