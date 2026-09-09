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
# Sans espace : GitHub les remplace par des points dans le nom d'un asset,
# et « Lux.Vox.0.1.0.dmg » se lit mal dans une page de release.
dmg="$racine/Apps/LuxVox-$version.dmg"

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
scene="$(mktemp -d)"
trap 'rm -rf "$scene"' EXIT
cp -R "$app" "$scene/"
ln -s /Applications "$scene/Applications"

mkdir -p "$racine/Apps"
hdiutil create -volname "Lux Vox" -srcfolder "$scene" -ov -format UDZO -quiet "$dmg"

echo
echo "  $dmg  ($(du -h "$dmg" | cut -f1))"
echo
echo "Ensuite :"
echo "  git tag -a v$version -m \"Lux Vox $version\" && git push origin v$version"
echo "  puis la release sur https://github.com/Ashuraz91z/LuxVox/releases/new"
