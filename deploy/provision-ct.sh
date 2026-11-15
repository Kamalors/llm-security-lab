#!/bin/bash
# LLM Security Lab -- cree UN conteneur LXC dedie (Ollama + IHM de soutenance) sur
# l'hote Proxmox, sur son propre bridge NAT, SANS toucher aux autres projets
# (VM 200, CT 301-308, vmbr0/1/2/10-16, vmbr20).
#
# Ce que fait --apply, et rien d'autre :
#   1. bridge dedie (10.30.0.1/24) monte via 'ip link' (JAMAIS d'ifreload global),
#      persistance en append pur dans /etc/network/interfaces (bloc balise) ;
#   2. NAT sortant vers vmbr0 pour ce seul sous-reseau (meme modele que vmbr1) et
#      DROP de tout trafic entre ce bridge et les autres bridges ;
#   3. conteneur NON privilegie 'llm-security-lab' : 4 coeurs plafonnes a 3,
#      priorite CPU basse, 6 Gio RAM, 24 Gio disque, root par cle SSH uniquement.
# Ollama, le modele et l'IHM s'installent ensuite PAR SSH dans le conteneur, sans
# root sur l'hote. Ce script ne detruit jamais un invite.
#
# Usage (EN ROOT SUR L'HOTE) :
#   sudo bash provision-ct.sh             # DRY-RUN : controles + plan, ne change rien
#   sudo bash provision-ct.sh --apply     # cree le bridge et le conteneur
#   sudo bash provision-ct.sh --teardown  # retire NOTRE bridge et NOS regles (conteneur a supprimer avant)
set -euo pipefail

CTID="${LAB_CTID:-401}"
BRIDGE="${LAB_BRIDGE:-vmbr30}"
NET="${LAB_NET:-10.30.0}"                 # /24 : hote = .1, conteneur = .10
UPLINK="${LAB_UPLINK:-vmbr0}"
MEM_MB="${LAB_MEM_MB:-6144}"
DISK_GB="${LAB_DISK_GB:-24}"
CT_NAME="llm-security-lab"
EXPECTED_HOST="${LAB_HOST:-PAR861454}"
IFACES=/etc/network/interfaces
PUBKEY="$(dirname "$(readlink -f "$0")")/lab-admin.pub"
PROTECTED="vmbr0 vmbr1 vmbr2 vmbr10 vmbr11 vmbr12 vmbr13 vmbr14 vmbr15 vmbr16 vmbr20"
MARK_BEGIN="# >>> LLM-SECURITY-LAB (NAT dedie au conteneur du labo) >>>"
MARK_END="# <<< LLM-SECURITY-LAB <<<"
# table, puis la regle telle qu'iptables l'attend. Elles ne matchent que NOTRE bridge / sous-reseau.
RULES=(
  "nat POSTROUTING -s $NET.0/24 -o $UPLINK -j MASQUERADE"
  "filter FORWARD -i $BRIDGE ! -o $UPLINK -j DROP"
  "filter FORWARD ! -i $UPLINK -o $BRIDGE -j DROP"
)

MODE="dry-run"
case "${1:-}" in
  --apply)      MODE="apply" ;;
  --teardown)   MODE="teardown" ;;
  ""|--dry-run) MODE="dry-run" ;;
  *) echo "Option inconnue : $1  (attendu: --apply | --teardown | --dry-run)" >&2; exit 2 ;;
esac

die(){ echo "ABORT: $*" >&2; exit 1; }
note(){ echo "[llm-lab] $*"; }

[ "$(id -u)" = 0 ]                   || die "root requis (lancer avec sudo)."
[ "$(hostname)" = "$EXPECTED_HOST" ] || die "hote inattendu '$(hostname)' (attendu '$EXPECTED_HOST'). Rien fait."
for c in ip iptables pct qm pvesm pveam; do command -v "$c" >/dev/null || die "'$c' introuvable."; done
for p in $PROTECTED; do [ "$BRIDGE" != "$p" ] || die "'$BRIDGE' appartient a un autre projet. Choisis un autre nom (LAB_BRIDGE=...)."; done

# Etat des AUTRES invites : doit etre identique avant et apres.
others_state(){
  { qm list 2>/dev/null  | awk 'NR>1{print "vm",$1,$3}'
    pct list 2>/dev/null | awk -v me="$CTID" 'NR>1 && $1!=me{print "ct",$1,$2}'; } | sort
}
bridge_live(){ ip link show "$BRIDGE" >/dev/null 2>&1; }
ours_in_file(){ grep -qF "$MARK_BEGIN" "$IFACES"; }
ct_exists(){ [ -e "/etc/pve/lxc/$CTID.conf" ] || [ -e "/etc/pve/qemu-server/$CTID.conf" ]; }
rules(){   # rules add | rules del
  local r table
  for r in "${RULES[@]}"; do
    # shellcheck disable=SC2086  # decoupage voulu de la regle en mots
    set -- $r; table="$1"; shift
    if [ "$ACTION" = add ]; then iptables -t "$table" -C "$@" 2>/dev/null || iptables -t "$table" -I "$@"
    else iptables -t "$table" -C "$@" 2>/dev/null && iptables -t "$table" -D "$@" || true; fi
  done
}

BEFORE="$(others_state || true)"

# ====================== TEARDOWN ======================
if [ "$MODE" = teardown ]; then
  ct_exists && die "l'invite $CTID existe encore. Verifie son nom puis supprime-le toi-meme : pct stop $CTID && pct destroy $CTID"
  if bridge_live; then
    ours_in_file || die "$BRIDGE existe mais notre bloc est absent de $IFACES : ce n'est pas le notre. Rien fait."
    members="$(ls "/sys/class/net/$BRIDGE/brif" 2>/dev/null || true)"
    [ -z "$members" ] || die "$BRIDGE a des interfaces rattachees ($members)."
    ip link set "$BRIDGE" down || true
    ip link del "$BRIDGE" || true
  fi
  ACTION=del rules
  if ours_in_file; then
    cp -a "$IFACES" "$IFACES.llmlabbak.$(date +%s)"
    awk -v b="$MARK_BEGIN" -v e="$MARK_END" 'index($0,b){skip=1} skip==0{print} index($0,e){skip=0}' "$IFACES" > "$IFACES.tmp" && mv "$IFACES.tmp" "$IFACES"
  fi
  note "teardown termine."
  exit 0
fi

# ====================== PRE-VOL ======================
note "MODE=$MODE  CT=$CTID ($CT_NAME)  BRIDGE=$BRIDGE  RESEAU=$NET.0/24"
note "autres invites (ne seront PAS touches) :"
echo "${BEFORE:-  (aucun)}" | sed 's/^/    /'

ct_exists && die "l'identifiant $CTID est deja pris. Choisis-en un autre (LAB_CTID=...). Rien fait."
NEED_BRIDGE=1
if bridge_live || ours_in_file; then
  # Reprise apres une execution interrompue : on ne continue que si le bridge est bien le notre, complet.
  { bridge_live && ours_in_file; } || die "'$BRIDGE' existe a moitie (live ou fichier, pas les deux). Inspecte, ou --teardown. Rien fait."
  ip -4 addr show dev "$BRIDGE" | grep -qF "$NET.1/24" || die "'$BRIDGE' existe sans l'adresse $NET.1/24. Rien fait."
  NEED_BRIDGE=0
else
  ip -4 route | grep -qF "$NET.0/24" && die "$NET.0/24 est deja route sur l'hote. Choisis un autre reseau (LAB_NET=...). Rien fait."
  grep -qE "^[[:space:]]*(auto|iface)[[:space:]]+$BRIDGE([[:space:]]|\$)" "$IFACES" && die "'$BRIDGE' est deja declare dans $IFACES. Rien fait."
fi
ip link show "$UPLINK" >/dev/null 2>&1 || die "uplink '$UPLINK' introuvable."
[ "$(cat /proc/sys/net/ipv4/ip_forward)" = 1 ] || die "ip_forward=0 : le NAT existant ne fonctionnerait pas non plus. Rien fait."

grep -qE '^ssh-ed25519 [A-Za-z0-9+/]+={0,2}( .*)?$' "$PUBKEY" 2>/dev/null && [ "$(wc -l < "$PUBKEY")" -le 1 ] \
  || die "cle publique attendue (une ligne ssh-ed25519) dans $PUBKEY."
TEMPLATE="$(pveam list local 2>/dev/null | awk '/debian-13-standard/{print $1}' | sort -V | tail -1 || true)"
[ -n "$TEMPLATE" ] || die "aucun gabarit debian-13-standard dans 'local' (pveam update && pveam available | grep debian-13)."
STORAGE="$(pvesm status --content rootdir 2>/dev/null | awk 'NR>1 && $3=="active"{print $1; exit}' || true)"
[ -n "$STORAGE" ] || die "aucun stockage actif acceptant des conteneurs (rootdir)."
AVAIL_MB="$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)"
[ "$AVAIL_MB" -ge $((MEM_MB + 3072)) ] || die "memoire disponible ${AVAIL_MB} Mo < ${MEM_MB} Mo + 3 Gio de reserve pour l'hote. Rien fait."

cat <<EOF
[llm-lab] PLAN :
  - bridge '$BRIDGE' = $NET.1/24 $([ "$NEED_BRIDGE" = 1 ] && echo "(a creer : ip link, append pur dans $IFACES)" || echo "(deja en place, le notre)")
  - iptables : MASQUERADE $NET.0/24 -> $UPLINK ; DROP entre $BRIDGE et tout autre bridge
  - conteneur $CTID '$CT_NAME' : gabarit $TEMPLATE, stockage $STORAGE:${DISK_GB}G,
    4 coeurs (cpulimit 3, cpuunits 50), ${MEM_MB} Mo RAM sans swap, IP $NET.10, non privilegie,
    root par la seule cle : $(cut -d' ' -f3- "$PUBKEY")
  - memoire disponible sur l'hote : ${AVAIL_MB} Mo
EOF
if [ "$MODE" = dry-run ]; then
  note "DRY-RUN : rien n'a ete modifie. Relance avec --apply apres relecture."
  exit 0
fi

# ====================== APPLY ======================
if [ "$NEED_BRIDGE" = 1 ]; then
  SIZE_BEFORE="$(wc -c < "$IFACES")"
  HASH_BEFORE="$(sha256sum "$IFACES" | awk '{print $1}')"
  note "creation live du bridge $BRIDGE (sans toucher les autres)"
  ip link add name "$BRIDGE" type bridge
  ip addr add "$NET.1/24" dev "$BRIDGE"
  ip link set "$BRIDGE" up
  note "persistance (append uniquement) dans $IFACES"
  cp -a "$IFACES" "$IFACES.llmlabbak.$(date +%s)"
  cat >> "$IFACES" <<EOF

$MARK_BEGIN
auto $BRIDGE
iface $BRIDGE inet static
    address $NET.1/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    post-up   iptables -t nat -A POSTROUTING -s $NET.0/24 -o $UPLINK -j MASQUERADE
    post-up   iptables -I FORWARD -i $BRIDGE ! -o $UPLINK -j DROP
    post-up   iptables -I FORWARD ! -i $UPLINK -o $BRIDGE -j DROP
    post-down iptables -t nat -D POSTROUTING -s $NET.0/24 -o $UPLINK -j MASQUERADE
    post-down iptables -D FORWARD -i $BRIDGE ! -o $UPLINK -j DROP
    post-down iptables -D FORWARD ! -i $UPLINK -o $BRIDGE -j DROP
$MARK_END
EOF
  # Preuve d'append pur : le debut du fichier doit etre identique a l'original.
  [ "$(head -c "$SIZE_BEFORE" "$IFACES" | sha256sum | awk '{print $1}')" = "$HASH_BEFORE" ] \
    || die "le debut de $IFACES a change (append non pur). Restaure depuis .llmlabbak."
fi
note "regles iptables (idempotent)"
ACTION=add rules

note "creation du conteneur $CTID"
pct create "$CTID" "$TEMPLATE" --hostname "$CT_NAME" --unprivileged 1 --features nesting=1 \
  --cores 4 --cpulimit 3 --cpuunits 50 --memory "$MEM_MB" --swap 0 --rootfs "$STORAGE:$DISK_GB" \
  --net0 "name=eth0,bridge=$BRIDGE,ip=$NET.10/24,gw=$NET.1" --nameserver 1.1.1.1 \
  --ssh-public-keys "$PUBKEY" --onboot 1 \
  --description "LLM Security Lab (soutenance) : Ollama + IHM. Cree par provision-ct.sh."
pct start "$CTID"

# ====================== VERIFICATION ======================
note "verification"
online=0
# Connexion TCP sortante depuis le conteneur (bash seul : ne depend pas de la presence de ping).
for _ in 1 2 3; do pct exec "$CTID" -- timeout 5 bash -c 'exec 3<>/dev/tcp/1.1.1.1/443' >/dev/null 2>&1 && { online=1; break; }; sleep 2; done
AFTER="$(others_state || true)"
if [ "$BEFORE" != "$AFTER" ]; then
  echo "AVANT:"; echo "$BEFORE" | sed 's/^/  /'
  echo "APRES:"; echo "$AFTER" | sed 's/^/  /'
  die "l'etat des autres invites a change ! Verifie immediatement."
fi
note "OK : conteneur $CTID '$CT_NAME' demarre sur $NET.10, autres invites inchanges."
if [ "$online" = 1 ]; then
  note "Sortie Internet : oui."
else
  # Sur PAR861454, la table nft 'inet hostfw' (chaine forward en policy drop) n'autorise que vmbr1.
  note "Sortie Internet : non, bloquee par le pare-feu de l'hote. C'est sans consequence :"
  note "l'installation se fait par copie de fichiers (deploy/install-guest.sh), le labo tourne hors ligne."
fi
note "Acces : ssh -J lab-host root@$NET.10   (cle : $(cut -d' ' -f3- "$PUBKEY"))"
note "Retrait : pct stop $CTID && pct destroy $CTID, puis sudo bash $0 --teardown"
