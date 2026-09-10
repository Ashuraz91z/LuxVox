#!/bin/bash
#
# Fabrique le DMG d'une version.
#
#     Scripts/release.sh 0.1.0
#
# Ne touche ni à git ni à GitHub : le tag et la release restent des gestes
# délibérés. Le script ne fait que ce qui doit être reproductible — la version
# inscrite dans le bundle, la compilation Release, l'empaquetage.
#
set -euo pipefail

version="${1:-}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "usage : Scripts/release.sh <version>   (ex. 0.1.0)" >&2
    exit 1
fi

racine="$(cd "$(dirname "$0")/.." && pwd)"
cd "$racine"

# Une version se fabrique à partir d'un état versionné, sinon le tag ne
# désigne pas ce qu'on distribue.
if [[ -n "$(git status --porcelain)" ]]; then
    echo "erreur : des modifications ne sont pas commitées." >&2
    git status --short >&2
    exit 1
fi

# Build isolé : ne pas écraser les produits Debug d'Xcode, dont le codesign
# échoue si l'app tourne.
build="$racine/.build/release"
app="$build/Build/Products/Release/Lux Vox.app"
# Ni espace ni tiret. L'espace, GitHub le remplace par un point, et
# « Lux.Vox.1.0.0.dmg » se lit mal dans une page de release. Le tiret, lui,
# ne survit pas à tous les chemins par lesquels un fichier peut arriver
# jusqu'au téléversement — la 0.2.0 et la 1.0.0 sont toutes deux publiées
# sans lui, alors que le script le mettait. Un nom qui change en route est un
# lien mort sur le site, et personne ne le voit avant que quelqu'un clique.
dmg="$racine/Apps/LuxVox$version.dmg"

echo "▸ version $version"
xcodebuild -project "Lux Vox.xcodeproj" -scheme "Lux Vox" -configuration Release \
    -derivedDataPath "$build" \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$(git rev-list --count HEAD)" \
    build > /dev/null

echo "▸ signature"
codesign --verify --deep --strict "$app"
codesign -dvvv "$app" 2>&1 | grep '^Authority' | head -1

echo "▸ empaquetage"
# La mise en scène de la fenêtre vit dans son propre script : refaire le fond
# du DMG ne devrait pas coûter une compilation Release.
"$racine/Scripts/dmg.sh" "$app" "$dmg"

echo "Ensuite :"
echo "  git tag -a v$version -m \"Lux Vox $version\" && git push origin v$version"
echo "  puis la release sur https://github.com/Ashuraz91z/LuxVox/releases/new"
echo
# Depuis 0.3, l'app se met à jour toute seule en lisant cette liste de
# releases. Ce ne sont donc plus des conventions de rangement : ce sont les
# deux conditions pour qu'une version existe aux yeux des utilisateurs.
echo "  L'app lit cette liste pour se mettre à jour. Donc :"
echo "    · l'étiquette doit être un numéro (v$version ou $version), rien d'autre ;"
echo "    · le .dmg doit être attaché à la release, sinon elle est ignorée."
