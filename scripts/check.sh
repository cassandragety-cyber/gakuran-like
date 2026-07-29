#!/usr/bin/env bash
# Contrôle qualité complet. À lancer avant chaque commit.
#
# Prérequis : rokit/aftman installé, puis `rokit install` (cf. README).
# Le std selene (`roblox.toml`) est généré à la demande s'il manque.

set -euo pipefail
cd "$(dirname "$0")/.."

failures=0
step() { printf "\n\033[1m==> %s\033[0m\n" "$1"; }
fail() { printf "\033[31m    ÉCHEC : %s\033[0m\n" "$1"; failures=$((failures + 1)); }

step "StyLua (format)"
if command -v stylua >/dev/null 2>&1; then
	stylua --check src/ || fail "code non formaté — lancez 'stylua src/'"
else
	fail "stylua introuvable"
fi

step "Selene (lint)"
if command -v selene >/dev/null 2>&1; then
	if [ ! -f roblox.toml ]; then
		printf "    roblox.toml absent, génération...\n"
		selene generate-roblox-std >/dev/null
	fi
	selene src/ || fail "lint en erreur"
else
	fail "selene introuvable"
fi

# Le brief interdit les boucles d'attente actives (budget §6). Selene ne sait
# pas exprimer cette règle, donc on la vérifie ici. On refuse `while true do`
# sans exception : toute attente passe par RunService avec accumulateur, un
# événement, ou task.delay. Le jour où une boucle infinie est réellement
# justifiée, c'est une discussion à avoir, pas un motif à contourner en
# silence.
step "Interdiction des boucles d'attente actives"
if grep -rnE "while[[:space:]]+true[[:space:]]+do" --include="*.luau" src/; then
	fail "boucle 'while true do' détectée"
else
	printf "    aucune occurrence\n"
fi

# Le brief impose un module = une responsabilité, 300 lignes maximum.
step "Taille des modules (300 lignes max)"
oversized=$(find src -name "*.luau" -exec awk 'END { if (NR > 300) printf "%s (%d lignes)\n", FILENAME, NR }' {} \;)
if [ -n "$oversized" ]; then
	printf "%s\n" "$oversized"
	fail "module(s) au-dessus de la limite — à découper"
else
	printf "    tous les modules sont sous la limite\n"
fi

# --!strict est obligatoire en tête de chaque module (stack technique imposée).
step "En-tête --!strict"
missing=$(grep -rLE "^--!strict" --include="*.luau" src/ || true)
if [ -n "$missing" ]; then
	printf "%s\n" "$missing"
	fail "module(s) sans --!strict"
else
	printf "    tous les modules sont en mode strict\n"
fi

printf "\n"
if [ "$failures" -gt 0 ]; then
	printf "\033[31m%d contrôle(s) en échec.\033[0m\n" "$failures"
	exit 1
fi
printf "\033[32mTous les contrôles passent.\033[0m\n"
