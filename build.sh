#!/usr/bin/env bash
# Compila e empacota o PodControl.app.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP="PodControl.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/PodControl "$APP/Contents/MacOS/PodControl"
cp Info.plist "$APP/Contents/Info.plist"
# Com um certificado "Apple Development" a identidade do app fica fixa e o macOS
# não pede as permissões de novo a cada build. Sem ele, cai na assinatura ad hoc.
IDENTIDADE=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/{print $2; exit}')
codesign --force --sign "${IDENTIDADE:--}" "$APP"
echo "Assinado com: ${IDENTIDADE:-ad hoc}"
echo "Pronto: $(pwd)/$APP"
