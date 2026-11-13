#!/usr/bin/env bash
# Instala o APK na maquininha de desenvolvimento conectada por USB e abre o app.
#
#   tool/deploy.sh            # instala o último build
#   tool/deploy.sh --logs     # instala e fica mostrando os logs do app
set -euo pipefail
cd "$(dirname "$0")/.."
APK=build/app/outputs/flutter-apk/app-release.apk
PKG=br.com.mobizweb.pos
[[ -f "$APK" ]] || { echo "Rode tool/build.sh antes." >&2; exit 2; }

adb devices -l
adb install -r "$APK"
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
echo "Instalado e aberto: $PKG"
if [[ "${1:-}" == "--logs" ]]; then
  adb logcat --pid="$(adb shell pidof -s "$PKG")"
fi
