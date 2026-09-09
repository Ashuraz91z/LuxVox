# Cahier des Charges : Lux Vox

> Application de dictée locale pour macOS.
> Dernière mise à jour : 2026-09-04. Aucune ligne de code écrite à ce jour.

---

## 1. Objectif du produit

Une application de dictée vocale qui réside dans la barre des menus macOS. Elle
capture la voix depuis la touche 🌐, la transcrit en **texte propre — sans les
hésitations**, et simule la frappe pour injecter le résultat là où se trouve le
curseur : page de notes, terminal, champ de recherche,
n'importe quoi.

Tout se passe en local. Aucun octet ne sort de la machine.

## 2. Nom et identité

**Lux Vox** — *vox*, la voix en latin, en écho à Lux Audere. Trois lettres comme
le *Md* de Lux Md : la famille se lit comme une collection.

- Nom du produit : `Lux Vox`
- Identifiant de bundle : `lux-audere.Lux-Vox` — convention de la famille
  (`lux-audere.Lux-md`, `lux-audere.Lux-Calendar`)
- Dossier de travail : `Lux Vox/`

L'icône reprend le squircle et la palette de la famille (voir `Lux Calendar/A/`
et `Lux Md/A/icon-generator.swift`, qui régénère tout le jeu d'icônes depuis un
script hors cible — même approche ici). Le V et l'onde sonore sont la même
forme : c'est la piste de départ.

## 3. Fonctionnalités principales

* **Déclencheur global — la touche 🌐 (Fn).** Celle en bas à gauche des
  claviers Apple. Deux gestes sur cette seule touche : **maintien** (le micro
  s'ouvre à l'appui, se ferme au relâchement) et **double-appui** (le micro
  reste ouvert sans les mains ; un appui simple le referme). Comportement
  détaillé et contraintes système en section 6, décision *b*.
* **Transcription embarquée.** Traitement local sur le Neural Engine. Cible :
  **texte injecté en moins de 2 secondes** après le relâchement de la touche,
  sans aucune connexion réseau.
* **Nettoyage du texte.** Les hésitations disparaissent avant l'injection.
  C'est une exigence de v1, détaillée en section 4.
* **Injection automatisée.** Simulation de frappe à l'emplacement du curseur.
* **Historique de secours.** Un menu déroulant depuis l'icône affiche les 10
  dernières transcriptions, copiables à la main si le focus de fenêtre a échoué.

## 4. Le nettoyage du texte (exigence v1)

C'est ce qui sépare cette app d'une dictée brute. Deux passes, dans cet ordre.

### Passe 1 — règles (toujours active, coût ~0 ms)

Traitement de texte pur, sans modèle. Couvre l'essentiel des hésitations.

| Dicté | Écrit |
|---|---|
| « euh je voulais heu te dire » | « Je voulais te dire » |
| « je je je pense que » | « Je pense que » |
| « c'est bon quoi voilà » | « C'est bon. » |
| « du coup en fait bah oui » | « Oui. » |

Périmètre de la passe 1 :
- tics lexicaux : *euh, heu, hum, bah, ben, quoi, voilà, du coup, en fait*
  (retirés en position de remplissage, conservés quand ils portent du sens)
- bégaiements et répétitions immédiates de mots
- ponctuation dictée : *virgule, point, à la ligne, point d'interrogation*
- majuscule en début de phrase, espaces français corrects avant `? ! : ;`

Contrainte d'implémentation : **fonction pure, sans SwiftUI, testable headless**,
sur le modèle de `Lux Md/Lux md/MarkdownFormatter.swift`. La suite de tests est
une table texte-entrée / texte-attendu qui tourne sans lancer l'app. C'est ce qui
rend le réglage des règles supportable dans la durée.

### Passe 2 — modèle de langue on-device (sous délai maximum)

Les faux départs échappent à toute règle : « je vais au ma… non en fait je pars
demain » demande de comprendre que la première moitié est annulée. Passe via
`FoundationModels` (modèle de langue local d'Apple, hors-ligne), avec une
consigne stricte : **nettoyer, jamais reformuler**. Le sens et le vocabulaire de
l'utilisateur ne changent pas.

**Garde-fou non négociable :** délai maximum de 400 ms. Passé ce délai, on
injecte le résultat de la passe 1 et on abandonne la passe 2. Le budget de 2
secondes ne saute jamais à cause du nettoyage.

Le coût réel de cette passe se mesure à l'étape 2 du plan (section 8). Si elle
s'avère trop lente ou trop bavarde, elle devient une option désactivée par
défaut — mais elle est livrée en v1.

## 5. Interface et expérience utilisateur

* **Absence du Dock.** L'app tourne en arrière-plan uniquement (agent,
  `LSUIElement`). Pas de fenêtre principale.
* **Retour visuel minimaliste.** L'icône de la barre des menus a quatre états :
  repos, écoute, **écoute verrouillée**, traitement. L'état verrouillé doit se
  distinguer au premier coup d'œil : c'est le seul cas où le micro est ouvert
  sans que l'utilisateur ait un doigt sur la touche. SF Symbols pour commencer ;
  assets dessinés ensuite, une fois les états validés à l'usage.
* **Onboarding natif.** Au premier lancement, les alertes système guident vers
  les deux permissions indispensables : **Microphone** et **Accessibilité**.
  L'app doit rester compréhensible tant qu'elles ne sont pas accordées (état
  d'icône dédié, entrée de menu qui ouvre le bon panneau des Réglages Système).

## 6. Architecture et stack technique

* **Environnement :** Xcode 27, Swift 6.4, macOS 27, Apple Silicon.
* **Mode langage Swift 6** (concurrence stricte), contrairement à Lux Md et Lux
  Calendar restés en mode 5. Lux Vox fait dialoguer trois contextes d'exécution :
  le thread temps réel d'`AVAudioEngine`, le callback du tap `CGEvent` sur sa
  boucle d'exécution, et l'UI sur le `MainActor`. C'est précisément le terrain
  où un accès concurrent ne se manifeste qu'en plantage intermittent
  impossible à reproduire. Le compilateur les refuse à la place.
* **Interface :** SwiftUI, composant `MenuBarExtra` (style `.window` pour la
  liste d'historique).
* **Capture audio :** `AVAudioEngine`, 16 kHz mono. Le socle existe déjà dans
  `Lux Calendar/Lux Calendar/Services/DictationService.swift` (permissions,
  capture, détection de silence, français) — à reprendre plutôt qu'à réécrire.
* **Sécurité :** App Sandbox **désactivé** (`ENABLE_APP_SANDBOX = NO`), sans
  quoi le contrôle du clavier est impossible. Conséquence assumée : pas de
  distribution App Store. Même choix que Lux Md.

### Décisions techniques prises

Quatre points où la solution évidente ne marche pas. Ils sont tranchés ici pour
ne pas être redécouverts pendant l'implémentation.

**a. Le moteur de transcription — derrière une abstraction**

Un protocole `MoteurTranscription` avec deux implémentations mises en
concurrence à l'étape 2 :

| | WhisperKit (`base`) | `SpeechTranscriber` (macOS 26+) |
|---|---|---|
| Poids dans le `.dmg` | ~150 Mo | 0 |
| Hors-ligne dès l'installation | oui | modèle téléchargé par l'OS au 1ᵉʳ usage |
| Ponctuation / français | très bon | à mesurer |
| Contrôle | total | boîte noire |

WhisperKit est le défaut retenu, conforme à l'intention d'origine (modèle
pré-intégré, fonctionnement immédiat hors-ligne). L'abstraction coûte deux
heures et évite de refaire le socle si l'API native d'Apple gagne le banc
d'essai. **La décision se prend sur des chiffres, pas sur une intuition.**

**b. Le déclencheur — la touche 🌐 (Fn), via un `CGEvent` tap**

*La touche.* Celle marquée du globe, en bas à gauche des claviers Apple. Elle
n'émet pas un `keyDown` ordinaire : macOS la signale par un **`flagsChanged`**
portant le drapeau `.function` (`kCGEventFlagMaskSecondaryFn`). L'appui et le
relâchement se lisent donc sur les transitions de ce drapeau — ce qui suffit
pour le maintien comme pour le double-appui.

*Les deux gestes.* Une seule touche, deux façons de s'en servir :

| Geste | Effet |
|---|---|
| Maintien (> 300 ms) | Enregistre tant que la touche est tenue. Relâchement → transcription et injection. |
| Double-appui (deux appuis en moins de 300 ms) | **Mode verrouillé** : le micro reste ouvert, sans les mains. |
| Appui simple, en mode verrouillé | Ferme le micro → transcription et injection. |
| `Échap`, dans les deux modes | Annule : rien n'est transcrit, rien n'est injecté. |

*Comment lever l'ambiguïté.* Un appui court peut être le premier d'un
double-appui. Règle : **un appui de moins de 300 ms n'est jamais une dictée** —
personne ne dit rien en 300 ms. L'audio de ce fragment est jeté et l'app attend
300 ms de plus un second appui. Au-delà de 300 ms de maintien il n'y a plus
d'ambiguïté possible : c'est une dictée, et aucun délai n'est ajouté.

*Prérequis système, à traiter dans l'onboarding.* macOS s'attribue cette touche
par défaut. Dans Réglages Système → Clavier, il faut régler « Appuyer sur 🌐
pour » sur **Ne rien faire**, et désactiver le double-appui qui lance la dictée
d'Apple — sinon les deux dictées se déclenchent ensemble. **L'app doit vérifier
cette configuration au premier lancement et guider l'utilisateur vers le bon
panneau** : c'est la première cause d'échec prévisible, et elle n'a rien à voir
avec le code.

*Pourquoi un tap.* Un moniteur global `NSEvent` observe les touches mais **ne
les consomme pas** : le déclencheur atteindrait aussi l'application au premier
plan. `CGEvent.tapCreate` en `headInsertEventTap` permet d'intercepter.

*À valider à l'étape 3.* Le globe est traité très bas dans la pile système ; que
ses transitions remontent bien jusqu'à un tap de session, et qu'on puisse les
consommer, se vérifie sur la machine avant de bâtir dessus. **Repli si la touche
🌐 s'avère incapturable : Ctrl droit** — également un modificateur lisible en
`flagsChanged`, keycode distinct du Ctrl gauche, libre de toute réservation
système, et compatible avec exactement la même grammaire de gestes. Le
déclencheur doit rester configurable entre les deux.

**c. L'injection — hybride, avec garde-fou**

- Par défaut `CGEvent.keyboardSetUnicodeString` : indépendant du layout clavier,
  accents corrects. **Par paquets d'environ 20 caractères**, sinon les
  applications Electron et les terminaux perdent des événements synthétiques
  envoyés trop vite.
- Au-delà d'environ 200 caractères : presse-papier + `Cmd+V` synthétique, avec
  **restauration du presse-papier précédent**.
- **Test `IsSecureEventInputEnabled()` avant toute injection.** Si un champ de
  saisie sécurisée a le focus (mot de passe), on n'injecte rien : le texte part
  dans l'historique et une notification le signale.

**d. La signature — un certificat stable dès le jour 1**

Sandbox désactivé + permission Accessibilité : l'autorisation TCC s'accroche à
la signature du binaire. En signature ad-hoc, **la permission saute à chaque
recompilation** et impose un aller-retour dans les Réglages Système à chaque
build. Un certificat stable (Developer ID, ou auto-signé persistant) réglé avant
la première ligne de code économise des dizaines d'interruptions.

Pour qu'un `.dmg` s'ouvre sans clic-droit sur une autre machine, il faut en plus
la notarisation. En usage personnel, on documente le
`xattr -d com.apple.quarantine` et on s'en tient là.

## 7. Décisions par défaut (à confirmer à l'usage)

Ces points n'étaient pas tranchés dans la première version du cahier. Valeurs
retenues pour ne pas bloquer le démarrage — chacune est révisable.

| Question | Décision | Pourquoi |
|---|---|---|
| Langue | Français forcé | Évite la latence et les erreurs de détection automatique |
| La fenêtre a changé pendant la transcription | **On n'injecte pas.** Historique + notification | Écrire dans la mauvaise fenêtre est pire que ne rien écrire |
| Durée maximale — maintien | 60 s, transcription par morceaux au-delà de 20 s | Tenir les 2 s sur les longues dictées |
| Durée maximale — mode verrouillé | Arrêt automatique après 30 s de silence, plafond dur à 5 min | Un micro ouvert et oublié ne doit jamais le rester |
| Persistance de l'historique | **Mémoire vive uniquement**, perdu au redémarrage | Confidentialité : du texte dicté ne traîne pas sur disque |

## 8. Plan de réalisation

Les étapes 1 à 3 portent le risque technique. Les étapes 4 à 6 sont du travail
sûr.

1. **Socle & permissions** — projet Xcode, `MenuBarExtra` + `LSUIElement`,
   onboarding micro/Accessibilité, certificat de signature (décision *d*).
   *Vérifiable :* l'icône est dans la barre, les deux permissions s'accordent et
   survivent à une recompilation.

2. **Banc d'essai des moteurs** — protocole `MoteurTranscription`, les deux
   implémentations, mesures de latence sur un jeu de phrases réelles. Mesurer au
   passage le coût de la passe 2 du nettoyage.
   *Vérifiable :* un tableau de chiffres et une décision motivée.

3. **Capture & déclencheur** — `CGEvent` tap sur la touche 🌐, les deux gestes
   et la règle des 300 ms (décision *b*), `AVAudioEngine` 16 kHz mono repris de
   Lux Calendar, préchauffage du modèle au lancement pour tenir les 2 s.
   *Vérifiable :* maintenir enregistre et relâcher transcrit ; double-appui
   verrouille et appui simple relâche ; `Échap` annule ; chronomètre à l'appui.
   *À lever en premier :* la capture effective du globe (voir décision *b*).

4. **Nettoyage du texte** — les deux passes de la section 4, avec leur suite de
   tests headless.
   *Vérifiable :* la table de tests passe au vert, sans lancer l'app.

5. **Injection** — stratégie hybride et garde-fou Secure Input (décision *c*),
   testée dans Notes, Terminal, VS Code et Slack : les quatre se comportent
   différemment.

6. **Finition & livrable** — états d'icône, historique des 10 dernières, `.dmg`
   dans `Apps/` comme Lux Md, `Claude.md` du projet.

## 9. Livrable attendu

Un exécutable empaqueté en `.dmg`, installable par glisser-déposer dans
*Applications*, contenant le modèle d'IA pré-intégré pour un fonctionnement
immédiat hors-ligne. Rangé dans `Apps/`, comme `Lux Md/Apps/Lux md.dmg`.

## 10. Hors scope v1

À écarter explicitement tant qu'un besoin réel n'émerge pas :

- multilingue et détection automatique de langue
- reformulation ou amélioration du style (la passe 2 nettoie, elle ne réécrit pas)
- dictée toujours à l'écoute, déclenchée par un mot-clé (le mode verrouillé de
  la décision *b* couvre le besoin sans micro ouvert en permanence)
- fenêtre de réglages complète (le menu déroulant suffit)
- synchronisation ou export de l'historique
- iOS

## Principe directeur

Ce que l'utilisateur a dit doit arriver intact à l'écran, moins les hésitations.
En cas de doute — focus incertain, saisie sécurisée, modèle trop lent — **ne rien
écrire vaut mieux qu'écrire au mauvais endroit ou déformer les mots**. Le texte
reste disponible dans l'historique ; c'est le filet de sécurité.
