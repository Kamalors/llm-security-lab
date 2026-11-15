#!/usr/bin/env bash
# Test local de etat-labo.sh sur un faux LAB_DIR : bash video/tournage/test_etat_labo.sh
set -uo pipefail
ICI=$(cd "$(dirname "$0")" && pwd)
S="$ICI/etat-labo.sh"
L=$(mktemp -d); trap 'rm -rf "$L"' EXIT
export LAB_DIR="$L" NO_RESTART=1
mkdir -p "$L/data"
session() { printf '{"id":"%s","n":%s}' "$1" "$2" > "$L/data/$1.json"; }
echoue() { echo "ÉCHEC : $*"; exit 1; }
nb() { ls "$1" 2>/dev/null | grep -cE '^[0-9a-f]{32}\.json$'; }
A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; C=cccccccccccccccccccccccccccccccc
session $A 1; session $B 2; session $C 3
avant=$(cd "$L/data" && sha256sum *.json)

bash "$S" mettre-de-cote >/dev/null || echoue "mettre-de-cote"
[ "$(nb "$L/data")" = 0 ] || echoue "data/ pas vide après mettre-de-cote"
[ "$(wc -l < "$L/mis-de-cote-2026-11-15/MANIFEST.sha256")" = 3 ] || echoue "manifeste ≠ 3 lignes"

session dddddddddddddddddddddddddddddddd 4; session eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee 5
bash "$S" restaurer >/dev/null 2>&1 && echoue "restaurer accepté avec une prise non archivée"
bash "$S" archiver prise1 >/dev/null || echoue "archiver prise1"
[ "$(nb "$L/tournage-2026-11-15/prise1")" = 2 ] || echoue "prise1 ≠ 2 fichiers"
bash "$S" archiver prise1 >/dev/null 2>&1 && echoue "archiver prise1 deux fois accepté"

bash "$S" restaurer >/dev/null || echoue "restaurer"
[ "$(cd "$L/data" && sha256sum *.json)" = "$avant" ] || echoue "empreintes différentes après restaurer"

# Second mettre-de-cote alors que le dossier mis de côté contient encore une session
cp "$L/data/$A.json" "$L/mis-de-cote-2026-11-15/"
bash "$S" mettre-de-cote >/dev/null 2>&1 && echoue "mettre-de-cote accepté sur un dossier non vide"
rm "$L/mis-de-cote-2026-11-15/$A.json"

# notes.json apparu pendant le tournage : restaurer refuse
bash "$S" mettre-de-cote >/dev/null || echoue "mettre-de-cote (2)"
echo '{}' > "$L/data/notes.json"
bash "$S" restaurer >/dev/null 2>&1 && echoue "restaurer accepté avec un notes.json nouveau"

# Reprises : chaque cas part d'un labo neuf avec trois essais du groupe et des notes
neuf() { rm -rf "$L"/*; mkdir -p "$L/data"; session $A 1; session $B 2; session $C 3; echo '{"entreprise":"x"}' > "$L/data/notes.json"
         etat=$(cd "$L/data" && sha256sum *.json); }
D="$L/mis-de-cote-2026-11-15"

neuf; bash "$S" mettre-de-cote >/dev/null || echoue "mettre-de-cote (notes)"
[ ! -e "$L/data/notes.json" ] || echoue "notes.json laissé dans data/ pendant le tournage"
bash "$S" restaurer >/dev/null || echoue "restaurer (notes)"
[ "$(cd "$L/data" && sha256sum *.json)" = "$etat" ] || echoue "notes ou essais différents après restaurer"

bash "$S" restaurer >/dev/null 2>&1 || echoue "restaurer relancé : doit dire « déjà restauré », pas refuser"
bash "$S" archiver prise9 >/dev/null 2>&1 && echoue "archiver accepté sans tournage en cours (essais du groupe archivés)"
[ "$(nb "$L/data")" = 3 ] || echoue "essais du groupe déplacés par archiver"

neuf; bash "$S" mettre-de-cote >/dev/null; mv "$D/$A.json" "$L/data/"   # mise de côté coupée en route
bash "$S" archiver prise9 >/dev/null 2>&1 && echoue "archiver accepté avec un essai du groupe dans data/"
bash "$S" restaurer >/dev/null || echoue "restaurer après une mise de côté interrompue"
[ "$(cd "$L/data" && sha256sum *.json)" = "$etat" ] || echoue "empreintes différentes après reprise (1)"

neuf; bash "$S" mettre-de-cote >/dev/null; mv "$D/$B.json" "$L/data/"   # restauration coupée en route
bash "$S" restaurer >/dev/null || echoue "restaurer interrompu puis relancé"
[ "$(cd "$L/data" && sha256sum *.json)" = "$etat" ] || echoue "empreintes différentes après reprise (2)"
echo ok
