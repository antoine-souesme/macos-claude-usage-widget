#!/bin/bash
# Compile l'application et fabrique le bundle ClaudeUsage.app dans build/.
#
#   ./build.sh             construit le bundle
#   ./build.sh --install   construit puis copie le bundle dans /Applications
#   ./build.sh --zip       construit puis produit build/ClaudeUsage-X.Y.Z.zip
#
# Le moteur de compilation « native » est imposé : sur une machine sans Xcode,
# le moteur par défaut de Swift 6.4 échoue à s'initialiser.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ClaudeUsage"
BUNDLE="build/${APP_NAME}.app"

# La version vit dans Version.swift ; elle est recopiée dans l'Info.plist du
# bundle pour que macOS et la release affichent le même numéro.
VERSION=$(sed -n 's/^public let appVersion = "\(.*\)"$/\1/p' Sources/ClaudeUsageCore/Version.swift)
if [[ -z "$VERSION" ]]; then
    echo "Version introuvable dans Sources/ClaudeUsageCore/Version.swift" >&2
    exit 1
fi

echo "Compilation de la version ${VERSION} en mode release…"
swift build --build-system native -c release

echo "Fabrication du bundle…"
rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS"
sed "s/__VERSION__/${VERSION}/g" Resources/Info.plist > "${BUNDLE}/Contents/Info.plist"
cp ".build/release/${APP_NAME}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"

# Signature locale : sans elle, le trousseau redemande l'autorisation à chaque
# reconstruction, car l'identité de l'application change.
codesign --force --deep --sign - "$BUNDLE"

echo "Bundle prêt : ${BUNDLE}"

case "${1:-}" in
    --install)
        echo "Installation dans /Applications…"
        rm -rf "/Applications/${APP_NAME}.app"
        cp -R "$BUNDLE" /Applications/
        echo "Installé : /Applications/${APP_NAME}.app"
        ;;
    --zip)
        ARCHIVE="build/${APP_NAME}-${VERSION}.zip"
        rm -f "$ARCHIVE"
        # ditto préserve la structure du bundle, ce que `zip` ne garantit pas.
        ditto -c -k --keepParent "$BUNDLE" "$ARCHIVE"
        echo "Archive prête : ${ARCHIVE}"
        ;;
esac
