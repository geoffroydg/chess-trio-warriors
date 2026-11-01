#!/bin/sh
# Fabrique une page unique (sans fichier externe) pour la publier comme Artifact claude.ai.
# Usage : sh scripts/build-artifact.sh [fichier-de-sortie]
set -e
cd "$(dirname "$0")/.."
OUT="${1:-build/artifact.html}"
mkdir -p "$(dirname "$OUT")"
{
  sed -n '/<!-- BEGIN PAGE -->/,/<!-- END HEAD -->/p' www/index.html
  sed -n '/<!-- BEGIN BODY -->/,/<!-- END BODY -->/p' www/index.html
  echo '<script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>'
  echo '<script>'
  cat www/game.js
  echo '</script>'
} > "$OUT"
echo "Page créée : $OUT"
