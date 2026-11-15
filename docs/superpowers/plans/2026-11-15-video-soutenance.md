# Vidéo de préparation de la soutenance LLM : plan de fabrication

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** une vidéo d'environ 12 minutes, avec voix naturelle et transitions, qui explique le labo LLM aux quatre membres du groupe (Maxime, Nolan, Fatih, Valentin) et donne à chacun sa fiche de rôle. Elle est filmée sur le vrai outil.

**Architecture:**
- Deux outils de captation :
  - la fenêtre WPF est filmée par ffmpeg `gdigrab` et pilotée au clavier ;
  - l'IHM web est filmée dans Edge sans fenêtre, par le protocole DevTools, depuis Node 24 sans dépendance.
- Un script shell gère l'état du labo dans le conteneur : il met de côté, archive et restaure les essais, avec contrôle des empreintes.
- Un moteur de montage Python lit `video/script.json`. Chaque phrase a sa voix et son visuel :
  - un extrait de capture ;
  - une image figée ;
  - un écran dessiné.
- Le moteur cale chaque visuel sur la voix, enchaîne les fondus, puis ajoute les sous-titres et les chapitres. La voix, les sous-titres et les chapitres sont copiés du moteur RAO.

**Tech Stack:** Python 3.13 (Pillow 12, numpy, imageio-ffmpeg, edge-tts 7.3, faster-whisper), Node 24 (WebSocket natif), Windows PowerShell 5.1, Edge, bash dans le conteneur.

**Spec:** `docs/superpowers/specs/2026-11-15-video-soutenance-design.md`

Le projet n'est pas un dépôt git : pas d'étape de commit. Toutes les commandes se lancent depuis la racine du projet `C:\Users\vael3\Projects\llm-security-lab`.

## Global Constraints

- Sortie : `video/labo_llm_explique.mp4`, 1920×1080, 30 i/s, H.264 + AAC, piste de sous-titres français désactivée par défaut, un chapitre MP4 par scène. Fichiers à côté : `video/sous-titres_fr.srt` et `video/chapitres.md` (chapitres horodatés et transcription).
- Voix : `fr-FR-RemyMultilingualNeural` via edge-tts. Seuls les quatre prénoms sont des données personnelles dans le texte.
- Tout le texte affiché ou dit est en français.
- Aucun résultat inventé ou retouché : la voix ne dit que ce que les captures montrent. Les essais filmés sont présentés comme des essais de démonstration du tournage, à refaire par le groupe.
- Le jeton du labo n'apparaît jamais à l'écran, dans une URL capturée, dans un journal ni dans un fichier. Il est lu par SSH et reste en mémoire. L'IHM se connecte par le code à usage unique de `POST /api/handoff`.
- Ne jamais écrire dans `#entreprise` ni dans les champs Gandalf (`#levels`) de l'IHM : ils s'enregistrent sur le serveur.
- `data/` du conteneur : les 12 essais existants vont dans `/opt/llm-security-lab/mis-de-cote-2026-11-15/` pendant le tournage, puis sont remis avec des SHA-256 identiques. Toutes les prises du tournage vont dans `/opt/llm-security-lab/tournage-2026-11-15/<prise>/`. `llm-lab` est redémarré après chaque déplacement.
- L'outil ne change pas pour le tournage. Un vrai bug est corrigé, redéployé avec `bash deploy/push-lab.sh` et signalé à l'utilisateur.
- Fichiers `.ps1` en UTF-8 avec BOM (Windows PowerShell 5.1).
- Navigateur : Edge (`C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`), thème clair de l'IHM.
- Écran : 1920×1080 physiques à 125 %. La fenêtre de démo est agrandie, le curseur masqué.
- Le tournage de la fenêtre pilote le PC. Il ne démarre qu'après le feu vert explicite de l'utilisateur, donné juste avant.
- Les éléments dessinés se limitent à trois :
  - un écran de transition au début de chaque rôle ;
  - un écran de fiche récapitulative d'au moins 20 s à la fin de chaque rôle ;
  - un badge de touche.
- Moteur RAO (`C:\Users\vael3\Documents\Sécurité des infrastructure\presentation\sources\video\`) : on le copie, on ne le modifie jamais.

## Review Focus

1. **Une notification Windows ou une autre fenêtre passe devant la fenêtre filmée.** Comme `gdigrab` filme une zone de l'écran, elle apparaîtrait dans la vidéo. Il faut activer « Ne pas déranger » avant la prise (Task 5) et relire la planche contact de chaque prise. Si l'intrusion tombe dans un passage utile, on refait la prise.
2. **Le titre accentué de la fenêtre** (« Labo sécurité LLM, démonstration en direct ») peut faire échouer `gdigrab -i title=…`. On filme donc la zone de bureau du rectangle de la fenêtre, en pixels physiques. L'essai de la Task 3 vérifie la taille de sortie.
3. **Une attaque finit « Essai incomplet » ou en erreur** (502, délai dépassé, modèle froid au premier appel). Le bilan d'après-prise (`etat-labo.sh bilan`) le révèle. Dans ce cas, on archive la prise et on la refait, sans jamais monter une prise incomplète. La Task 2 teste `bilan` sur des sessions factices.
4. **Une action de l'IHM vise un champ enregistré** (`#entreprise`, `#levels …`). `verifierActions` le refuse avant le lancement d'Edge (test dans la Task 4).
5. **Le jeton fuit dans un fichier produit** (journal, JSON d'actions, capture). Après le tournage, on lit le jeton par SSH et on cherche sa présence dans `video/`, sans jamais l'afficher. Ce contrôle a lieu dans la Task 5 et à nouveau dans la Task 8.

---

### Task 1: Écrans dessinés (transition, fiche, badge)

**Files:**
- Create: `video/cartes.py`
- Test: `video/test_video.py` (un seul fichier de tests pour `video/`, lancé par `python video/test_video.py`, avec de simples `assert`, comme `test_build.py` de RAO)

**Interfaces:**
- Produces:
  - `transition(numero: int, prenom: str, role: str) -> PIL.Image.Image` (RGB, 1920×1080) ;
  - `fiche(prenom: str, role: str, message: str, maitriser: list[str], questions: list[str], relais: str) -> PIL.Image.Image` (RGB, 1920×1080) ;
  - `badge(touche: str) -> PIL.Image.Image` (RGBA, dimensions selon le texte). Toutes lèvent `ValueError("déborde : …")` si un texte ne tient pas dans la zone prévue.
- Couleurs de l'outil : encre `#101936`, texte secondaire `#4B5675`, fond `#F5F7FB`, règles serveur `#1D3FCB`, attaquant `#C2410C`.
- Polices : `C:\Windows\Fonts\segoeui.ttf` et `seguisb.ttf`, celles de la fenêtre WPF.

- [ ] **Step 1: Écrire les tests qui échouent** : `test_cartes()` dans `video/test_video.py`. Assertions :
  - `transition(2, "Nolan", "Attaques sur Ollama").size == (1920, 1080)` ;
  - `fiche("Fatih", "Gandalf et OWASP", "m", ["a"]*4, ["q ?"]*4, "Valentin va…")` donne une image de taille `(1920, 1080)` ;
  - `fiche` avec 30 lignes dans `maitriser` lève `ValueError` ;
  - `badge("F5").mode == "RGBA"` et `badge("Touche 3").size[0] > badge("F5").size[0]` ;
  - la chaîne `"é’«»"` se dessine (le masque de chaque glyphe avec `ImageFont.getmask` n'est pas vide).
- [ ] **Step 2: Lancer** `python video/test_video.py`. Attendu : échec, `cartes` introuvable.
- [ ] **Step 3: Écrire `video/cartes.py`.** Mise en page sobre :
  - transition : un grand numéro de passage, le prénom, le rôle ;
  - fiche : quatre blocs lisibles en pause (Message, À maîtriser, Questions probables du jury, Relais), avec un texte courant d'au moins 30 px ;
  - badge : une touche arrondie, avec un fond `#101936` à 85 %.
- [ ] **Step 4: Relancer** `python video/test_video.py`. Attendu : `ok`. Ouvrir une fiche enregistrée en PNG dans le dossier de travail de la session pour juger la lisibilité.

### Task 2: État du labo dans le conteneur

**Files:**
- Create: `video/tournage/etat-labo.sh`
- Test: `video/tournage/test_etat_labo.sh`, lancé localement dans Git Bash.

**Interfaces:**
- Produces: `etat-labo.sh <commande>`, lancé en root dans le conteneur avec `ssh -F automation/ssh_config llm-lab 'bash -s' -- <commande> < video/tournage/etat-labo.sh`. Variables : `LAB_DIR` (par défaut `/opt/llm-security-lab`) et `NO_RESTART=1` pour les tests (dans ce cas, pas de `systemctl restart llm-lab`). Les sessions sont les fichiers `data/[0-9a-f]{32}.json`.
  - `mettre-de-cote` : refuse si `mis-de-cote-2026-11-15/` contient déjà une session. Sinon, écrit `mis-de-cote-2026-11-15/MANIFEST.sha256` (empreintes calculées dans `data/`), y déplace les sessions, puis redémarre.
  - `archiver <prise>` : déplace les sessions de `data/` vers `tournage-2026-11-15/<prise>/` (refuse si ce dossier existe déjà), puis redémarre.
  - `restaurer` : refuse si `data/` contient une session (prise non archivée). Sinon, remet les sessions mises de côté, vérifie `sha256sum -c MANIFEST.sha256` depuis `data/`, refuse s'il existe un `data/notes.json` qui n'était pas là avant, puis redémarre. Code de sortie non nul en cas d'écart.
  - `bilan` : affiche une ligne par session de l'API (`<scénario> <verdict> <nombre de tours>`), dans l'ordre de création. Il interroge `http://127.0.0.1:8080/api/sessions` avec `node -e` et `fetch`, avec le jeton lu dans `$LAB_DIR/.env`, sans l'afficher.

- [ ] **Step 1: Écrire `test_etat_labo.sh`.** Le test crée un `LAB_DIR` temporaire avec 3 fichiers de session factices, puis vérifie, dans l'ordre :
  1. `mettre-de-cote` : `data/` est vide et le manifeste a 3 lignes ;
  2. on crée 2 sessions « tournage », puis `restaurer` sort en code non nul ;
  3. `archiver prise1` : 2 fichiers dans `tournage-2026-11-15/prise1/` ;
  4. `archiver prise1` une deuxième fois sort en code non nul ;
  5. `restaurer` : 3 fichiers revenus, empreintes identiques ;
  6. un second `mettre-de-cote` alors que le dossier mis de côté n'est pas vide sort en code non nul (cas recréé à part).
- [ ] **Step 2: Lancer** `bash video/tournage/test_etat_labo.sh`. Attendu : échec, script absent.
- [ ] **Step 3: Écrire `etat-labo.sh`** (`set -euo pipefail`, `mv` qui préserve propriétaire et droits `600`).
- [ ] **Step 4: Relancer le test.** Attendu : `ok`.
- [ ] **Step 5: Lancer `bilan` en lecture seule sur le vrai conteneur.** Attendu : 12 lignes, celles des essais du 11/11.

### Task 3: Captation de la fenêtre de démo

**Files:**
- Create: `video/tournage/fenetre.ps1` (UTF-8 avec BOM)

**Interfaces:**
- Produces: `powershell -File video/tournage/fenetre.ps1 -Sortie video/captures/<nom> [-Touches 'F5','1',…,'8']`. Écrit `<nom>.mp4` (1920×1080 au besoin après mise à l'échelle, 30 i/s, libx264 `-preset ultrafast -crf 16`) et `<nom>.touches.json` : `[{"touche":"F5","t":3.42,"fin":9.80}, …]`, où `t` est l'envoi et `fin` le retour au repos, en secondes depuis le début de l'enregistrement.
- Déroulé :
  1. `SetProcessDPIAware` ;
  2. lancer `automation\Demo_LLM.cmd`, attendre la fenêtre par son processus, puis l'agrandir avec `ShowWindow` (`SW_MAXIMIZE`) ;
  3. prendre son rectangle en pixels physiques ;
  4. ffmpeg d'imageio-ffmpeg : `-f gdigrab -framerate 30 -draw_mouse 0 -offset_x -offset_y -video_size -i desktop` (jamais `title=`) ;
  5. envoyer chaque touche avec `WScript.Shell` (`AppActivate`, puis `SendKeys`, F5 s'écrivant `{F5}`) ;
  6. attendre le repos, c'est-à-dire le bouton `BtnCheck` (« Vérifier le labo ») de nouveau activé, lu par UI Automation (240 s au plus par touche, sinon arrêt avec message), puis 4 s pour que le verdict reste à l'écran ;
  7. arrêter ffmpeg proprement (`q` sur son entrée standard), puis fermer la fenêtre, ce qui ferme aussi son tunnel.

- [ ] **Step 1: Écrire `fenetre.ps1`.**
- [ ] **Step 2: Essai sans attaque.** Ce test ne crée aucune session, mais il pilote le PC une trentaine de secondes : demander d'abord le feu vert à l'utilisateur. Lancer `-Sortie video/captures/essai-fenetre -Touches 'F5'`. Attendus :
  - `ffprobe` donne 1920×1080 et 30 i/s ;
  - le JSON contient une entrée F5 avec `fin > t` ;
  - une image extraite à `fin + 1` montre « Le labo est prêt ».
- [ ] **Step 3: Vérifier sur le serveur** que `etat-labo.sh bilan` affiche toujours 12 lignes.

### Task 4: Captation de l'IHM web

**Files:**
- Create: `video/tournage/ihm.mjs`, `video/tournage/ihm.ps1` (UTF-8 avec BOM), `video/tournage/ihm-essai.json`, `video/tournage/ihm-tournage.json`
- Test: `video/tournage/test_ihm.mjs` (`node --test`)

**Interfaces:**
- Produces:
  - `ihm.mjs`, qui exporte `verifierActions(actions: object[]): void`. Cette fonction lève une erreur pour toute action dont le sélecteur touche `#entreprise` ou `#levels`, et pour tout type d'action inconnu.
  - Le CLI `node video/tournage/ihm.mjs <actions.json> <sortie>`. L'URL arrive par la variable `IHM_URL`, jamais en argument. Il écrit `<sortie>.mp4` (1920×1080, 30 i/s) et `<sortie>.actions.json` (`[{"action":…, "t":…}]`).
  - Les actions : `{"attendre":ms}`, `{"touche":"ArrowRight"}`, `{"clic":"<css>"}`, `{"attendre_selecteur":"<css>","max":ms}`, `{"defiler":"<css>"}`.
  - `ihm.ps1 -Actions <json> -Sortie <chemin>` :
    1. ouvre `ssh -F automation/ssh_config -N -L 18080:127.0.0.1:8080 llm-lab` (pas 8080, réservé à la fenêtre) ;
    2. lit le jeton par SSH en mémoire (même commande `sed` que `demo_llm.ps1`), demande un code par `POST /api/handoff` ;
    3. lance `ihm.mjs` avec `IHM_URL=http://127.0.0.1:18080/#code=<code>` ;
    4. ferme le tunnel quoi qu'il arrive (`finally`).
- Fonctionnement de `ihm.mjs` :
  - Edge `--headless=new --remote-debugging-port=0 --user-data-dir=<dossier temporaire>` ;
  - CDP par `WebSocket` natif : `Emulation.setDeviceMetricsOverride` 1920×1080 avec un facteur de 1, et `Emulation.setEmulatedMedia` avec `prefers-color-scheme: light` pour le thème clair (si l'IHM reste en sombre, clic sur `#theme` avant l'enregistrement) ;
  - `Page.startScreencast` en JPEG, chaque image horodatée ;
  - assemblage à 30 i/s constants par le démultiplexeur `concat` de ffmpeg, avec la durée de chaque image.

- [ ] **Step 1: Écrire le test qui échoue.** `test_ihm.mjs` vérifie que :
  - `verifierActions([{clic:"#entreprise"}])` lève une erreur ;
  - `verifierActions([{defiler:"#levels tr"}])` lève une erreur ;
  - `verifierActions([{voler:1}])` lève une erreur ;
  - `verifierActions([{touche:"ArrowRight"},{attendre:500}])` ne lève rien.
- [ ] **Step 2: Lancer** `node --test video/tournage/test_ihm.mjs`. Attendu : échec.
- [ ] **Step 3: Écrire `ihm.mjs`.**
- [ ] **Step 4: Relancer le test.** Attendu : réussite.
- [ ] **Step 5: Écrire `ihm-essai.json` et `ihm.ps1`.** L'essai passe les écrans 1 à 5 avec `ArrowRight` (4 s par écran) et fait défiler l'écran 5, sans aucun clic dans l'écran 2.
- [ ] **Step 6: Premier essai de l'IHM sur le serveur**, sans gêner l'écran de l'utilisateur. Lancer `powershell -File video/tournage/ihm.ps1 -Actions video/tournage/ihm-essai.json -Sortie video/captures/essai-ihm`. Attendus :
  - une vidéo 1920×1080 d'environ 25 s ;
  - sur sa planche contact (Task 6), les 5 écrans remplis, sans dialogue de connexion ;
  - `etat-labo.sh bilan` toujours à 12 lignes ;
  - aucun `data/notes.json` créé.
  
  Si l'IHM a un vrai bug : le corriger, `bash deploy/push-lab.sh`, puis le noter pour l'utilisateur.
- [ ] **Step 7: Écrire `ihm-tournage.json`.** Déroulé :
  - écran 1 (8 s) ;
  - écran 2 : clic sur le scénario choisi dans `#scenarios button.scn:nth-child(N)`, clic sur un prompt prêt dans `#seeds button`, clic sur `#submit`, `attendre_selecteur` sur `#verdict:not([hidden])` (240 s au plus), second prompt si besoin, clic sur `#flat` (« Voir comme le modèle »), défilement de `#stream` ;
  - écrans 3, 4 et 5 (8 s chacun, défilement de 5).
  
  `N` et le nombre de prompts sont fixés au tournage, d'après le bilan de la prise de la fenêtre : une attaque compromise.

### Task 5: Tournage

**Files:**
- Create: `video/captures/fenetre-prise<k>.mp4|.touches.json`, `video/captures/ihm-prise<k>.mp4|.actions.json`, `video/captures/bilan-prise<k>.txt`

**Interfaces:**
- Consumes : `etat-labo.sh` (Task 2), `fenetre.ps1` (Task 3), `ihm.ps1` et `ihm-tournage.json` (Task 4).
- Produces : les captures retenues et leur bilan, utilisés par la Task 7.

- [ ] **Step 1: Demander le feu vert.** Annoncer environ 10 minutes sans toucher au PC et demander d'activer « Ne pas déranger ». Ne rien lancer avant la réponse.
- [ ] **Step 2: Mettre de côté.** `etat-labo.sh mettre-de-cote`, puis `bilan`. Attendu : aucune ligne.
- [ ] **Step 3: Prise de la fenêtre.** `fenetre.ps1 -Sortie video/captures/fenetre-prise1 -Touches 'F5','1','2','3','4','5','6','7','8'`, puis `bilan > video/captures/bilan-prise1.txt`. Attendu : 8 lignes, aucune `incomplete`. Sinon : `archiver prise1-rate` et refaire la prise avec `k+1`.
- [ ] **Step 4: Prise de l'IHM.** Fixer `N` sur une attaque compromise du bilan, puis lancer `ihm.ps1 -Actions video/tournage/ihm-tournage.json -Sortie video/captures/ihm-prise1`. Ensuite, `bilan` doit afficher 9 lignes, la dernière jouée depuis l'IHM.
- [ ] **Step 5: Archiver puis restaurer.** `archiver prise1`, puis `restaurer`. Attendus : code 0, `sha256sum -c` OK sur les 12 fichiers, `bilan` à 12 lignes identiques à celles de la Task 2, step 5.
- [ ] **Step 6: Contrôler les fuites.** Lire le jeton par SSH dans une variable, chercher sa présence dans `video/` (`Select-String -SimpleMatch -Quiet`), puis effacer la variable. Attendu : `False`.
- [ ] **Step 7: Relire la planche contact de chaque prise** (Task 6, image toutes les 5 s). Attendus : aucune notification, aucune fenêtre étrangère, aucun dialogue. Sinon, refaire la prise concernée en reprenant aux steps 2 à 5.
- [ ] **Step 8: Prévenir l'utilisateur** que le PC est libre et que les 12 essais sont remis à l'identique.

### Task 6: Moteur de montage

**Files:**
- Create:
  - `video/commun.py` : copie verbatim des fonctions RAO de `build.py` (`run`, `FFMPEG`, `SR`, `chiffres`, `pour_affichage`, `en_lettres`, `prononcer`, `empreinte`, `synthese_edge`, `vers_wav`, `lire_wav`, la découpe des sous-titres `_decoupe`…`sous_titres`, `chapitres_ffmetadata`, `couper_sous_titres_par_defaut`). Les tables `LEXIQUE` et `AFFICHAGE` sont propres au projet LLM.
  - `video/montage.py`.
  - `video/planche.py` : copie de RAO `planche.py`, chemins adaptés.
  - `video/prononciation.py` : copie de la partie `--asr` de RAO `mesures.py`.
- Test: `video/test_video.py` (ajouts).

**Interfaces:**
- Consumes : `cartes.transition`, `cartes.fiche`, `cartes.badge` (Task 1) ; `<capture>.touches.json` (Task 3).
- Produces (dans `montage.py`) :
  - `charger(chemin: Path) -> dict`. Valide `video/script.json` : `{"title", "scenes":[{"id","chapitre","beats":[{"say": str, <un seul visuel>}]}]}`. Le visuel est l'un des suivants :
    - `"clip": {"source": "fenetre-prise1", "de": s, "a": s}` ;
    - `"fige": {"source": …, "t": s}` ;
    - `"carte": {"type": "transition", "numero", "prenom", "role"}` ;
    - `"carte": {"type": "fiche", "prenom", "role", "message", "maitriser", "questions", "relais"}`.
    
    Lève `ValueError` en nommant la scène et la phrase fautives (zéro ou deux visuels, `a <= de`, source absente de `video/captures/`).
  - `duree_beat(voix: float, visuel: dict) -> float`. Pour `clip` : `max(voix + BEAT_GAP, a - de)`, sans jamais accélérer ni couper l'extrait choisi. Pour `fige` et transition : `voix + BEAT_GAP`. Pour fiche : `max(voix + BEAT_GAP, 20.0)`.
  - `chronologie(script: dict, voix: dict[tuple[int,int], float]) -> dict`, qui renvoie `{"beats": [(si, bi, debut, duree)], "debuts": [début de chaque scène], "duree": total}`. Valeurs : `LEAD = 1.0`, `BEAT_GAP = 0.5`, `SCENE_GAP = 1.2`, `TAIL = 3.0`, `XF_BEAT = 0.35` (fondu entre deux sources différentes ; coupe franche si la même source continue), `XF_SCENE = 0.7` (fondu par le fond `#F5F7FB`). Un fondu ne raccourcit jamais une phrase : le segment précédent est prolongé de la durée du fondu.
  - `rendre_segment(visuel: dict, duree: float, travail: Path) -> Path`. Segment mis en cache sous l'empreinte de `(visuel, duree)`, mis à l'échelle en 1920×1080 à 30 i/s. Un `clip` prend son extrait réel et fige la dernière image si `duree > a - de`. Le badge de chaque touche de `touches.json` comprise dans `[de, a]` est incrusté de `t` à `t + 1.5`.
  - `main()` : `python video/montage.py video/script.json video/travail [--apercu] [--voix-muette]`. Il fait la synthèse avec cache, la chronologie, les segments, puis l'assemblage : fondus, piste voix normalisée, SRT, chapitres, correctif de la piste de sous-titres. Il écrit `video/labo_llm_explique.mp4` (ou `apercu.mp4`), `video/sous-titres_fr.srt`, `video/travail/chronologie.json` et `video/chapitres.md`. L'option `--voix-muette` remplace la synthèse par un silence de `0.065 s` par caractère : c'est pour les tests, sans réseau.

- [ ] **Step 1: Écrire les tests qui échouent** (ajouts à `test_video.py`) :
  - `duree_beat(3.0, {"clip": {"source": "x", "de": 2, "a": 10}}) == 8.0` ;
  - `duree_beat(9.0, même clip) == 9.5` ;
  - `duree_beat(4.0, fiche) == 20.0` ;
  - pour un script de 2 scènes et 3 phrases aux voix de `{2, 3, 4}` s, le `duree` de `chronologie` vaut `LEAD + Σ duree_beat + SCENE_GAP + TAIL`, et `debuts[1]` est le début de la 3ᵉ phrase moins `SCENE_GAP` ;
  - `charger` lève `ValueError` contenant `"scène"` pour une phrase sans visuel ;
  - bout en bout avec `--voix-muette` : deux captures de 6 s générées par ffmpeg (`testsrc2`, 1280×720) dans un dossier temporaire, un `touches.json` à `t = 1.0`, un script de 2 scènes (clip, fige, transition, fiche). `ffprobe` doit donner : vidéo 1920×1080 à 30 i/s, une piste audio, une piste `mov_text`, 2 chapitres, une durée égale au `duree` de `chronologie.json` à 0,1 s près.
- [ ] **Step 2: Lancer** `python video/test_video.py`. Attendu : échec, `montage` introuvable.
- [ ] **Step 3: Copier `commun.py`, `planche.py` et `prononciation.py`, puis écrire `montage.py`.**
- [ ] **Step 4: Relancer** `python video/test_video.py`. Attendu : `ok`, y compris `test_cartes`.

### Task 7: Narration

**Files:**
- Create: `video/script.json`

**Interfaces:**
- Consumes : les captures, `touches.json`, `actions.json` et `bilan-prise*.txt` de la Task 5 ; `charger` et `planche` de la Task 6.

- [ ] **Step 1: Préparer la relecture des captures.** Faire une planche contact de chaque capture retenue (1 image toutes les 2 s) et la regarder. Noter les instants utiles : vérification du labo, début et verdict de chaque attaque, « Voir comme le modèle », chaque écran de l'IHM.
- [ ] **Step 2: Écrire `video/script.json`.** Structure de la spec, environ 12 minutes :
  - Ouverture ;
  - Maxime, Nolan, Fatih, Valentin : chacun ouvre par une carte de transition et finit par une carte de fiche ;
  - Conclusion.
  
  Sources du texte : README, `app/scenarios.mjs`, `app/public/index.html`, `verifier/verify.mjs`, `bilan-prise*.txt`. Les « questions fréquentes » de `docs/presentation.md` ne sont reprises qu'après vérification, car le document est obsolète. Les chiffres viennent du bilan réel ; la voix dit que ce sont les essais de démonstration du tournage. Pour « Et dans mon entreprise ? » et les essais Gandalf, la voix dit ce que Valentin et Fatih doivent préparer, sans écrire ce contenu à leur place. Les sigles s'écrivent comme ils doivent être lus (« O-WASP », « L-L-M ») ; `AFFICHAGE` les remet en graphie normale pour l'écran.
- [ ] **Step 3: Vérifier la structure.** `python -c "import sys; sys.path.insert(0,'video'); import montage; montage.charger(__import__('pathlib').Path('video/script.json'))"`. Attendu : aucune erreur.
- [ ] **Step 4: Faire relire l'exactitude par un relecteur neuf** (sous-agent), avec la spec (section Exactitude et anti-objectifs), `script.json`, les sources, les bilans et les planches contact. Consigne : signaler chaque phrase non étayée par une source ou par une image. Corriger chaque point retenu.

### Task 8: Voix, prononciation, vidéo finale

**Files:**
- Modify: `video/commun.py` (tables `LEXIQUE` et `AFFICHAGE`), `video/script.json` (corrections)
- Modify: `README.md` (une ligne : où est la vidéo et comment la reconstruire)
- Create: `video/labo_llm_explique.mp4`, `video/sous-titres_fr.srt`, `video/chapitres.md`

- [ ] **Step 1: Première synthèse et aperçu.** `python video/montage.py video/script.json video/travail --apercu`. Attendu : `video/apercu.mp4` d'une durée de 10 à 14 min.
- [ ] **Step 2: Contrôler la prononciation.** `python video/prononciation.py video/travail`. Pour chaque phrase dont la transcription s'écarte, ajouter une entrée à `LEXIQUE` (candidats : Ollama, Qwen, OWASP, ChatML, base64, Lakera, JSON, Proxmox, ROT13), puis relancer les steps 1 et 2. Attendu : plus aucun écart sur un terme technique.
- [ ] **Step 3: Relire l'aperçu.** Faire une planche contact toutes les 10 s et la regarder. Attendus :
  - chaque phrase tombe sur l'image dont elle parle ;
  - les badges apparaissent sur les bonnes touches ;
  - les fiches restent au moins 20 s ;
  - aucune image noire ;
  - fondus aux changements de scène.
- [ ] **Step 4: Vidéo finale.** `python video/montage.py video/script.json video/travail`. `ffprobe` doit donner :
  - 1920×1080 à 30 i/s, H.264 + AAC ;
  - une piste `mov_text` non activée par défaut ;
  - autant de chapitres que de scènes ;
  - `video/chapitres.md` qui liste les mêmes horodatages.
- [ ] **Step 5: Contrôles finaux.**
  - Rechercher le jeton dans `video/`, comme à la Task 5, step 6. Attendu : `False`.
  - Dans le conteneur, `cd /opt/llm-security-lab/data && sha256sum -c ../mis-de-cote-2026-11-15/MANIFEST.sha256` : tout OK. Puis `bilan` : 12 lignes, identiques à celles de la Task 2, step 5.
- [ ] **Step 6: README.** Ajouter la ligne sur la vidéo, puis remettre à l'utilisateur :
  - le chemin de la vidéo ;
  - la durée et les chapitres ;
  - les bugs de l'IHM corrigés, s'il y en a eu ;
  - le rappel que les essais du tournage sont archivés dans `tournage-2026-11-15/`.
