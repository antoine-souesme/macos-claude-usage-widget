#!/bin/bash
# Compile l'application et fabrique le bundle ClaudeUsage.app dans build/.
# Option --install : copie ensuite le bundle dans /Applications.
#
# Le moteur de compilation « native » est imposé : sur une machine sans Xcode,
# le moteur par défaut de Swift 6.4 échoue à s'initialiser.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ClaudeUsage"
BUNDLE="build/${APP_NAME}.app"

echo "Compilation en mode release…"
swift build --build-system native -c release

echo "Fabrication du bundle…"
rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS"
cp Resources/Info.plist "${BUNDLE}/Contents/Info.plist"
cp ".build/release/${APP_NAME}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"

# Signature locale : sans elle, le trousseau redemande l'autorisation à chaque
# reconstruction, car l'identité de l'application change.
codesign --force --deep --sign - "$BUNDLE"

echo "Bundle prêt : ${BUNDLE}"

if [[ "${1:-}" == "--install" ]]; then
    echo "Installation dans /Applications…"
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "$BUNDLE" /Applications/
    echo "Installé : /Applications/${APP_NAME}.app"
fi
