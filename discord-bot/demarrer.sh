#!/usr/bin/env bash
# Démarrage sur Linux / macOS, avec redémarrage automatique en cas de crash.
cd "$(dirname "$0")"
[ -d node_modules ] || npm install --omit=dev
[ -f .env ] || { cp .env.example .env; echo "Remplis .env (TOKEN, OWNER_IDS) puis relance."; exit 1; }
while true; do
  node src/index.js
  echo "Le bot s'est arrêté, redémarrage dans 5 s (Ctrl+C pour annuler)…"
  sleep 5
done
