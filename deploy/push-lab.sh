#!/bin/bash
# LLM Security Lab -- deploie le labo dans le conteneur, depuis le PC (Git Bash) :
#   bash deploy/push-lab.sh
# Le conteneur n'a pas de sortie Internet (pare-feu de l'hote). Ce script telecharge donc sur le PC
# depuis les sources officielles, exige les empreintes SHA-256 epinglees ci-dessous, copie par scp,
# puis lance deploy/install-guest.sh dans le conteneur.
# Relancable : si Node.js, Ollama et le modele sont deja en place, seul le projet (app/, verifier/)
# est recopie et l'API redemarree. C'est aussi la commande pour pousser une modification de l'IHM.
set -euo pipefail
cd "$(dirname "$0")/.."

SSH=(-F automation/ssh_config)
DEST=/opt/llm-security-lab
DL="${LAB_DL:-$HOME/.cache/llm-security-lab}"
NODE=v24.22.2;   NODE_SHA=361718c444e49af2ca5a110c83ba6a8901143f23ab285ebbef0341f391f482a9
OLLAMA=v0.40.16; OLLAMA_SHA=87bfafb2acbc89b2e6a1be0a9043de6aa75fb450696f86bc426e65fc448f788d
MODEL=qwen2.5;   TAG=1.5b; MANIFEST_SHA=65ec06548149b04c096a120e4a6da9d4017ea809c91734ea5631e89f96ddc57b
REG="https://registry.ollama.ai/v2/library/$MODEL"

note(){ echo "[push-lab] $*"; }
# fetch URL FICHIER SHA256 [options curl] : telecharge si absent, puis exige l'empreinte.
fetch(){
  local url="$1" out="$2" sha="$3"; shift 3
  [ -f "$out" ] || { curl -fL --retry 2 "$@" -o "$out.part" "$url" && mv "$out.part" "$out"; }
  echo "$sha *$out" | sha256sum -c - >/dev/null 2>&1 || { echo "ABORT: empreinte inattendue pour $out (fichier a supprimer avant de relancer)." >&2; exit 1; }
}

ssh "${SSH[@]}" llm-lab "mkdir -p $DEST"
if ssh "${SSH[@]}" llm-lab "test -x /usr/local/bin/ollama && test -x /usr/local/bin/node && test -f /usr/share/ollama/.ollama/models/manifests/registry.ollama.ai/library/$MODEL/$TAG"; then
  note "Node.js, Ollama et le modele sont deja dans le conteneur : rien a telecharger."
else
  mkdir -p "$DL/node" "$DL/ollama" "$DL/model/blobs"
  note "Node.js $NODE"
  fetch "https://nodejs.org/dist/$NODE/node-$NODE-linux-x64.tar.gz" "$DL/node/node-$NODE-linux-x64.tar.gz" "$NODE_SHA"
  note "modele $MODEL:$TAG (1 Go)"
  fetch "$REG/manifests/$TAG" "$DL/model/manifest.json" "$MANIFEST_SHA" -H "Accept: application/vnd.docker.distribution.manifest.v2+json"
  # Chaque fichier du modele est nomme par sa propre empreinte dans le manifeste.
  for d in $(grep -oE 'sha256:[0-9a-f]{64}' "$DL/model/manifest.json" | sort -u); do
    fetch "$REG/blobs/$d" "$DL/model/blobs/sha256-${d#sha256:}" "${d#sha256:}"
  done
  note "Ollama $OLLAMA (1,5 Go)"
  fetch "https://github.com/ollama/ollama/releases/download/$OLLAMA/ollama-linux-amd64.tar.zst" "$DL/ollama/ollama-linux-amd64.tar.zst" "$OLLAMA_SHA"
  # Les bibliotheques GPU (2,4 Go) ne servent a rien sur ce serveur sans carte graphique.
  # tar.exe de Windows (bsdtar) lit le zstd et sait recopier une archive en filtrant ses entrees.
  ( cd "$DL/ollama" && /c/Windows/System32/tar.exe -czf ollama-cpu.tar.gz --exclude "lib/ollama/cuda_*" --exclude "lib/ollama/vulkan*" --exclude "lib/ollama/mlx*" @ollama-linux-amd64.tar.zst )
  note "copie dans le conteneur"
  ssh "${SSH[@]}" llm-lab "mkdir -p $DEST/dl/models"
  scp -q "${SSH[@]}" "$DL/ollama/ollama-cpu.tar.gz" "$DL/node/node-$NODE-linux-x64.tar.gz" "llm-lab:$DEST/dl/"
  scp -q "${SSH[@]}" "$DL/model/manifest.json" "llm-lab:$DEST/dl/models/"
  scp -q -r "${SSH[@]}" "$DL/model/blobs" "llm-lab:$DEST/dl/models/"
fi

note "projet"
scp -q -r "${SSH[@]}" app verifier package.json deploy/install-guest.sh "llm-lab:$DEST/"
ssh "${SSH[@]}" llm-lab "bash $DEST/install-guest.sh"
