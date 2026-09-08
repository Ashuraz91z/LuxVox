# Lux Vox — Direction artistique & Design System

> Décline `Lux Calendar/Specs/Design-System-macOS.md` pour une application sans
> fenêtre. La palette de marque et le squircle ne bougent pas ; tout ce qui
> supposait une fenêtre est refait ou supprimé.
> Planche visuelle : `identite-visuelle.svg`.
> Dernière mise à jour : 2026-09-04.

---

## 1. Le problème que ce document résout

Le design system Mac de Lux suppose une fenêtre : barre latérale de 200 pt,
colonne de contenu à 720, cartes de 40, barre d'outils de 44. **Lux Vox n'a
rien de tout ça.** Son interface complète tient en trois surfaces :

| Surface | Taille réelle | Ce qui s'y joue |
|---|---|---|
| Le glyphe de la barre des menus | **16 pt, monochrome** | 95 % du temps passé avec l'app |
| Le panneau déroulant | ~280 × 340 pt | L'historique, les réglages |
| L'icône d'application | 1024 → 16 | Finder, DMG, Réglages Système |

Un design system qui parle de densité et d'élévation n'a rien à dire ici. Ce
qu'il faut, c'est une **marque qui survit à 16 pixels en noir et blanc**.

## 2. La marque

### 2.1 La règle de famille, telle qu'elle existe déjà

Elle ne s'énonce nulle part, mais les deux icônes existantes la disent
clairement — et c'est elle qui gouverne ce document :

| | Lux Calendar | Lux Md |
|---|---|---|
| Forme | 8 pétales | 4 barres |
| Construction | **formes pleines, bouts entièrement arrondis** | idem |
| Composition | **répétition d'une primitive** | idem |
| Couleur | sauge sur squircle sombre | **or sur l'élément distinctif**, sauge et menthe pour le reste |

Trois invariants : **du plein, jamais du trait ; des bouts arrondis ; une
primitive répétée.** Plus une règle de couleur : *un accent propre au produit,
posé sur l'élément qui le distingue, le reste dans les verts de la famille.*

Lux Vox applique les quatre. C'est ce qui le rend frère de Calendar et de Md
sans rien leur emprunter.

### 2.2 Le symbole : un microphone

Un micro, littéralement — capsule, arceau, pied. Pas de métaphore, pas de
symbole à déchiffrer. Une app qu'on invoque au clavier et qui vit dans un coin
de l'écran n'a pas le luxe d'être devinée.

Ce qui le rend Lux plutôt que générique, c'est **la construction, pas le sujet** :

- **Capsule** — une forme pleine à bouts entièrement arrondis, la même primitive
  que les barres de Lux Md, dressée. Courte et généreuse, jamais le tube fin des
  glyphes système.
- **Arceau** — un arc épais à extrémités arrondies, qui part à mi-hauteur de la
  capsule et l'enveloppe par en dessous. Il ne colle pas à la capsule : l'espace
  entre les deux fait partie du dessin.
- **Pied** — une troisième forme pleine arrondie, dans l'axe.

Trois pièces, trois poids, comme les quatre barres de Md ont quatre longueurs.

### 2.3 Ce que la marque n'est pas

**Elle n'emprunte rien au logo de Lux Audere.** L'anneau ouvert traversé par un
faisceau de `DA/logo.png` est la signature de la maison. Un produit qui le
reprend cesse d'être un produit et devient une déclinaison de l'entreprise.
Calendar a sa fleur, Md a ses barres, Vox a son micro — chacun se tient debout
tout seul, et c'est le squircle et la palette qui font la famille.

### 2.4 La règle qui gouverne tout le reste

> **L'état se lit à la forme, jamais à la couleur.**

En barre des menus, macOS repeint le glyphe en noir ou en blanc selon le thème
et l'état de sélection. Un glyphe qui distinguerait ses états par la teinte ne
distinguerait rien du tout. La forme est le seul canal disponible.

## 3. Le glyphe de barre des menus

Boîte de 16 unités. Image *template* : le système gère la couleur.

```
capsule creuse  rect x=6.2 y=1.6 w=3.6 h=7.6 rx=1.8 · trait 1.25
capsule pleine  même rect, rempli
arceau          M 12.3 7.2 A 4.3 4.3 0 0 1 3.7 7.2 · trait 1.35 · bouts ronds
anneau          circle cx=8 cy=7.2 r=4.3 · trait 1.35
arceau partiel  M 3.7 7.2 A 4.3 4.3 0 0 0 8 11.5 · trait 1.35 · bouts ronds
pied            rect x=7.35 y=11.5 w=1.3 h=2.5 rx=0.65
```

Deux variables indépendantes portent les quatre états : **le remplissage de la
capsule** (l'app dort ou travaille) et **la forme de l'arceau** (ce qu'elle fait).

| État | Capsule | Arceau | Lecture |
|---|---|---|---|
| **Repos** | creuse | simple | Un micro posé |
| **Écoute** | **pleine** | simple | La masse arrive : ça capte |
| **Écoute verrouillée** | pleine | **fermé en anneau** | Fermé, donc rien ne s'arrête tant qu'on ne le rouvre pas |
| **Traitement** | creuse | **quart d'arc qui balaie** | Asymétrique : quelque chose est en cours |

**Pourquoi l'anneau fermé pour le verrouillage.** C'est le seul état où le micro
reste ouvert sans que l'utilisateur ait un doigt sur la touche — donc le seul qui
doit se remarquer sans être cherché. Fermer l'arceau change la silhouette
entière, pas un détail, et le sens tombe juste : verrouillé = fermé.

**Pourquoi le quart d'arc pour le traitement.** C'est le seul état asymétrique
des quatre. À 16 pt, l'asymétrie se repère avant la forme — c'est ce qui le rend
identifiable du coin de l'œil, et l'animation ne fait que confirmer.

Le pied reste attaché à l'arceau dans les quatre états. Un pied qui flotte,
détaché, lit comme un glyphe cassé.

**Interdits :** pas de point rouge d'enregistrement — c'est le vocabulaire de la
capture d'écran, et il crie. Pas de badge, pas de compteur, pas de niveau sonore.

## 4. L'icône d'application

Squircle de la famille, dégradé vertical `#14322A → #0A1A16` en sombre,
`#FFFFFF → #F2EFE6` en clair. La marque occupe **56 %** du côté, centrée
optiquement (le pied tire l'axe optique vers le bas, le centre géométrique
paraît trop haut).

Répartition des couleurs, exactement la règle de Lux Md :

| Pièce | Sombre | Clair | Rôle |
|---|---|---|---|
| Capsule | `#8FB9C4` Halo | `#4A7C8C` Ardoise | **L'accent** — l'élément distinctif |
| Arceau | `#D5ECCD` menthe | `#8FAF93` sauge | Famille |
| Pied | `#94AD91` sauge | `#A8BFA5` sauge clair | Famille |

**L'icône montre toujours l'état de repos** — capsule creuse en barre des menus,
mais capsule pleine dans l'icône couleur, où le contour n'aurait aucun sens à
1024. Jamais l'anneau, jamais le balayage : une icône figée en train d'écouter
serait un contresens permanent sur une app de micro, et un mensonge dans le
Finder.

Génération : script `A/icon-generator.swift` hors cible, sur le modèle de Lux
Md. Dessin vectoriel redessiné à chaque taille, jamais redimensionné.

## 5. Palette

### 5.1 L'accent propre à Lux Vox

| Nom | Valeur | Rôle |
|---|---|---|
| **Ardoise** | `#4A7C8C` | Accent en thème clair |
| **Halo** | `#8FB9C4` | Accent en thème sombre |

Sauge appartient à Lux Calendar, l'or à Lux Md. L'ardoise est **froide** là où
les deux autres sont chaudes : les trois icônes se séparent au premier coup
d'œil dans le Dock, ce qui est la règle que le générateur de Lux Md avait déjà
posée pour l'or.

Le bleu n'est pas un choix décoratif : c'est la seule famille de teintes que la
palette Lux n'utilisait pas, et celle du signal.

### 5.2 Jetons repris sans changement

De `Design-System-macOS.md`, **en prenant les valeurs corrigées du document et
non celles de `LuxColor.swift`**, qui n'a pas encore reçu ses deux corrections :

| Jeton | Clair | Sombre |
|---|---|---|
| `surfaceElevated` | `#FFFFFF` | `#263329` |
| `text` | `#1D1D1F` | `#F0EEE6` |
| `textSecondary` | `#5B6B5E` | `#A9B8AB` |
| `textTertiary` | `#8B9389` | `#75817A` |
| `separator` | `#DCD7C8` | `#2C3A32` |
| `important` | `#C4703A` | `#F4A261` |

`important` sert à un seul endroit : la mention « saisie sécurisée — non
injecté » dans l'historique.

## 6. Typographie

Sous-ensemble strict de l'échelle Mac. Un panneau de 280 pt n'a pas de titres.

| Jeton | Taille | Graisse | Famille | Usage |
|---|---|---|---|---|
| `body` | 13 | 400 | SF | Le texte transcrit dans l'historique |
| `subhead` | 12 | 400 | SF | « il y a 4 min », état |
| `caption` | 11 | 600, +0,05 em, capitales | SF | « HISTORIQUE », « RÉGLAGES » |
| `mono` | 11,5 | 400 | SF Mono | Durée, latence mesurée |

**Pas de sérif.** New York et Playfair portent les titres de Lux Calendar ; ici
il n'y a aucun titre à porter. Le sérif ne réapparaît qu'à un seul endroit : le
mot « Lux Vox » dans la fenêtre d'onboarding, seul moment où l'app se présente.

## 7. Le panneau déroulant

`MenuBarExtra` en style `.window`. Largeur **280**, hauteur libre plafonnée à 340.

```
┌────────────────────────────────┐
│ HISTORIQUE                     │  caption, textTertiary
├────────────────────────────────┤
│ Il faut que je pense à rappeler│  body · 2 lignes max, puis …
│ il y a 4 min          1,2 s    │  subhead + mono, textTertiary
├────────────────────────────────┤
│ Le rendez-vous est décalé à…   │
│ il y a 12 min · non injecté    │  important si saisie sécurisée
├────────────────────────────────┤
│ ⚙ Réglages          ⏻ Quitter  │
└────────────────────────────────┘
```

- Rangée **36 pt** (deux lignes), marge intérieure 12, filet `separator` entre
  rangées — **jamais d'ombre**, règle du design system Mac.
- Survol : accent à 13 % sur toute la largeur. Clic : copie dans le
  presse-papier, et la rangée passe brièvement à l'accent plein, texte crème.
- Texte tronqué à deux lignes. Le panneau est un filet de sécurité, pas un
  lecteur.
- **Aucune capsule.** Rayon `6` pour tout contrôle — la capsule sur Mac est la
  signature d'un portage iOS.

## 8. Mouvement

| Transition | Traitement |
|---|---|
| Repos → Écoute | La capsule se remplit du bas vers le haut, 0,12 s, `easeOut` |
| Écoute → Verrouillé | Les deux extrémités de l'arceau se rejoignent, 0,18 s |
| → Traitement | La capsule se vide, l'arceau se réduit et balaie, 0,9 s/tour, linéaire |
| Traitement → Repos | L'arceau se redéploie, 0,15 s |
| Ouverture du panneau | Fondu 0,15 s |

**Rien ne pulse au rythme de la voix.** C'est tentant et c'est une faute : un
glyphe qui s'agite en permanence dans le champ de vision périphérique est une
nuisance. Il indique qu'on écoute, pas ce qu'on entend. Le niveau sonore n'a
aucune raison d'être affiché.

## 9. Les alertes système

Trois demandes au premier lancement — micro, Accessibilité, réglage de la touche
🌐. Ce sont des alertes **natives**, pas des écrans dessinés : c'est le seul
langage que l'utilisateur croit quand il s'agit d'accorder un pouvoir sur son
clavier. Une belle fenêtre custom qui réclame l'Accessibilité ressemble à un
logiciel malveillant.

Une seule surface dessinée : une fenêtre d'accueil sobre listant les trois
permissions, leur état (✓ / à accorder), et un bouton par permission qui ouvre le
panneau des Réglages Système correspondant. Elle ne se rouvre jamais d'elle-même
une fois les trois accordées.

## 10. Ce qu'on ne reprend pas, et pourquoi

| Écarté | Raison |
|---|---|
| Le logo de Lux Audere | C'est la signature de la maison. Un produit qui la porte cesse d'être un produit |
| La fleur à 8 pétales | Huit pétales et leurs interstices deviennent une tache grise à 16 pt. Elle reste la marque de Lux Calendar |
| Le dessin au trait | Hors langage : la famille est faite de formes pleines. Seuls l'arceau et la capsule creuse en usent, et à trait épais |
| L'échelle `display` / `title` / `heading` | Aucun titre nulle part |
| Barre latérale, colonne ≤ 720, barre d'outils | Il n'y a pas de fenêtre |
| Glassmorphism | Le design system Mac le réserve à la chrome. Il n'y a pas de chrome ici |
| Les couleurs de catégorie | Rien à catégoriser |
| Les ombres | Déjà proscrites dans la fenêtre ; un panneau de menu en a encore moins besoin |

## 11. Ce qui reste à trancher

1. **Le contour de la capsule à 16 pt.** `1.25` d'épaisseur laisse environ
   `1.1` d'intérieur. C'est la cote la plus tendue du dessin — à vérifier sur
   un écran non-Retina si l'app doit en croiser un.
2. **Le sens du balayage** en traitement — horaire par défaut, sans raison forte.
3. **Le halo de l'icône sombre** : aucun pour l'instant. À juger dans le Dock,
   à côté de Lux Calendar et Lux Md, avant d'en ajouter un.

## Principe directeur

L'app se voit 16 pixels à la fois, du coin de l'œil, pendant qu'on fait autre
chose. **Tout ce qui attire l'attention plus que nécessaire est un défaut**, pas
une qualité. Le glyphe dit trois choses et seulement trois : je dors, je
t'écoute, je travaille. Le reste est du bruit.
