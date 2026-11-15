# -*- coding: utf-8 -*-
"""Voix, texte affiché, sous-titres et chapitres : copie des fonctions du moteur de la vidéo RAO
(Documents/Sécurité des infrastructure/presentation/sources/video/build.py), qui reste intact.
Seuls LEXIQUE et AFFICHAGE sont propres au labo LLM ; chapitres_ffmetadata reçoit directement les débuts des chapitres."""
import asyncio
import hashlib
import re
import subprocess
import wave
from pathlib import Path

import imageio_ffmpeg
import numpy as np

FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
SR = 48000
FPS = 30

# (motif, remplacement) appliqués au seul texte lu, ajustés d'après la transcription Whisper (prononciation.py).
LEXIQUE = [(r"PIRATE_LAB", "PIRATE LAB"), (r"\bAPPROVED\b", "« Approved »"), (r"\bDENIED\b", "« Denied »"), (r"\bLakera\b", "Lakéra")]

# graphie normale pour les sous-titres (le texte lu épelle certains sigles : « O-WASP », « L-L-M »)
AFFICHAGE = [(r"\bO-WASP\b", "OWASP"), (r"\bQwen deux point cinq\b", "Qwen 2.5")]


def run(args, **kw):
    r = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace", **kw)
    if r.returncode:
        raise RuntimeError(f"échec : {' '.join(map(str, args[:6]))}…\n{r.stderr[-1500:]}")
    return r


_VAL = {"zéro": 0, "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7, "huit": 8,
        "neuf": 9, "dix": 10, "onze": 11, "douze": 12, "treize": 13, "quatorze": 14, "quinze": 15, "seize": 16,
        "vingt": 20, "vingts": 20, "trente": 30, "quarante": 40, "cinquante": 50, "soixante": 60,
        "cent": 100, "cents": 100, "mille": 1000}


_NW = "(?:" + "|".join(sorted(_VAL, key=len, reverse=True)) + ")"


_DIZ = "".join(f"(?<={d})|" for d in ("vingt", "trente", "quarante", "cinquante", "soixante"))[:-1]


_RUN = rf"{_NW}(?:[ -]{_NW}|(?:{_DIZ}) et (?:une?|onze)\b)*"


_NOMBRE = re.compile(rf"\b(?P<ent>{_RUN})(?: virgule (?P<dec>{_RUN}))?\b(?P<mult> millions?| milliards?)?", re.I)


_POST = [(r"(\d) euros hors taxes\b", "\\1\u00a0€\u00a0HT"), (r"(\d) millions? d'euros\b", "\\1\u00a0M€"),
         (r"(\d) euros (\d{2})\b", "\\1,\\2\u00a0€"), (r"(\d) euros\b", "\\1\u00a0€"),
         (r"(\d) minutes (\d{2})\b", "\\1\u00a0min\u00a0\\2"), (r"\b(\d+) ([FG])\b", r"\1\2"),
         (r"(\d) mois\b", "\\1\u00a0mois")]


def _valeur(texte):
    """« quatre-vingt-dix-huit » -> 98 ; None si la suite de mots n'est pas un seul nombre (« trois-deux-un »)."""
    total, cur = 0, 0
    for m in re.split(r"[ -]+", texte.lower()):
        if m == "et":
            continue
        v, bas = _VAL[m], cur % 100
        if m.startswith("vingt") and bas == 4:      # quatre-vingt(s)
            cur += 76
        elif v < 100:
            if bas and not ((bas % 10 == 0 and v < 10) or (bas in (60, 80) and 10 <= v < 20)):
                return None
            cur += v
        elif v == 100:
            if cur >= 100:
                return None
            cur = (cur or 1) * 100
        else:                                        # mille
            if total:
                return None
            total, cur = (cur or 1) * 1000, 0
    return total + cur


def _fmt(n):
    annee = 1900 <= n <= 2099 and n % 100
    return str(n) if n < 1000 or annee else f"{n:,}".replace(",", " ")


def chiffres(texte):
    texte = re.sub(r" ?\bpour cent\b", " %", texte)

    def rempl(m):
        ent, dec, mult = m.group("ent"), m.group("dec"), m.group("mult") or ""
        n = _valeur(ent)
        d = _valeur(dec) if dec else None
        if n is None or (dec and d is None):
            return m.group(0)
        if ent.lower() in ("un", "une") and not dec:
            return m.group(0)                        # article (« un pare-feu », « un million et demi »)
        debut = texte[:m.start()]
        if n < 10 and not dec and not mult and (not debut.strip() or re.search(r"[.!?]\s*$", debut)):
            return m.group(0)                        # jamais un chiffre en début de phrase : « Deux, les schémas… »
        return _fmt(n) + (f",{d}" if dec else "") + mult

    texte = _NOMBRE.sub(rempl, texte)
    for motif, r in _POST:
        texte = re.sub(motif, r, texte)
    return texte


def pour_affichage(texte):
    for motif, rempl in AFFICHAGE:  # cas particuliers d'abord (« S-D WAN » donne « SD-WAN », pas « SD WAN »)
        texte = re.sub(motif, rempl, texte)
    texte = re.sub(r"\b[A-Z](?:-[A-Z])+\b", lambda m: m.group(0).replace("-", ""), texte)
    return chiffres(texte)


def en_lettres(t):
    """« 221 424 € », « 7,97 M€ », « 20 % » -> mots : longueur parlée d'un sous-titre, comparaison avec Whisper."""
    from num2words import num2words
    t = re.sub(r"(\d)[\s  ](?=\d{3}\b)", r"\1", t)
    t = t.replace("%", " pour cent ").replace("M€", " millions d'euros ").replace("€", " euros ")
    t = re.sub(r"(\d+),(\d+)", lambda m: f"{num2words(int(m[1]), lang='fr')} virgule {num2words(int(m[2]), lang='fr')}", t)
    return re.sub(r"\d+", lambda m: num2words(int(m[0]), lang="fr"), t)


def prononcer(texte):
    for motif, rempl in LEXIQUE:
        texte = re.sub(motif, rempl, texte)
    return texte


def empreinte(texte, voix, debit, ton):
    return hashlib.sha1(f"{voix}|{debit}|{ton}|{texte}".encode("utf-8")).hexdigest()[:16]


async def _edge(texte, voix, debit, ton, mp3, sem):
    import edge_tts
    async with sem:
        for essai in range(4):
            try:
                await edge_tts.Communicate(texte, voix, rate=debit, pitch=ton).save(str(mp3))
                return
            except Exception:  # coupure réseau : on réessaie
                if essai == 3:
                    raise
                await asyncio.sleep(2 + essai * 3)


def synthese_edge(taches, voix, ton):
    async def tout():
        sem = asyncio.Semaphore(4)
        await asyncio.gather(*(_edge(t, voix, d, ton, mp3, sem) for t, mp3, d in taches))
    asyncio.run(tout())


def vers_wav(src, dst):
    """48 kHz mono, silences de début et de fin retirés (les pauses sont ensuite maîtrisées par la chronologie)."""
    trim = "silenceremove=start_periods=1:start_threshold=-48dB:start_silence=0.05," \
           "areverse,silenceremove=start_periods=1:start_threshold=-48dB:start_silence=0.08,areverse"
    run([FFMPEG, "-y", "-i", str(src), "-af", trim, "-ar", str(SR), "-ac", "1", "-sample_fmt", "s16", str(dst)])


def lire_wav(path):
    with wave.open(str(path)) as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)


MAX_CUE, MAX_LIGNE, MIN_DUREE = 82, 44, 1.2


_MAL_COUPE = re.compile(r"\b(?:le|la|les|de|du|des|un|une|à|au|aux|et|en|par|pour|sur|dans|sans|ne|ce|ses|son|sa|nos|vos|que|qui)$")


def _moities(m):
    """Morceau trop long : moitiés équilibrées (pas de reste orphelin comme « B. » en tête du bloc suivant)."""
    if len(m) <= MAX_CUE:
        return [m]
    a, b = _deux_lignes(m, MAX_CUE).split("\n")
    return _moities(a) + _moities(b)


def _reequilibre(t):
    """Deux blocs d'au moins 25 caractères : coupure à la ponctuation la plus centrale, sinon entre deux mots."""
    m = [x for x in re.split(r"(?<=[,;:]) +", t) if x]
    coupes = [(" ".join(m[:k]), " ".join(m[k:])) for k in range(1, len(m))]
    coupes = [c for c in coupes if min(map(len, c)) >= 25 and max(map(len, c)) <= MAX_CUE]
    return list(min(coupes, key=lambda c: max(map(len, c)))) if coupes else _moities(t)


def _decoupe(texte):
    """Blocs de 84 caractères au plus : coupure aux fins de phrase, puis à la ponctuation, puis entre deux mots.
    Les espaces insécables (« 221 424 € ») ne sont jamais des points de coupure."""
    phrases = [s.strip() for s in re.split(r"(?<=[.!?…])\s+", texte) if s.strip()]
    blocs = []
    for ph in phrases:
        if len(ph) <= MAX_CUE:
            blocs.append(ph)
            continue
        morceaux = [m.strip() for m in re.split(r"(?<=[,;:]) +", ph) if m.strip()]
        bp, cur = [], ""
        for m in morceaux:
            if len(m) > MAX_CUE:
                if cur:
                    bp.append(cur)
                *debut, cur = _moities(m)
                bp += debut
            elif len(cur) + len(m) + 1 <= MAX_CUE:
                cur = (cur + " " + m).strip()
            else:
                bp.append(cur)
                cur = m
        if cur:
            bp.append(cur)
        if len(bp) > 1 and len(bp[-1]) < 25:  # reste orphelin : les deux derniers blocs rééquilibrés
            bp[-2:] = _reequilibre(bp[-2] + " " + bp[-1])
        blocs += bp
    fusion = []  # regroupe les blocs courts avec le suivant tant que la limite le permet
    for b in blocs:
        if fusion and len(fusion[-1]) + len(b) + 1 <= MAX_CUE and (len(fusion[-1]) < 30 or len(b) < 30):
            fusion[-1] = fusion[-1] + " " + b
        else:
            fusion.append(b)
    return fusion


def _deux_lignes(b, limite=MAX_LIGNE):
    """Deux lignes équilibrées, coupées de préférence après une ponctuation, jamais après un nombre ou un article."""
    if len(b) <= limite:
        return b
    mots, meilleur = b.split(" "), None
    for i in range(1, len(mots)):
        l1, l2 = " ".join(mots[:i]), " ".join(mots[i:])
        score = abs(len(l1) - len(l2)) + (0 if l1[-1] in ",;:." else 6) + (100 if l1[-1].isdigit() else 12 if _MAL_COUPE.search(l1) else 0) \
            + (100 if max(len(l1), len(l2)) > limite else 0)
        if meilleur is None or score < meilleur[0]:
            meilleur = (score, l1, l2)
    return meilleur[1] + "\n" + meilleur[2]


def _poids(b):
    """Durée relative d'un bloc : sa longueur parlée, plus les pauses de ponctuation et les sigles épelés."""
    t = re.sub(r"\bHT\b", "hors taxes", re.sub(r"\bmin\b", "minutes", en_lettres(b)))
    return len(t) + 4 * len(re.findall(r"[,;]", b)) + 8 * len(re.findall(r"[.:?!]", b)) \
        + 2 * len(re.findall(r"[A-Z](?=[A-Z])|(?<=[A-Z])[A-Z]", b))


def sous_titres(script, beats, chemin):
    """Sous-titres SRT en chiffres ; durée de chaque bloc au prorata de sa longueur parlée, 1,2 s au minimum."""
    def ts(x):  # arrondi à la milliseconde d'abord : 394,9996 s donne 00:06:35,000, pas 00:06:34,000
        ms = round(x * 1000)
        return f"{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d},{ms % 1000:03d}"
    cues, n = [], 1
    for si, bi, t0, d in beats:
        blocs = _decoupe(pour_affichage(script["scenes"][si]["beats"][bi]["say"].strip()))
        # un bloc qu'aucune coupure ne met en deux lignes de 44 caractères devient deux blocs d'une ligne
        blocs = [x for b in blocs for x in ([b] if max(map(len, _deux_lignes(b).split("\n"))) <= MAX_LIGNE
                                             else _deux_lignes(b, len(b) // 2 + 12).split("\n"))]
        poids = [_poids(b) for b in blocs]
        durees = [d * p / (sum(poids) or 1) for p in poids]
        for i, du in enumerate(durees):  # un bloc trop bref emprunte du temps à son voisin
            if du < MIN_DUREE and len(durees) > 1:
                j = i - 1 if i else i + 1
                manque = min(MIN_DUREE - du, max(0.0, durees[j] - MIN_DUREE))
                durees[i] += manque
                durees[j] -= manque
        t = t0
        for b, du in zip(blocs, durees):
            cues.append(f"{n}\n{ts(t)} --> {ts(t + du)}\n{_deux_lignes(b)}\n")
            n += 1
            t += du
    Path(chemin).write_text("\n".join(cues), encoding="utf-8")


def chapitres_ffmetadata(script, debuts, duree, chemin):
    """Chapitres MP4 (un par scène) : chaque membre saute directement à son rôle depuis le lecteur."""
    def esc(s):
        return re.sub(r"([=;#\\\n])", r"\\\1", s)
    lignes = [";FFMETADATA1", f"title={esc(script['title'])}"]
    fins = debuts[1:] + [duree]
    for sc, t0, t1 in zip(script["scenes"], debuts, fins):
        lignes += ["[CHAPTER]", "TIMEBASE=1/1000", f"START={int(t0 * 1000)}", f"END={int(t1 * 1000)}",
                   f"title={esc(sc.get('chapitre') or sc['title'])}"]
    Path(chemin).write_text("\n".join(lignes) + "\n", encoding="utf-8")


def couper_sous_titres_par_defaut(mp4):
    """Le multiplexeur MP4 de ffmpeg réactive la piste malgré -disposition:s:0 0 : on éteint le bit « enabled » de son tkhd,
    pour que la piste soit proposée sans s'afficher d'office."""
    with open(mp4, "r+b") as f:
        tete = f.read(8_000_000)                          # moov en tête grâce à +faststart
        i = tete.find(b"hdlr" + bytes(8) + b"sbtl")       # hdlr de la piste de sous-titres
        j = tete.rfind(b"tkhd", 0, i)                     # tkhd de la même piste
        assert i > 0 and j > 0, "piste de sous-titres introuvable"
        f.seek(j + 7)                                     # octet de poids faible des flags
        f.write(bytes([tete[j + 7] & 0xFE]))
