#!/bin/bash
#
# Empaquette une app dans un DMG mis en scène.
#
#     Scripts/dmg.sh "chemin/vers/Lux Vox.app" "Apps/LuxVox-0.2.1.dmg"
#
# Séparé de `release.sh` pour une raison pratique : refaire la fenêtre du DMG
# ne devrait pas coûter une compilation Release de six minutes. Le script
# prend n'importe quelle app déjà construite.
#
# La mise en scène passe par Finder, en AppleScript — c'est le seul moyen
# d'écrire un `.DS_Store` sans embarquer une bibliothèque tierce. Au premier
# lancement, macOS demandera l'autorisation « contrôler Finder » pour le
# terminal. C'est une fois, dans Réglages Système → Confidentialité et
# sécurité → Automatisation.
#
set -euo pipefail

app="${1:-}"
dmg="${2:-}"
if [[ -z "$app" || -z "$dmg" ]]; then
    echo "usage : Scripts/dmg.sh <chemin de l'app> <chemin du dmg>" >&2
    exit 1
fi
[[ -d "$app" ]] || { echo "erreur : introuvable — $app" >&2; exit 1; }

racine="$(cd "$(dirname "$0")/.." && pwd)"
volume="Lux Vox"
monte="/Volumes/$volume"

# Un volume du même nom déjà monté et le nôtre arriverait en « Lux Vox 1 » :
# l'AppleScript mettrait alors en scène la fenêtre de quelqu'un d'autre. On
# s'arrête plutôt que de démonter un disque qui n'est pas à nous.
if [[ -d "$monte" ]]; then
    echo "erreur : « $volume » est déjà monté. Éjecte-le d'abord :" >&2
    echo "    hdiutil detach \"$monte\"" >&2
    exit 1
fi

scene="$(mktemp -d)"
rw="$(mktemp -u).dmg"
# Un échec au milieu de la mise en scène laisserait un volume monté, et le
# prochain lancement se heurterait au garde-fou ci-dessus.
trap 'hdiutil detach "$monte" -quiet 2>/dev/null || true; rm -rf "$scene" "$rw"' EXIT

echo "▸ décor"
cp -R "$app" "$scene/"
ln -s /Applications "$scene/Applications"

mkdir "$scene/.background"
xcrun swift "$racine/Scripts/fond-dmg.swift" "$scene/.background" > /dev/null

# Les cotes de la fenêtre sont celles du fond : Finder ne redimensionne pas
# une image de fond, il la pose. Le générateur les écrit, on les relit — elles
# n'ont ainsi qu'un seul domicile.
# shellcheck source=/dev/null
source "$scene/.background/cotes.sh"
rm "$scene/.background/cotes.sh"
# Un TIFF à deux images : macOS y prend la 2× sur un écran Retina, la 1×
# ailleurs. Deux PNG séparés ne se déclarent pas comme un même fond.
tiffutil -cathidpicheck \
    "$scene/.background/fond.png" "$scene/.background/fond@2x.png" \
    -out "$scene/.background/fond.tiff" > /dev/null 2>&1
rm "$scene/.background/fond.png" "$scene/.background/fond@2x.png"

echo "▸ image de travail"
# Marge : Finder doit pouvoir écrire son `.DS_Store` dans un volume déjà
# rempli au ras par `-srcfolder`.
taille=$(( $(du -sm "$scene" | cut -f1) + 20 ))
hdiutil create -volname "$volume" -srcfolder "$scene" -ov \
    -format UDRW -size "${taille}m" -quiet "$rw"
hdiutil attach "$rw" -readwrite -noverify -noautoopen -quiet

echo "▸ mise en scène"
osascript > /dev/null <<APPLESCRIPT
tell application "Finder"
    tell disk "$volume"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set sidebar width of container window to 0
        set the bounds of container window to {240, 140, 240 + $largeur, 140 + $hauteur}

        set reglages to the icon view options of container window
        set arrangement of reglages to not arranged
        set icon size of reglages to $icone
        set text size of reglages to 12
        set label position of reglages to bottom
        set background picture of reglages to file ".background:fond.tiff"

        set position of item "Lux Vox.app" of container window to {$x_app, $axe}
        set position of item "Applications" of container window to {$x_applications, $axe}

        update without registering applications
        close
    end tell
end tell
APPLESCRIPT

# L'icône du volume : dans la barre latérale et sur le bureau, un disque
# monté porte sinon un générique blanc.
#
# Trois pièges, tous payés en essais. Le fichier se pose dans le volume monté
# et non dans le décor — `hdiutil create -srcfolder` filtre ce nom-là. Il se
# pose **après** la mise en scène — tant que la fenêtre est ouverte, Finder
# efface un `.VolumeIcon.icns` qu'il ne s'attendait pas à trouver. Et le
# drapeau vient juste derrière, sinon le fichier ne sert à rien.
cp "$app/Contents/Resources/AppIcon.icns" "$monte/.VolumeIcon.icns"
SetFile -a C "$monte"

# Finder écrit le `.DS_Store` de façon paresseuse : sans ce répit, le
# démontage emporte la mise en scène.
sleep 2
sync
hdiutil detach "$monte" -quiet

echo "▸ compression"
mkdir -p "$(dirname "$dmg")"
rm -f "$dmg"
hdiutil convert "$rw" -format UDZO -imagekey zlib-level=9 -quiet -o "$dmg"

echo
echo "  $dmg  ($(du -h "$dmg" | cut -f1))"
