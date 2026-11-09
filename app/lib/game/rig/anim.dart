import 'dart:math' as math;
import 'dart:typed_data';

/// Courbes d'interpolation des keyframes.
enum Ease {
  linear,
  step,
  inQuad,
  outQuad,
  inOutQuad,
  inCubic,
  outCubic,
  inOutCubic,
  inOutSine,
  inBack,
  outBack,
  inOutBack,
  outElastic,
}

double ease(Ease e, double t) {
  final x = t < 0 ? 0.0 : (t > 1 ? 1.0 : t);
  switch (e) {
    case Ease.linear:
      return x;
    case Ease.step:
      return x < 1 ? 0 : 1;
    case Ease.inQuad:
      return x * x;
    case Ease.outQuad:
      return x * (2 - x);
    case Ease.inOutQuad:
      return x < 0.5 ? 2 * x * x : 1 - 2 * (1 - x) * (1 - x);
    case Ease.inCubic:
      return x * x * x;
    case Ease.outCubic:
      final y = 1 - x;
      return 1 - y * y * y;
    case Ease.inOutCubic:
      return x < 0.5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3) / 2;
    case Ease.inOutSine:
      return 0.5 - 0.5 * math.cos(math.pi * x);
    case Ease.inBack:
      const c = 1.70158;
      return (c + 1) * x * x * x - c * x * x;
    case Ease.outBack:
      const c = 1.70158;
      final y = x - 1;
      return 1 + (c + 1) * y * y * y + c * y * y;
    case Ease.inOutBack:
      const c = 1.70158 * 1.525;
      return x < 0.5
          ? (4 * x * x * ((c + 1) * 2 * x - c)) / 2
          : (math.pow(2 * x - 2, 2) * ((c + 1) * (x * 2 - 2) + c) + 2) / 2;
    case Ease.outElastic:
      if (x == 0 || x == 1) return x;
      const c = 2 * math.pi / 3;
      return math.pow(2, -10 * x) * math.sin((x * 10 - 0.75) * c) + 1;
  }
}

/// Canaux animables d'un os (décalages par rapport à la pose de repos).
class Ch {
  static const rot = 0, tx = 1, ty = 2, sx = 3, sy = 4;
  static const count = 5;
}

/// Pose : valeur de chaque canal de chaque os (tableau plat, aucune allocation par image).
class Pose {
  Pose(this.bones) : v = Float32List(bones * Ch.count) {
    reset();
  }
  final int bones;
  final Float32List v;

  void reset() {
    for (var b = 0; b < bones; b++) {
      final o = b * Ch.count;
      v[o] = 0;
      v[o + 1] = 0;
      v[o + 2] = 0;
      v[o + 3] = 1;
      v[o + 4] = 1;
    }
  }

  double get(int bone, int ch) => v[bone * Ch.count + ch];
  void set(int bone, int ch, double x) => v[bone * Ch.count + ch] = x;
  void add(int bone, int ch, double x) => v[bone * Ch.count + ch] += x;

  void copyFrom(Pose o) => v.setAll(0, o.v);

  /// this = a + (b - a) * w
  void blend(Pose a, Pose b, double w) {
    for (var i = 0; i < v.length; i++) {
      v[i] = a.v[i] + (b.v[i] - a.v[i]) * w;
    }
  }
}

/// Piste de keyframes d'un canal d'un os : temps, valeurs, courbe vers la clé suivante.
class Track {
  Track(this.bone, this.ch, List<double> keys, {Ease ease = Ease.inOutCubic, List<Ease>? eases})
      : times = Float32List(keys.length ~/ 2),
        values = Float32List(keys.length ~/ 2),
        eases = eases ?? List.filled(keys.length ~/ 2, ease) {
    assert(keys.length.isEven && keys.length >= 2);
    for (var i = 0; i < times.length; i++) {
      times[i] = keys[i * 2];
      values[i] = keys[i * 2 + 1];
    }
    assert(this.eases.length >= times.length - 1);
  }

  final int bone;
  final int ch;
  final Float32List times;
  final Float32List values;
  final List<Ease> eases;

  double sample(double t) {
    final n = times.length;
    if (t <= times[0]) return values[0];
    if (t >= times[n - 1]) return values[n - 1];
    var i = 0;
    while (i < n - 2 && t >= times[i + 1]) {
      i++;
    }
    final t0 = times[i], t1 = times[i + 1];
    final k = t1 - t0 <= 1e-9 ? 1.0 : (t - t0) / (t1 - t0);
    final e = ease(eases[i], k);
    return values[i] + (values[i + 1] - values[i]) * e;
  }
}

/// Animation : ensemble de pistes. [next] : état enchaîné à la fin (clips non bouclés).
class Clip {
  Clip(this.duration, this.tracks, {this.loop = false});
  final double duration;
  final List<Track> tracks;
  final bool loop;

  void sampleInto(Pose pose, double t) {
    pose.reset();
    final tt = loop ? (duration <= 0 ? 0.0 : t % duration) : math.min(t, duration);
    for (final tr in tracks) {
      pose.v[tr.bone * Ch.count + tr.ch] = tr.sample(tt);
    }
  }
}

/// États d'animation d'un guerrier.
enum AnimState { idle, move, jump, attack, hit, ko, victory, petrified }

/// Machine à états : un clip par état, transitions en fondu (120–200 ms) depuis
/// un instantané de la pose précédente (pas de fondus imbriqués).
class AnimationStateMachine {
  AnimationStateMachine(this.clips, int bones)
      : _from = Pose(bones),
        _cur = Pose(bones),
        out = Pose(bones);

  final Map<AnimState, Clip> clips;
  final Pose _from;
  final Pose _cur;

  /// Pose résultante (après [update]).
  final Pose out;

  AnimState state = AnimState.idle;
  double time = 0;
  double speed = 1;
  double _blend = 1;
  double _blendDur = 0.15;

  /// État vers lequel enchaîner à la fin d'un clip non bouclé.
  static AnimState? nextOf(AnimState s) => switch (s) {
        AnimState.jump || AnimState.attack || AnimState.hit => AnimState.idle,
        _ => null,
      };

  Clip get clip => clips[state]!;

  /// Progression 0..1 du clip courant (modulo pour les boucles).
  double get progress {
    final d = clip.duration;
    if (d <= 0) return 1;
    return clip.loop ? (time % d) / d : math.min(1.0, time / d);
  }

  bool get finished => !clip.loop && time >= clip.duration;
  bool get blending => _blend < 1;
  double get blendWeight => _blend;

  /// Joue [s]. [duration] : durée imposée (ajuste la vitesse) ; [blend] en secondes.
  void play(AnimState s, {double? duration, double blend = 0.15, bool restart = true}) {
    if (s == state && !restart) return;
    _from.copyFrom(out);
    state = s;
    time = 0;
    final d = clip.duration;
    speed = duration == null || duration <= 0 || d <= 0 ? 1 : d / duration;
    _blendDur = blend.clamp(0.0, 0.5);
    _blend = _blendDur <= 0 ? 1 : 0;
  }

  void update(double dt) {
    time += dt * speed;
    if (_blend < 1) _blend = math.min(1.0, _blend + dt / _blendDur);
    if (finished) {
      final n = nextOf(state);
      if (n != null) {
        clip.sampleInto(_cur, time);
        out.copyFrom(_cur);
        play(n, blend: 0.18);
      }
    }
    clip.sampleInto(_cur, time);
    if (_blend >= 1) {
      out.copyFrom(_cur);
    } else {
      // Fondu adouci (smoothstep) entre l'instantané et le clip courant.
      final w = _blend * _blend * (3 - 2 * _blend);
      out.blend(_from, _cur, w);
    }
  }
}
