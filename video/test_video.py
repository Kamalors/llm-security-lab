# -*- coding: utf-8 -*-
"""Tests de la vidéo : python video/test_video.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))


def leve(f, *a, contient=""):
    try:
        f(*a)
    except ValueError as e:
        assert contient in str(e), e
        return
    raise AssertionError(f"{f.__name__} aurait dû lever ValueError")


def test_cartes():
    import cartes
    from PIL import ImageFont
    assert cartes.transition(2, "Nolan", "Attaques sur Ollama").size == (1920, 1080)
    assert cartes.fiche("Fatih", "Gandalf et OWASP", "m", ["a"] * 4, ["q ?"] * 4, "Valentin va…").size == (1920, 1080)
    leve(cartes.fiche, "Fatih", "r", "m", ["une ligne à maîtriser"] * 30, ["q ?"], "relais", contient="déborde")
    assert cartes.badge("F5").mode == "RGBA"
    assert cartes.badge("Touche 3").size[0] > cartes.badge("F5").size[0]
    f = ImageFont.truetype(cartes.POLICE, 40)
    for c in "é’«»":
        assert f.getmask(c).getbbox(), f"glyphe absent : {c}"


CLIP = {"clip": {"source": "x", "de": 2, "a": 10}}
FICHE = {"carte": {"type": "fiche", "prenom": "Fatih", "role": "r", "message": "m", "maitriser": ["a"], "questions": ["q ?"], "relais": "v"}}


def test_duree_beat():
    from montage import duree_beat
    assert duree_beat(3.0, CLIP) == 8.0
    assert duree_beat(9.0, CLIP) == 9.5
    assert duree_beat(4.0, FICHE) == 20.0
    assert duree_beat(4.0, {"fige": {"source": "x", "t": 1}}) == 4.5


def test_chronologie():
    import montage as m
    fige = {"fige": {"source": "x", "t": 1}}
    script = {"scenes": [{"id": "a", "chapitre": "A", "beats": [{"say": "un", **fige}, {"say": "deux", **fige}]},
                         {"id": "b", "chapitre": "B", "beats": [{"say": "trois", **fige}]}]}
    c = m.chronologie(script, {(0, 0): 2.0, (0, 1): 3.0, (1, 0): 4.0})
    somme = 2.5 + 3.5 + 4.5
    assert abs(c["duree"] - (m.LEAD + somme + m.SCENE_GAP + m.TAIL)) < 1e-9, c
    debut3 = c["beats"][2][2]
    assert abs(c["debuts"][1] - (debut3 - m.SCENE_GAP)) < 1e-9, c
    assert c["debuts"][0] == 0.0


def test_fondu_vers_le_fond():
    import numpy as np, warnings, montage
    img = np.zeros((4, 4, 3), np.uint8)
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        fin = montage._melange(img, None, 1.0)
        milieu = montage._melange(img, None, 0.5)
    assert (fin == np.array(montage.cartes.FOND, np.uint8)).all(), fin[0, 0]
    assert (milieu == (np.array(montage.cartes.FOND) * 0.5).astype(np.uint8)).all(), milieu[0, 0]


def test_charger_refuse():
    import json, tempfile, montage
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "s.json"
        p.write_text(json.dumps({"title": "t", "scenes": [{"id": "a", "chapitre": "A", "beats": [{"say": "sans visuel"}]}]}), encoding="utf-8")
        leve(montage.charger, p, contient="scène")
        p.write_text(json.dumps({"title": "t", "scenes": [{"id": "a", "chapitre": "A", "beats": [{"say": "x", **CLIP}]}]}), encoding="utf-8")
        leve(montage.charger, p, Path(d), contient="scène")   # source absente du dossier des captures


def test_bout_en_bout():
    import json, subprocess, tempfile, montage
    from commun import FFMPEG
    with tempfile.TemporaryDirectory() as d:
        d = Path(d); cap = d / "captures"; cap.mkdir()
        for nom in ("a", "b"):
            subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=30",
                            "-t", "6", "-pix_fmt", "yuv420p", str(cap / f"{nom}.mp4")], check=True)
        (cap / "a.touches.json").write_text('[{"touche": "1", "t": 1.0, "fin": 3.0}]', encoding="utf-8")
        script = {"title": "Essai", "scenes": [
            {"id": "s1", "chapitre": "Un", "beats": [
                {"say": "Une phrase sur la capture.", "clip": {"source": "a", "de": 0.5, "a": 4.0}},
                {"say": "Une image figée.", "fige": {"source": "b", "t": 2.0}}]},
            {"id": "s2", "chapitre": "Deux", "beats": [
                {"say": "Transition.", "carte": {"type": "transition", "numero": 1, "prenom": "Maxime", "role": "Problématique"}},
                {"say": "Fiche.", **FICHE}]}]}
        (d / "script.json").write_text(json.dumps(script, ensure_ascii=False), encoding="utf-8")
        montage.main([str(d / "script.json"), str(d / "travail"), "--captures", str(cap), "--sortie", str(d), "--voix-muette", "--apercu"])
        mp4 = d / "apercu.mp4"
        info = subprocess.run([FFMPEG, "-hide_banner", "-i", str(mp4)], capture_output=True, text=True, encoding="utf-8", errors="replace").stderr
        assert "1920x1080" in info and "30 fps" in info, info
        assert "Audio: aac" in info and "mov_text" in info, info
        assert info.count("Chapter #") == 2, info
        chrono = json.loads((d / "travail" / "chronologie.json").read_text(encoding="utf-8"))
        r = subprocess.run([FFMPEG, "-i", str(mp4), "-map", "0:v", "-f", "null", "-"], capture_output=True, text=True, encoding="utf-8", errors="replace").stderr
        import re
        h, mi, s = re.findall(r"time=(\d+):(\d+):([\d.]+)", r)[-1]
        assert abs(int(h) * 3600 + int(mi) * 60 + float(s) - chrono["duree"]) < 0.1, (r[-300:], chrono["duree"])
        assert (d / "chapitres.md").exists() and (d / "sous-titres_fr.srt").exists()


if __name__ == "__main__":
    for nom, f in list(globals().items()):
        if nom.startswith("test_"):
            f()
            print("ok", nom)
    print("ok")
