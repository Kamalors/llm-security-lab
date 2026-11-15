# -*- coding: utf-8 -*-
"""Contrôle de prononciation : chaque phrase synthétisée est transcrite par Whisper et comparée au texte prévu
(partie --asr de mesures.py de la vidéo RAO). Usage : python video/prononciation.py video/travail
Écrit <travail>/prononciation.json et affiche les phrases dont la transcription s'écarte (similarité < 0,9)."""
import difflib
import json
import re
import subprocess
import sys
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from commun import FFMPEG, en_lettres  # noqa: E402


def norm(t):
    t = re.sub(r"\b[A-Z](?:-[A-Z])+\b", lambda m: m.group(0).replace("-", ""), t)  # « L-L-M » -> « LLM »
    t = en_lettres(t)
    t = unicodedata.normalize("NFKD", t.lower())
    t = "".join(c for c in t if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9 ]+", " ", t).split()


def audio_16k(path):
    import numpy as np
    raw = subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-i", str(path), "-ac", "1", "-ar", "16000",
                          "-f", "f32le", "-"], capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def main():
    travail = Path(sys.argv[1])
    beats = json.loads((travail / "chronologie.json").read_text(encoding="utf-8"))["beats"]
    from faster_whisper import WhisperModel
    modele = WhisperModel("medium", device="cpu", compute_type="int8")
    ecarts, vus = [], {}
    for b in beats:
        wav = Path(b["audio"])
        if wav not in vus:
            segs, _ = modele.transcribe(audio_16k(wav), language="fr", beam_size=5, vad_filter=False)
            vus[wav] = " ".join(s.text.strip() for s in segs)
        entendu = vus[wav]
        ratio = max(difflib.SequenceMatcher(None, norm(t), norm(entendu)).ratio() for t in {b["texte"], b["lu"]})
        b["entendu"], b["similarite"] = entendu, round(ratio, 3)
        if ratio < 0.9:
            ecarts.append({"scene": b["scene"], "beat": b["beat"], "prevu": b["texte"], "entendu": entendu, "similarite": round(ratio, 3)})
    ecarts.sort(key=lambda e: e["similarite"])
    (travail / "prononciation.json").write_text(json.dumps({"suspectes": ecarts, "phrases": beats}, ensure_ascii=False, indent=1), encoding="utf-8")
    for e in ecarts:
        print(f"{e['similarite']:.2f} {e['scene']}#{e['beat']}\n  prévu   : {e['prevu']}\n  entendu : {e['entendu']}")
    print(f"ok : {len(ecarts)} phrases suspectes sur {len(beats)}")


if __name__ == "__main__":
    main()
