#!/usr/bin/env bash
# Hook de contrôle : bloque la fin d'une tâche si les tests du moteur ou du serveur échouent.
cd "$(dirname "$0")/../.." || exit 0
fail=0
if [ -f engine/package.json ]; then
  (cd engine && npm test --silent >/tmp/engine-test.log 2>&1) || { echo "Tests moteur en échec :" >&2; tail -30 /tmp/engine-test.log >&2; fail=1; }
fi
if [ -f server/package.json ] && grep -q '"test"' server/package.json; then
  (cd server && npm test --silent >/tmp/server-test.log 2>&1) || { echo "Tests serveur en échec :" >&2; tail -30 /tmp/server-test.log >&2; fail=1; }
fi
if [ -f app/pubspec.yaml ] && command -v flutter >/dev/null; then
  (cd app && flutter analyze --no-fatal-infos >/tmp/app-analyze.log 2>&1) || { echo "flutter analyze en échec :" >&2; tail -30 /tmp/app-analyze.log >&2; fail=1; }
fi
[ $fail -eq 0 ] || exit 2
