#!/usr/bin/env bash
# Gera o APK de release para a maquininha Stone.
#
#   tool/build.sh                 # APK universal ARM (armeabi-v7a + arm64-v8a)
#   tool/build.sh --loja minhaloja # já sai apontado para a loja
#
# Variáveis opcionais (viram --dart-define): MOBIZ_DOMAIN, MOBIZ_STORE,
# MOBIZ_SUPPORT_NAME, MOBIZ_SUPPORT_PHONE, MOBIZ_SUPPORT_EMAIL, MOBIZ_SUPPORT_SITE.
set -euo pipefail
cd "$(dirname "$0")/.."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --loja) MOBIZ_STORE="$2"; shift 2 ;;
    *) echo "Opção desconhecida: $1" >&2; exit 2 ;;
  esac
done

VERSION="$(grep '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')"
DEFINES=(--dart-define="MOBIZ_APP_VERSION=${VERSION}")
for var in MOBIZ_DOMAIN MOBIZ_STORE MOBIZ_SUPPORT_NAME MOBIZ_SUPPORT_PHONE MOBIZ_SUPPORT_EMAIL MOBIZ_SUPPORT_SITE; do
  if [[ -n "${!var:-}" ]]; then DEFINES+=(--dart-define="${var}=${!var}"); fi
done

flutter pub get
flutter analyze
flutter test

# Só ARM: os terminais Stone não usam x86. Os símbolos de depuração ficam
# fora do APK (build/symbols) — guarde-os para ler stack traces de produção.
flutter build apk --release \
  --target-platform android-arm,android-arm64 \
  --split-debug-info=build/symbols \
  "${DEFINES[@]}"

APK=build/app/outputs/flutter-apk/app-release.apk
tool/check-apk.sh "$APK"
echo
echo "APK pronto: $APK"
