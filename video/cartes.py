# -*- coding: utf-8 -*-
"""Les seuls écrans dessinés de la vidéo : transition de rôle, fiche récapitulative, badge de touche.
Couleurs et police de la fenêtre de démonstration (WPF, Segoe UI)."""
from PIL import Image, ImageDraw, ImageFont

W, H = 1920, 1080
POLICE = r"C:\Windows\Fonts\segoeui.ttf"
POLICE_GRAS = r"C:\Windows\Fonts\seguisb.ttf"
ENCRE, GRIS, FOND, REGLE = (16, 25, 54), (75, 86, 117), (245, 247, 251), (200, 208, 224)
SYS, EXT, BLANC = (29, 63, 203), (194, 65, 12), (255, 255, 255)
MARGE, HAUT, BAS = 110, 290, 1010


def _f(taille, gras=False):
    return ImageFont.truetype(POLICE_GRAS if gras else POLICE, taille)


def _lignes(texte, f, largeur):
    lignes, cur = [], ""
    for mot in texte.split():
        essai = f"{cur} {mot}".strip()
        if cur and f.getlength(essai) > largeur:
            lignes.append(cur)
            cur = mot
        else:
            cur = essai
    return lignes + ([cur] if cur else [])


def transition(numero: int, prenom: str, role: str) -> Image.Image:
    im = Image.new("RGB", (W, H), FOND)
    d = ImageDraw.Draw(im)
    d.text((MARGE, 300), f"{numero}", font=_f(260, True), fill=SYS, anchor="ls")
    d.text((MARGE + 10, 360), f"Rôle {numero} sur 4", font=_f(36), fill=GRIS, anchor="ls")
    d.line([(MARGE, 420), (MARGE + 160, 420)], fill=SYS, width=6)
    for txt, f, c, y in ((prenom, _f(140, True), ENCRE, 600), (role, _f(64), GRIS, 700)):
        if f.getlength(txt) > W - 2 * MARGE:
            raise ValueError(f"déborde : {txt}")
        d.text((MARGE, y), txt, font=f, fill=c, anchor="ls")
    return im


def _colonne(d, x, largeur, blocs):
    """blocs : (titre, couleur, éléments, puces, gras). Dessine si d n'est pas None ; renvoie la hauteur utilisée."""
    y = HAUT
    for titre, couleur, elements, puces, gras in blocs:
        if d:
            d.text((x, y), titre.upper(), font=_f(26, True), fill=couleur, anchor="lt")
        y += 50
        f = _f(34 if gras else 30, gras)
        for el in elements:
            retrait = 34 if puces else 0
            for i, l in enumerate(_lignes(el, f, largeur - retrait)):
                if d:
                    if puces and i == 0:
                        d.ellipse([x + 4, y + 16, x + 16, y + 28], fill=couleur)
                    d.text((x + retrait, y), l, font=f, fill=ENCRE, anchor="lt")
                y += 46 if gras else 42
            y += 12
        y += 34
    return y - 34


def fiche(prenom: str, role: str, message: str, maitriser: list[str], questions: list[str], relais: str) -> Image.Image:
    im = Image.new("RGB", (W, H), FOND)
    d = ImageDraw.Draw(im)
    d.text((MARGE, 120), f"Fiche · {prenom}", font=_f(72, True), fill=ENCRE, anchor="ls")
    d.text((MARGE, 185), role, font=_f(40), fill=GRIS, anchor="ls")
    d.line([(MARGE, 235), (W - MARGE, 235)], fill=REGLE, width=2)
    largeur = (W - 2 * MARGE - 90) // 2
    gauche = [("Message", SYS, [message], False, True), ("À maîtriser", SYS, maitriser, True, False)]
    droite = [("Questions probables du jury", EXT, questions, True, False), ("Relais", GRIS, [relais], False, False)]
    for x, blocs in ((MARGE, gauche), (MARGE + largeur + 90, droite)):
        if _colonne(None, x, largeur, blocs) > BAS:
            raise ValueError(f"déborde : fiche de {prenom}, colonne « {blocs[0][0]} »")
        _colonne(d, x, largeur, blocs)
    return im


def badge(touche: str) -> Image.Image:
    f = _f(40, True)
    w, h = int(f.getlength(touche)) + 56, 76
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=16, fill=ENCRE + (217,))
    d.text((w / 2, h / 2), touche, font=f, fill=BLANC, anchor="mm")
    return im
