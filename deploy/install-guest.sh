#!/bin/bash
# LLM Security Lab -- installe Node.js, Ollama, le modele cible et l'API/IHM DANS le conteneur du labo.
# A lancer en root dans le conteneur 'llm-security-lab' (jamais sur l'hote Proxmox). Idempotent.
#
# Installation HORS LIGNE : le pare-feu de l'hote (table nft 'inet hostfw', chaine forward en
# policy drop) ne laisse pas sortir le conteneur. Tout est telecharge sur le PC depuis les sources
# officielles, verifie par empreinte SHA-256, puis copie ici (voir README, « Installer le labo »).
# Attendu dans /opt/llm-security-lab :
#   app/ verifier/ package.json               le projet
#   dl/node-v*-linux-x64.tar.gz               Node.js (nodejs.org)
#   dl/ollama-cpu.tar.gz                      Ollama (bin/ et lib/ de la version officielle, sans les bibliotheques GPU)
#   dl/models/manifest.json + blobs/sha256-*  le modele, tel que servi par registry.ollama.ai
# automation/demo_llm.ps1 s'appuie sur ces noms : /opt/llm-security-lab/.env, services 'ollama' et 'llm-lab', port 8080.
set -euo pipefail

APP=/opt/llm-security-lab
DL=$APP/dl
MODEL="${TARGET_MODEL:-qwen2.5:1.5b}"
STORE=/usr/share/ollama/.ollama/models
die(){ echo "ABORT: $*" >&2; exit 1; }
note(){ echo "[llm-lab] $*"; }
attendre(){ for _ in $(seq 1 "$2"); do (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && return 0; sleep 1; done; return 1; }

[ "$(id -u)" = 0 ]                   || die "root requis."
[ "$(hostname)" = llm-security-lab ] || die "a lancer dans le conteneur 'llm-security-lab', pas sur '$(hostname)'."
[ -f "$APP/app/server.mjs" ] && [ -f "$APP/verifier/verify.mjs" ] || die "sources absentes de $APP (voir l'en-tete)."

if ! command -v node >/dev/null; then
  tgz="$(ls "$DL"/node-v*-linux-x64.tar.gz 2>/dev/null | tail -1)"; [ -n "$tgz" ] || die "archive Node.js absente de $DL."
  note "Node.js : $(basename "$tgz")"
  tar -xzf "$tgz" -C /opt
  ln -sfn "/opt/$(basename "$tgz" .tar.gz)/bin/node" /usr/local/bin/node
fi

if [ ! -x /usr/local/bin/ollama ]; then
  [ -f "$DL/ollama-cpu.tar.gz" ] || die "archive Ollama absente de $DL."
  note "Ollama : extraction sous /usr/local"
  tar -xzf "$DL/ollama-cpu.tar.gz" -C /usr/local
fi
# Utilisateur et service : ceux de l'installation manuelle documentee par Ollama.
id ollama >/dev/null 2>&1 || useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama
cat > /etc/systemd/system/ollama.service <<EOF
[Unit]
Description=Ollama (modele cible du labo)
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment=OLLAMA_HOST=127.0.0.1:11434
Environment=OLLAMA_MAX_LOADED_MODELS=1
Environment=OLLAMA_NUM_PARALLEL=1

[Install]
WantedBy=multi-user.target
EOF

# Modele : les memes fichiers que 'ollama pull', deposes dans le magasin d'Ollama.
name="${MODEL%%:*}"; tag="${MODEL##*:}"
if [ ! -f "$STORE/manifests/registry.ollama.ai/library/$name/$tag" ]; then
  [ -f "$DL/models/manifest.json" ] || die "modele absent de $DL/models."
  note "modele $MODEL : copie dans le magasin d'Ollama"
  install -d "$STORE/blobs" "$STORE/manifests/registry.ollama.ai/library/$name"
  mv "$DL"/models/blobs/sha256-* "$STORE/blobs/"
  cp "$DL/models/manifest.json" "$STORE/manifests/registry.ollama.ai/library/$name/$tag"
fi
chown -R ollama:ollama /usr/share/ollama

systemctl daemon-reload
systemctl enable ollama >/dev/null 2>&1
systemctl restart ollama
attendre 11434 30 || die "Ollama ne demarre pas : journalctl -u ollama -n 30"
ollama list | grep -q "^$MODEL" || die "Ollama ne liste pas $MODEL : journalctl -u ollama -n 30"

id llmlab >/dev/null 2>&1 || useradd --system --home-dir "$APP" --shell /usr/sbin/nologin llmlab
install -d -o llmlab -g llmlab -m 700 "$APP/data"
if [ ! -f "$APP/.env" ]; then
  # Jetons generes ici, jamais dans le depot. NUM_THREAD suit le plafond CPU du conteneur (cpulimit 3).
  jeton(){ head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
  ( umask 077; cat > "$APP/.env" <<EOF
LAB_HUMAN_TOKEN=$(jeton)
LAB_HERMES_TOKEN=$(jeton)
OLLAMA_URL=http://127.0.0.1:11434
TARGET_MODEL=$MODEL
NUM_THREAD=3
DATA_DIR=$APP/data
REPORT_DIR=$APP/reports
EOF
  )
  chown root:llmlab "$APP/.env"; chmod 640 "$APP/.env"
fi

# ponytail: durcissement systemd minimal (utilisateur dedie, ecoute sur 127.0.0.1 par defaut du serveur).
# ProtectSystem/PrivateTmp echouent souvent dans un LXC non privilegie ; a ajouter si le labo sort de ce conteneur.
cat > /etc/systemd/system/llm-lab.service <<EOF
[Unit]
Description=LLM Security Lab : API et IHM de soutenance
After=network-online.target ollama.service
Wants=ollama.service

[Service]
User=llmlab
WorkingDirectory=$APP
EnvironmentFile=$APP/.env
ExecStart=/usr/local/bin/node app/server.mjs
Restart=on-failure
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable llm-lab >/dev/null 2>&1
systemctl restart llm-lab
attendre 8080 15 || die "l'API ne repond pas : journalctl -u llm-lab -n 30"
rm -rf "$DL"
note "OK : $(ollama --version 2>/dev/null | tail -1), node $(node --version), modele $MODEL, API sur 127.0.0.1:8080."
