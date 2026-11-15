# Vidéo de préparation de la soutenance LLM : conception

Date : 15/11/2026. Statut : validé par l'utilisateur le 15/11/2026.

## Intention

Une vidéo pour les quatre membres du groupe qui présentent le labo « Pourquoi l'injection de prompt reste-t-elle si difficile à corriger ? ». Elle leur explique le projet et donne à chacun sa fiche de rôle (ce qu'il présente, ce qu'il doit maîtriser, les questions probables du jury, le passage de relais). Même usage que la vidéo du projet RAO (`Documents\Sécurité des infrastructure\presentation\sources\video\`), que les quatre connaissent déjà.

Différence voulue avec RAO : ici on **filme le vrai outil** (fenêtre de démonstration et IHM web), au lieu d'écrans dessinés. Chacun voit exactement ce sur quoi il cliquera le jour de la soutenance.

## Équipe et rôles (ordre de passage)

| # | Qui | Rôle | Ce qu'il présente | Écrans filmés |
|---|---|---|---|---|
| 1 | Maxime | Problématique et labo | La question, injection SQL contre injection de prompt, le serveur et son isolement. Ouvre et conclut | IHM écran 1 ; fenêtre « Vérifier le labo » (schéma PC → Proxmox → conteneur → Ollama → API) |
| 2 | Nolan | Attaques sur Ollama | Les 8 attaques, la démo en direct, comment le verdict est calculé | Fenêtre : attaques 1 à 8 ; IHM écran 2 avec « Voir comme le modèle » |
| 3 | Fatih | Gandalf et OWASP | Défenses par niveau de Gandalf, classement dans le Top 10 LLM 2025 | IHM écrans 3 et 4 |
| 4 | Valentin | Veille et entreprise | Les quatre raisons, les mesures, les sources, « Et dans mon entreprise ? » | IHM écran 5 |

Répartition proposée par Claude. Invité à la corriger, l'utilisateur a donné les prénoms dans cet ordre sans changer les rôles.

## Objectifs

- Chacun comprend le projet entier et sait ce qu'il dit, dans quel ordre, et à qui il passe la parole.
- Chacun reconnaît à l'écran l'outil qu'il manipulera (touches, boutons, ce qui change à l'écran).
- Voix naturelle en français, transitions fluides, sous-titres, chapitres MP4 pour sauter à son rôle.

## Non-objectifs

- Pas une vidéo à projeter devant le jury.
- Pas de captation de l'interface Proxmox (elle demande le mot de passe de l'utilisateur) ni du site Gandalf (les essais Gandalf sont le travail noté du groupe).
- Pas de modification de la fenêtre de démo ni de l'IHM pour les besoins du tournage (rien de cosmétique). Exception : un vrai bug découvert pendant le tournage est corrigé et redéployé avec `bash deploy/push-lab.sh`, puis signalé à l'utilisateur (sinon il casserait aussi la soutenance).

## Anti-objectifs (échec même si la vidéo « marche »)

- **Un résultat inventé ou retouché.** Tout ce qui s'affiche vient d'un vrai essai sur le vrai modèle. La voix ne dit que ce que les captures montrent.
- **Laisser des traces dans les essais du groupe.** Après le tournage, `data/` dans le conteneur doit être revenu à son état d'avant (aucune session de tournage, notes intactes).
- **Écrire à la place du groupe** le texte « Et dans mon entreprise ? » ou des essais Gandalf. La vidéo dit ce que Valentin et Fatih doivent préparer, sans le remplir.
- **Exposer un jeton.** Le jeton du labo ne doit apparaître ni à l'écran, ni dans une URL capturée, ni dans les fichiers du projet.

## Décisions prises avec l'utilisateur

1. Vidéo pour les quatre membres : le projet + une fiche par rôle.
2. Fabrication : captation du vrai outil (choisie contre le moteur d'écrans dessinés de RAO).
3. Les 8 attaques sont jouées pendant le tournage, sur le vrai modèle. Ces essais sont ensuite rangés hors de `data/`, comme ceux du 11/11.
4. `data/` contient déjà 12 essais du 11/11 (10 h 20 à 10 h 40, origine non confirmée, traités comme ceux du groupe). Ils sont mis de côté pendant le tournage puis remis à l'identique, empreintes vérifiées avant et après.

## Approches envisagées

| Approche | Pour | Contre | Retenue |
|---|---|---|---|
| Écrans dessinés (moteur RAO) | Format connu, rendu maîtrisé, schéma « un seul canal » construit au rythme de la voix | On ne voit pas l'outil réel | Non |
| **Captation du vrai outil** | On voit ce qu'on manipulera le jour J ; teste au passage l'IHM sur le serveur | Plus fragile à produire ; le PC est piloté pendant le tournage de la fenêtre | **Oui, choix de l'utilisateur** |
| Captation pour Nolan et Fatih seulement, dessin ailleurs | Compromis | Deux styles dans la même vidéo | Non |

## Structure proposée (environ 12 minutes)

Proposition de Claude : le projet est expliqué **rôle par rôle**, puisque chaque rôle correspond à une partie de l'outil, dans l'ordre de l'IHM. C'est plus court que « le projet, puis les rôles » (RAO), qui obligerait à montrer deux fois les mêmes écrans. Tout le monde regarde la vidéo entière, donc chacun voit aussi le projet entier.

1. **Ouverture** (≈ 40 s) : à quoi sert la vidéo, la question, les quatre rôles et l'ordre de passage.
2. **Maxime, problématique et labo** (≈ 2 min 30) : écran 1 (deux canaux contre un seul), puis la fenêtre qui vérifie le labo maillon par maillon. Fiche : message, à maîtriser, questions probables, relais vers Nolan.
3. **Nolan, attaques sur Ollama** (≈ 3 min 30) : les 8 attaques jouées dans la fenêtre (une ou deux montrées en entier, les autres resserrées), verdicts, puis l'écran 2 en « Voir comme le modèle ». Fiche, relais vers Fatih.
4. **Fatih, Gandalf et OWASP** (≈ 2 min 30) : écran 3 (défenses par niveau ; lignes d'essais vides, à remplir par le groupe), écran 4 (les 8 essais du tournage classés). Fiche, relais vers Valentin.
5. **Valentin, veille et entreprise** (≈ 2 min) : écran 5, les quatre raisons, les mesures, les sources, le champ « Et dans mon entreprise ? » vide. Fiche, relais vers Maxime pour la conclusion.
6. **Conclusion** (≈ 30 s) : l'enchaînement, ce qui reste à faire avant la soutenance (vos propres essais Ollama et Gandalf, le texte entreprise, une répétition chronométrée).

Éléments dessinés (choix de Claude, l'utilisateur n'a pas tranché) : un écran de transition au début de chaque rôle (prénom, rôle, numéro de passage), un **écran de fiche récapitulative d'environ 20 s à la fin de chaque rôle** (message, à maîtriser, questions probables, relais), lisible en pause comme les fiches de RAO, et un petit badge « Touche 3 » / « F5 » à chaque touche envoyée à la fenêtre, pour apprendre les touches. Tout le reste est filmé.

## Contraintes

### Tournage

- **Fenêtre de démo** (`automation\Demo_LLM.cmd`, WPF) : lancée sur le PC de l'utilisateur, pilotée au clavier (F5, touches 1 à 8, gérées par la fenêtre elle-même). Écran 1920×1080 à 125 % : la fenêtre (1480×900 logiques) ne tient pas, elle est donc filmée agrandie en plein écran. Curseur masqué. **L'utilisateur ne touche pas au PC pendant ce tournage** (≈ 10 min) : Claude demande le feu vert juste avant.
- **IHM web** : filmée dans un navigateur sans fenêtre (Edge est installé, pas Chrome), en 1920×1080, à travers le tunnel SSH vers le conteneur. Connexion par le code à usage unique (`POST /api/handoff`), jamais par un jeton dans l'URL capturée. Thème clair.
- **Ne rien taper dans les champs enregistrés automatiquement** de l'IHM (texte entreprise, essais Gandalf) : ils écrivent sur le serveur.
- Les attaques sont jouées avec les messages prêts du scénario (ceux de la fenêtre), comme le fera Nolan.
- **Écran 2 de l'IHM** : il ne rouvre pas un essai passé (choisir un scénario repart d'un essai vide, `choose()` dans `app.js`). Pour montrer « Voir comme le modèle » avec un vrai échange, une attaque de plus est jouée depuis l'IHM (avec ses messages prêts, de préférence une attaque compromise dans la fenêtre). L'écran 4 compte donc 9 essais, et la voix le dit.
- **Prise ratée** (notification Windows, essai incomplet, erreur) : on remet le labo à l'état vide (sessions de la prise archivées, `llm-lab` redémarré) avant de refaire la prise, pour que les écrans 4 et 5 ne montrent que la prise gardée.

### Avant et après le tournage

- Avant : relever `/opt/llm-security-lab/data/` (liste et SHA-256 de chaque fichier ; `notes.json` n'existe pas au 15/11). Déplacer les 12 essais existants vers `/opt/llm-security-lab/mis-de-cote-2026-11-15/`, redémarrer `llm-lab` (les sessions sont chargées en mémoire au démarrage) : le labo filmé part vide.
- Après : déplacer les sessions du tournage (toutes les prises) vers `/opt/llm-security-lab/tournage-2026-11-15/`, remettre les 12 essais dans `data/`, redémarrer `llm-lab`, vérifier que la liste et les empreintes sont identiques à celles d'avant. Si un `notes.json` est apparu pendant le tournage, c'est une erreur : le retirer.

### Montage

- **La voix est écrite après le tournage**, à partir de ce que les captures montrent réellement (le modèle ne répond pas toujours pareil : le nombre d'attaques réussies peut différer des 6 sur 8 du 11/11).
- On coupe, on fige ou on resserre les attentes du modèle. On ne retouche jamais ce que l'outil affiche (verdicts, réponses, durées). Une attente resserrée reste lisible comme telle : la fenêtre affiche la vraie durée de chaque réponse.
- Les essais filmés sont présentés à la voix comme des essais de démonstration du tournage, à refaire par le groupe.

### Voix, sous-titres, chapitres

- Voix `fr-FR-RemyMultilingualNeural` (edge-tts, déjà installé), comme RAO. Le texte de la narration passe par le service de Microsoft, comme pour RAO. Rien de personnel dans le texte au-delà des quatre prénoms.
- Sous-titres français (piste désactivée par défaut + fichier SRT), chapitres MP4 (un par rôle).
- Prononciation vérifiée par transcription Whisper (`faster-whisper` installé), avec un lexique pour les termes mal lus (Ollama, Qwen, OWASP, ChatML, base64, Lakera…).

### Exactitude

Chaque affirmation de la narration est vérifiée contre l'état actuel du projet (README, `app/scenarios.mjs`, `app/public/index.html`, `verifier/verify.mjs`) et contre les captures. `docs/presentation.md` est obsolète (Hermes, Codex, VM) : ses « questions fréquentes » ne sont reprises qu'après vérification. Faits établis : modèle `qwen2.5:1.5b` sur CPU (≈ 19 jetons/s), conteneur 401 sur un bridge dédié sans sortie Internet, verdict déterministe sans LLM, « a tenu » ne veut pas dire « robuste », niveaux 7 et 8 de Gandalf en pause le 10/11.

## Ce qui se réutilise du projet RAO

Dans `Documents\Sécurité des infrastructure\presentation\sources\video\build.py` : synthèse edge-tts avec cache par empreinte de phrase, conversion et découpe des silences, sous-titres (découpe, nombres en chiffres, insécables), chapitres ffmetadata, correctif du bit « enabled » de la piste de sous-titres, contrôle Whisper (`mesures.py`). Le compositeur d'images (`image_a`, `ecrans.py`) ne s'applique pas : il faut un montage de clips vidéo calés sur la voix. Le moteur RAO reste intact : on copie ce qui sert, on ne le modifie pas.

## Livrables

Dans le projet, dossier `video/` :
- `labo_llm_explique.mp4` (1920×1080, 30 i/s, H.264 + AAC, sous-titres et chapitres intégrés), `sous-titres_fr.srt` ;
- `chapitres.md` : chapitres horodatés et transcription ;
- les sources pour reconstruire : script de narration, captures brutes, outil de montage.

## Laissé au constructeur

- L'outil de captation (ffmpeg `gdigrab` d'imageio-ffmpeg pour la fenêtre, protocole DevTools d'Edge pour l'IHM, ou mieux), et l'envoi des touches à la fenêtre.
- Le format du script de narration et la façon de caler chaque phrase sur un passage de capture.
- Le style des écrans de transition (sobre, cohérent avec les couleurs de l'outil : bleu des règles, orange de l'attaquant).
- Quelles attaques sont montrées en entier et lesquelles sont resserrées, selon ce que le tournage donne.
- Le texte des fiches de rôle, à partir des sources ci-dessus, relu pour l'exactitude.
