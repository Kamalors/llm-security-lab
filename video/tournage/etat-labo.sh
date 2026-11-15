#!/usr/bin/env bash
# État des essais du labo pendant le tournage de la vidéo. En root dans le conteneur :
#   ssh -F automation/ssh_config llm-lab 'bash -s' -- <commande> < video/tournage/etat-labo.sh
# Commandes : mettre-de-cote | archiver <prise> | restaurer | bilan
# Le jeton du labo est lu dans .env par node et n'est jamais affiché.
# Le fichier EN-COURS marque un tournage entre mettre-de-cote et restaurer ; restaurer peut être relancé sans risque.
set -euo pipefail
LAB_DIR=${LAB_DIR:-/opt/llm-security-lab}
DATA="$LAB_DIR/data"
COTE="$LAB_DIR/mis-de-cote-2026-11-15"
TOURNAGE="$LAB_DIR/tournage-2026-11-15"
EN_COURS="$COTE/EN-COURS"
MANIFESTE="$COTE/MANIFEST.sha256"

sessions() { ls "$1" 2>/dev/null | grep -E '^[0-9a-f]{32}\.json$' || true; }
stop() { echo "refus : $*" >&2; exit 1; }
liste() { grep -qE "^[0-9a-f]{64} [ *]$1\$" "$MANIFESTE" 2>/dev/null; }   # « h  f » sous Linux, « h *f » sous Git Bash
du_groupe() { for f in $(sessions "$DATA"); do liste "$f" && echo "$f"; done; true; }
etrangers() { for f in $(sessions "$DATA"); do liste "$f" || echo "$f"; done; true; }
verifier() {  # data/ identique au manifeste (essais et notes)
  (cd "$DATA" && { [ ! -s "$MANIFESTE" ] || sha256sum -c --quiet "$MANIFESTE"; } && { [ ! -f "$COTE/NOTES.sha256" ] || sha256sum -c --quiet "$COTE/NOTES.sha256"; })
}
APPARU="un notes.json est apparu pendant le tournage : le ranger dans $TOURNAGE, puis relancer"

api() {  # api <chemin> : GET authentifié sur l'API locale, corps JSON sur la sortie
  LAB_ENV="$LAB_DIR/.env" CHEMIN="$1" node -e '
    const env = require("fs").readFileSync(process.env.LAB_ENV, "utf8");
    const jeton = env.match(/^LAB_HUMAN_TOKEN=(.*)$/m)[1].trim();
    fetch("http://127.0.0.1:8080" + process.env.CHEMIN, { headers: { Authorization: "Bearer " + jeton } })
      .then(r => r.ok ? r.text() : Promise.reject(new Error("HTTP " + r.status))).then(t => process.stdout.write(t))
      .catch(e => { console.error(e.message); process.exit(1); });'
}

redemarrer() {
  [ -n "${NO_RESTART:-}" ] && return 0
  systemctl restart llm-lab
  for _ in $(seq 30); do api /api/status >/dev/null 2>&1 && return 0; sleep 1; done
  stop "l'API ne répond pas après le redémarrage"
}

case "${1:-}" in
  mettre-de-cote)
    [ ! -e "$EN_COURS" ] || stop "un tournage est déjà en cours : lancer restaurer d'abord"
    [ -z "$(sessions "$COTE")" ] || stop "$COTE contient déjà des essais"
    mkdir -p "$COTE"
    (cd "$DATA" && for f in $(sessions .); do sha256sum "$f"; done) > "$MANIFESTE"
    if [ -f "$DATA/notes.json" ]; then (cd "$DATA" && sha256sum notes.json) > "$COTE/NOTES.sha256"; else rm -f "$COTE/NOTES.sha256"; fi
    touch "$EN_COURS"
    for f in $(sessions "$DATA"); do mv "$DATA/$f" "$COTE/"; done
    [ ! -f "$DATA/notes.json" ] || mv "$DATA/notes.json" "$COTE/"   # le labo filmé part vide, et les notes sont à l'abri
    redemarrer
    echo "mis de côté : $(sessions "$COTE" | wc -l) essais"
    ;;
  archiver)
    prise=${2:?nom de prise manquant}
    [ -e "$EN_COURS" ] || stop "aucun tournage en cours : les essais de data/ sont ceux du groupe"
    [ -z "$(du_groupe)" ] || stop "data/ contient des essais du groupe (mise de côté interrompue ?) : lancer restaurer"
    [ ! -e "$TOURNAGE/$prise" ] || stop "$TOURNAGE/$prise existe déjà"
    mkdir -p "$TOURNAGE/$prise"
    for f in $(sessions "$DATA"); do mv "$DATA/$f" "$TOURNAGE/$prise/"; done
    redemarrer
    echo "archivé : $(sessions "$TOURNAGE/$prise" | wc -l) essais dans $prise"
    ;;
  restaurer)
    [ -f "$MANIFESTE" ] || stop "aucun manifeste dans $COTE"
    if [ ! -e "$EN_COURS" ]; then
      verifier || stop "aucun tournage en cours, et data/ ne correspond pas au manifeste"
      echo "déjà restauré : $(sessions "$DATA" | wc -l) essais, empreintes identiques"; exit 0
    fi
    [ -z "$(etrangers)" ] || stop "data/ contient des essais du tournage : les archiver d'abord"   # ceux du groupe (reprise) restent
    if [ -f "$COTE/notes.json" ]; then [ ! -f "$DATA/notes.json" ] || stop "$APPARU"; mv "$COTE/notes.json" "$DATA/"
    elif [ -f "$DATA/notes.json" ] && [ ! -f "$COTE/NOTES.sha256" ]; then stop "$APPARU"; fi
    for f in $(sessions "$COTE"); do mv "$COTE/$f" "$DATA/"; done
    verifier || stop "empreintes différentes"
    rm -f "$EN_COURS"
    redemarrer
    echo "restauré : $(sessions "$DATA" | wc -l) essais, empreintes identiques"
    ;;
  bilan)
    api /api/sessions | node -e '
      let t = ""; process.stdin.on("data", d => t += d).on("end", () => {
        const l = JSON.parse(t).sort((a, b) => String(a.created).localeCompare(String(b.created)));
        for (const s of l) console.log(s.scenario, s.verdict, (s.turns || []).length);
      });'
    ;;
  *) stop "commande inconnue : ${1:-} (mettre-de-cote | archiver <prise> | restaurer | bilan)" ;;
esac
