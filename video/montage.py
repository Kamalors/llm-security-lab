# -*- coding: utf-8 -*-
"""Montage de la vidéo du labo LLM. Chaque phrase du script a sa voix et un seul visuel :
un extrait de capture (clip), une image figée (fige) ou un écran dessiné (carte : transition ou fiche).
Usage : python video/montage.py video/script.json video/travail [--apercu] [--voix-muette] [--captures DIR] [--sortie DIR]
L'extrait choisi n'est jamais accéléré ni coupé : si la voix est plus longue, sa dernière image reste figée."""
import argparse
import json
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

ICI = Path(__file__).resolve().parent
sys.path.insert(0, str(ICI))
import cartes  # noqa: E402
from commun import (FFMPEG, FPS, SR, chapitres_ffmetadata, couper_sous_titres_par_defaut, empreinte,  # noqa: E402
                    lire_wav, pour_affichage, prononcer, run, sous_titres, synthese_edge, vers_wav)

W, H = 1920, 1080
LEAD, BEAT_GAP, SCENE_GAP, TAIL = 1.0, 0.5, 1.2, 3.0   # silences (s) ; le changement de scène est un fondu par le fond sur tout SCENE_GAP
XF_BEAT, BADGE, FICHE_MIN = 0.35, 1.5, 20.0            # fondu entre deux visuels ; durée d'un badge de touche ; fiche lisible en pause
VISUELS = ("clip", "fige", "carte")
FOND = np.array(cartes.FOND, dtype=np.float32)
VF = f"scale={W}:{H}:force_original_aspect_ratio=decrease,pad={W}:{H}:(ow-iw)/2:(oh-ih)/2:color=0xF5F7FB"


# ------------------------------------------------------------------ script et chronologie
def charger(chemin: Path, captures: Path | None = None) -> dict:
    script = json.loads(Path(chemin).read_text(encoding="utf-8"))
    for sc in script["scenes"]:
        for bi, b in enumerate(sc["beats"], 1):
            ou = f"scène {sc['id']}, phrase {bi}"
            v = [k for k in VISUELS if k in b]
            if len(v) != 1 or not b.get("say", "").strip():
                raise ValueError(f"{ou} : il faut un texte « say » et un seul visuel (clip, fige ou carte), trouvé {v}")
            if "clip" in b and b["clip"]["a"] <= b["clip"]["de"]:
                raise ValueError(f"{ou} : extrait vide (a <= de)")
            if "carte" in b and b["carte"].get("type") not in ("transition", "fiche"):
                raise ValueError(f"{ou} : carte de type inconnu")
            src = (b.get("clip") or b.get("fige") or {}).get("source")
            if src and captures is not None and not (Path(captures) / f"{src}.mp4").exists():
                raise ValueError(f"{ou} : capture absente : {src}.mp4")
    return script


def duree_beat(voix: float, visuel: dict) -> float:
    if "clip" in visuel:
        return max(voix + BEAT_GAP, visuel["clip"]["a"] - visuel["clip"]["de"])
    if "carte" in visuel and visuel["carte"]["type"] == "fiche":
        return max(voix + BEAT_GAP, FICHE_MIN)
    return voix + BEAT_GAP


def chronologie(script: dict, voix: dict) -> dict:
    t, beats, debuts = LEAD, [], []
    for si, sc in enumerate(script["scenes"]):
        if si:
            t += SCENE_GAP
        debuts.append(t - SCENE_GAP if si else 0.0)
        for bi, b in enumerate(sc["beats"]):
            d = duree_beat(voix[(si, bi)], b)
            beats.append((si, bi, t, d))
            t += d
    return {"beats": beats, "debuts": debuts, "duree": t + TAIL}


# ------------------------------------------------------------------ images
def _libelle(touche):
    return f"Touche {touche}" if touche.isdigit() else touche


class _Lecteur:
    """Images d'un visuel, demandées dans l'ordre (k = numéro d'image depuis le début du visuel)."""

    def __init__(self, b, captures, badges):
        self.proc, self.fixe, self.badges = None, None, []
        if "carte" in b:
            c = dict(b["carte"])
            f = cartes.transition if c.pop("type") == "transition" else cartes.fiche
            self.fixe = np.asarray(f(**c).convert("RGB"))
        elif "fige" in b:
            g = b["fige"]
            raw = run_bytes([FFMPEG, "-loglevel", "error", "-ss", f"{g['t']:.3f}", "-i", str(captures / f"{g['source']}.mp4"),
                             "-frames:v", "1", "-vf", VF, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"])
            self.fixe = np.frombuffer(raw[:W * H * 3], np.uint8).reshape(H, W, 3)
        else:
            c = b["clip"]
            self.de, self.n = c["de"], max(1, round((c["a"] - c["de"]) * FPS))
            self.proc = subprocess.Popen([FFMPEG, "-loglevel", "error", "-ss", f"{c['de']:.3f}", "-i", str(captures / f"{c['source']}.mp4"),
                                          "-t", f"{c['a'] - c['de']:.3f}", "-vf", f"{VF},fps={FPS}", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                                         stdout=subprocess.PIPE)
            self.lus, self.derniere = 0, None
            touches = captures / f"{c['source']}.touches.json"
            if touches.exists():
                self.badges = [(k["t"], badges(_libelle(k["touche"]))) for k in json.loads(touches.read_text(encoding="utf-8"))
                               if c["de"] <= k["t"] <= c["a"]]

    def image(self, k):
        if self.fixe is not None:
            return self.fixe
        while self.lus <= min(k, self.n - 1):
            buf = self.proc.stdout.read(W * H * 3)
            if len(buf) < W * H * 3:
                self.n = self.lus   # capture plus courte que prévu : la dernière image reste
                break
            self.derniere = np.frombuffer(buf, np.uint8).reshape(H, W, 3)
            self.lus += 1
        if self.derniere is None:
            raise RuntimeError("extrait sans image lisible")
        img, t = self.derniere, self.de + min(k, self.n - 1) / FPS
        for t0, (rgb, alpha) in self.badges:
            if t0 <= t < t0 + BADGE:
                img = img.copy()
                h, w = alpha.shape
                y, x = H - 56 - h, W - 56 - w
                zone = img[y:y + h, x:x + w].astype(np.float32)
                img[y:y + h, x:x + w] = (zone * (1 - alpha[..., None]) + rgb * alpha[..., None]).astype(np.uint8)
        return img

    def fermer(self):
        if self.proc:
            self.proc.stdout.close()
            self.proc.kill()
            self.proc.wait()


def run_bytes(cmd):
    r = subprocess.run(cmd, capture_output=True)
    if r.returncode or not r.stdout:
        raise RuntimeError(f"ffmpeg : {r.stderr.decode(errors='replace')[-600:]}")
    return r.stdout


def _melange(a, b, u):
    a = FOND if a is None else a
    b = FOND if b is None else b
    return (np.asarray(a, np.float32) * (1 - u) + np.asarray(b, np.float32) * u).astype(np.uint8)


def _suite(p, b):
    """Même capture, extrait qui reprend là où le précédent s'arrête : on enchaîne sans fondu."""
    return "clip" in p and "clip" in b and p["clip"]["source"] == b["clip"]["source"] and abs(b["clip"]["de"] - p["clip"]["a"]) < 0.05


def images(script, chrono, captures):
    cache = {}

    def badges(lib):
        if lib not in cache:
            im = np.asarray(cartes.badge(lib), np.float32)
            cache[lib] = (im[..., :3], im[..., 3] / 255)
        return cache[lib]

    f, prec, b_prec, si_prec = 0, None, None, None
    for si, bi, t0, d in chrono["beats"]:
        b = script["scenes"][si]["beats"][bi]
        lect = _Lecteur(b, captures, badges)
        f0, f1 = round(t0 * FPS), round((t0 + d) * FPS)
        if f < f0:   # silence d'ouverture (fondu depuis le fond) ou changement de scène (fondu par le fond)
            premiere, nb = lect.image(0), f0 - f
            for j in range(nb):
                u = (j + 0.5) / nb
                yield _melange(None, premiere, u) if prec is None else \
                    _melange(prec, None, 2 * u) if u < 0.5 else _melange(None, premiere, 2 * u - 1)
            f = f0
        nxf = round(XF_BEAT * FPS) if si == si_prec and not _suite(b_prec, b) else 0
        for k in range(f1 - f):
            brut = lect.image(k)
            yield _melange(prec, brut, (k + 0.5) / nxf) if k < nxf else brut
        f, prec, b_prec, si_prec = f1, brut, b, si
        lect.fermer()
    total = round(chrono["duree"] * FPS)
    for j in range(total - f):   # fin : dernière image, puis fondu vers le fond sur la dernière seconde
        yield _melange(prec, None, min(1.0, max(0.0, (j - (total - f - FPS)) / FPS)))


# ------------------------------------------------------------------ voix
def voix(script, travail, muette, nom_voix, debit, ton):
    fichiers, taches = {}, []
    for d in ("audio", "wav"):
        (travail / d).mkdir(parents=True, exist_ok=True)
    for si, sc in enumerate(script["scenes"]):
        for bi, b in enumerate(sc["beats"]):
            lu = prononcer(b["say"])
            if muette:
                wav = travail / "wav" / f"muet_{len(b['say'])}.wav"
                if not wav.exists():
                    with wave.open(str(wav), "wb") as w:
                        w.setnchannels(1), w.setsampwidth(2), w.setframerate(SR)
                        w.writeframes(bytes(2 * int(SR * 0.065 * len(b["say"]))))
                fichiers[(si, bi)] = (lu, None, wav)
                continue
            h = empreinte(lu, nom_voix, debit, ton)
            mp3, wav = travail / "audio" / f"{h}.mp3", travail / "wav" / f"{h}.wav"
            fichiers[(si, bi)] = (lu, mp3, wav)
            if not mp3.exists() and (lu, mp3, debit) not in taches:
                taches.append((lu, mp3, debit))
    if taches:
        print(f"voix : {len(taches)} phrases à synthétiser")
        synthese_edge(taches, nom_voix, ton)
    for lu, mp3, wav in fichiers.values():
        if not wav.exists():
            vers_wav(mp3, wav)
    return fichiers, {k: len(lire_wav(v[2])) / SR for k, v in fichiers.items()}


def piste(chrono, fichiers, travail, normaliser):
    son = np.zeros(round(chrono["duree"] * FPS) * SR // FPS, dtype=np.int32)   # exactement la durée de l'image
    for si, bi, t0, _ in chrono["beats"]:
        s = lire_wav(fichiers[(si, bi)][2]).astype(np.int32)
        i0 = int(t0 * SR)
        son[i0:i0 + len(s)] += s[:max(0, len(son) - i0)]
    brut = travail / "voix_brute.wav"
    with wave.open(str(brut), "wb") as w:
        w.setnchannels(1), w.setsampwidth(2), w.setframerate(SR)
        w.writeframes(np.clip(son, -32768, 32767).astype(np.int16).tobytes())
    if not normaliser:   # voix muette : rien à normaliser
        return brut
    # EBU R128, -16 LUFS, crête -1,5 dB, en deux passes (comme RAO)
    mesure = run([FFMPEG, "-hide_banner", "-i", str(brut), "-af", "loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json", "-f", "null", "-"]).stderr
    m = json.loads(mesure[mesure.rfind("{"):mesure.rfind("}") + 1])
    norm = travail / "voix.wav"
    run([FFMPEG, "-y", "-i", str(brut), "-af",
         f"loudnorm=I=-16:TP=-1.5:LRA=11:measured_I={m['input_i']}:measured_TP={m['input_tp']}:"
         f"measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true",
         "-ar", str(SR), str(norm)])
    return norm


# ------------------------------------------------------------------ sorties
def hms(t):
    m, s = divmod(int(t), 60)
    return f"{m}:{s:02d}"


def ecrire_chapitres_md(script, debuts, duree, video, chemin):
    nom = [sc["chapitre"] for sc in script["scenes"]]
    lignes = [f"# {script['title']} : chapitres et transcription", "",
              f"Vidéo : [{video.name}]({video.name}) · durée : {hms(duree)}", "", "## Chapitres", ""]
    lignes += [f"- **{hms(t)}** {n}" for t, n in zip(debuts, nom)]
    lignes += ["", "## Transcription", ""]
    for t, sc in zip(debuts, script["scenes"]):
        lignes += [f"### {hms(t)} · {sc['chapitre']}", "", pour_affichage(" ".join(b["say"] for b in sc["beats"])), ""]
    Path(chemin).write_text("\n".join(lignes) + "\n", encoding="utf-8")


def encoder(frames, audio, srt, chap, sortie, apercu):
    cmd = [FFMPEG, "-y", "-hide_banner", "-loglevel", "error", "-nostats",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
           "-i", str(audio), "-i", str(srt), "-i", str(chap),
           "-map", "0:v", "-map", "1:a", "-map", "2:s", "-map_metadata", "3", "-map_chapters", "3",
           "-c:v", "libx264", "-preset", "veryfast" if apercu else "slow", "-crf", "26" if apercu else "20", "-pix_fmt", "yuv420p",
           "-c:a", "aac", "-b:a", "160k", "-c:s", "mov_text", "-metadata:s:a:0", "language=fre",
           "-metadata:s:s:0", "language=fre", "-disposition:s:0", "0", "-movflags", "+faststart", str(sortie)]
    journal = open(Path(sortie).with_suffix(".log"), "w+b")   # un tube non lu bloquerait ffmpeg
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stderr=journal)
    try:
        for im in frames:
            proc.stdin.write(np.ascontiguousarray(im).tobytes())
    finally:
        proc.stdin.close()
        code = proc.wait()
        journal.seek(0)
        err = journal.read().decode(errors="replace")
        journal.close()
    if code:
        raise RuntimeError(err[-2000:])
    couper_sous_titres_par_defaut(sortie)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("script")
    ap.add_argument("travail")
    ap.add_argument("--captures", default=str(ICI / "captures"))
    ap.add_argument("--sortie", default=str(ICI))
    ap.add_argument("--voix", default="fr-FR-VivienneMultilingualNeural")
    ap.add_argument("--debit", default="+0%")
    ap.add_argument("--ton", default="+0Hz")
    ap.add_argument("--apercu", action="store_true")
    ap.add_argument("--voix-muette", action="store_true")
    a = ap.parse_args(argv)
    captures, travail, sortie = Path(a.captures), Path(a.travail), Path(a.sortie)
    travail.mkdir(parents=True, exist_ok=True)
    script = charger(Path(a.script), captures)
    fichiers, durees = voix(script, travail, a.voix_muette, a.voix, a.debit, a.ton)
    chrono = chronologie(script, durees)
    debuts = [d + SCENE_GAP / 2 if si else 0.0 for si, d in enumerate(chrono["debuts"])]   # chapitre : quand sa scène apparaît
    print(f"durée : {chrono['duree'] / 60:.1f} min, {len(chrono['beats'])} phrases")
    audio = piste(chrono, fichiers, travail, not a.voix_muette)
    srt, chap = sortie / "sous-titres_fr.srt", travail / "chapitres.txt"   # autre nom que la vidéo : VLC ne le charge pas d'office
    sous_titres(script, [(si, bi, t0, durees[(si, bi)]) for si, bi, t0, _ in chrono["beats"]], srt)
    chapitres_ffmetadata(script, debuts, chrono["duree"], chap)
    (travail / "chronologie.json").write_text(json.dumps(
        {"duree": chrono["duree"],
         "scenes": [{"si": si, "id": sc["id"], "debut": round(t, 2), "chapitre": sc["chapitre"]} for si, (sc, t) in enumerate(zip(script["scenes"], debuts))],
         "beats": [{"si": si, "scene": script["scenes"][si]["id"], "beat": bi, "debut": round(t0, 2), "duree": round(durees[(si, bi)], 2),
                    "duree_visuel": round(d, 2), "texte": script["scenes"][si]["beats"][bi]["say"], "lu": fichiers[(si, bi)][0],
                    "audio": str(fichiers[(si, bi)][2])} for si, bi, t0, d in chrono["beats"]]},
        ensure_ascii=False, indent=1), encoding="utf-8")
    video = sortie / ("apercu.mp4" if a.apercu else "labo_llm_explique.mp4")
    print("encodage…")
    encoder(images(script, chrono, captures), audio, srt, chap, video, a.apercu)
    ecrire_chapitres_md(script, debuts, chrono["duree"], video, sortie / "chapitres.md")
    print("ok :", video, f"{video.stat().st_size / 1e6:.1f} Mo")


if __name__ == "__main__":
    main()
