#!/usr/bin/env bash
# Confere o APK contra as regras de homologação da Stone que dá para checar
# por máquina: tamanho, permissões, packageName, versão, ABIs e assinatura.
#
#   tool/check-apk.sh [caminho-do-apk]
set -euo pipefail
APK="${1:-build/app/outputs/flutter-apk/app-release.apk}"
[[ -f "$APK" ]] || { echo "APK não encontrado: $APK" >&2; exit 2; }

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[[ -n "$SDK" ]] || { echo "Defina ANDROID_HOME." >&2; exit 2; }
BT="$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)"
FAIL=0
ok()   { echo "  OK    $*"; }
bad()  { echo "  FALHA $*"; FAIL=1; }
warn() { echo "  AVISO $*"; }

echo "Verificando $APK"

# 1. Tamanho: "O app pode ter no máximo 70MB".
BYTES=$(wc -c < "$APK")
MB=$(awk "BEGIN { printf \"%.1f\", $BYTES / 1048576 }")
if (( BYTES <= 70 * 1048576 )); then ok "tamanho ${MB} MB (limite 70 MB)"; else bad "tamanho ${MB} MB passa de 70 MB"; fi

BADGING="$("$BT/aapt2" dump badging "$APK")"

# 2. packageName / versão.
PKG=$(sed -n "s/^package: name='\([^']*\)'.*/\1/p" <<<"$BADGING")
VNAME=$(sed -n "s/^package:.* versionName='\([^']*\)'.*/\1/p" <<<"$BADGING")
VCODE=$(sed -n "s/^package:.* versionCode='\([^']*\)'.*/\1/p" <<<"$BADGING")
if [[ "$PKG" =~ ^br\.com\.[a-z0-9_]+(\.[a-z0-9_]+)+$ ]] && ! grep -qiE 'stone|pagseguro|cielo|getnet|sunmi|gertec|positivo|ingenico|tectoy|pax' <<<"$PKG"; then
  ok "packageName $PKG"
else
  bad "packageName $PKG fora da regra (br.com.<empresa>.<app>, sem adquirente/fabricante)"
fi
if [[ "$VNAME" =~ ^[0-9.]{1,12}$ ]]; then ok "versionName $VNAME / versionCode $VCODE"; else bad "versionName '$VNAME' deve ter só números e ponto (máx. 12)"; fi

# 3. Permissões: só as que o app declara de propósito.
ALLOWED='android.permission.INTERNET'
PERMS=$(sed -n "s/^uses-permission: name='\([^']*\)'.*/\1/p" <<<"$BADGING")
for p in $PERMS; do
  if grep -qx "$p" <<<"$ALLOWED" || [[ "$p" == "$PKG."* ]]; then ok "permissão $p"; else bad "permissão não prevista: $p (a Stone tem lista de proibidas)"; fi
done

# 4. SDKs e ABIs.
MIN=$(sed -n "s/^minSdkVersion:'\([0-9]*\)'.*/\1/p" <<<"$BADGING"); [[ -n "$MIN" ]] || MIN=$(sed -n "s/^sdkVersion:'\([0-9]*\)'.*/\1/p" <<<"$BADGING")
TARGET=$(sed -n "s/^targetSdkVersion:'\([0-9]*\)'.*/\1/p" <<<"$BADGING")
ok "minSdk $MIN / targetSdk $TARGET"
(( MIN > 23 )) && warn "a Stone documenta suporte mínimo a Android 6 (API 23); este build exige API $MIN — confirme os modelos do seu parque"
ABIS=$(unzip -Z1 "$APK" 'lib/*' | cut -d/ -f2 | sort -u | tr '\n' ' ')
if grep -q 'armeabi-v7a' <<<"$ABIS" && ! grep -q 'x86' <<<"$ABIS"; then ok "ABIs: $ABIS"; else bad "ABIs: $ABIS (esperado só ARM, incluindo armeabi-v7a)"; fi

# 5. Sem WebView/Play Services (proibidos no terminal).
if unzip -Z1 "$APK" | grep -qiE 'webview|com/google/android/gms'; then bad "o APK contém WebView ou Google Play Services"; else ok "sem WebView nem Google Play Services"; fi

# 6. Assinatura V1 + V2.
# (o apksigner só avalia a V1 quando se pede compatibilidade abaixo do Android 7)
SIG="$("$BT/apksigner" verify --verbose --print-certs --min-sdk-version 21 "$APK" 2>&1 || true)"
if grep -q 'Verified using v1 scheme (JAR signing): true' <<<"$SIG" && grep -q 'Verified using v2 scheme (APK Signature Scheme v2): true' <<<"$SIG"; then
  ok "assinatura V1 + V2"
else
  warn "assinatura sem V1+V2 (normal no build de teste; a homologação exige as duas — use android/key.properties)"
fi
if grep -q 'CN=Android Debug' <<<"$SIG"; then warn "assinado com a chave de DEBUG — serve para a maquininha de desenvolvimento, não para homologar"; fi

echo
if (( FAIL )); then echo "Há itens fora da regra."; exit 1; fi
echo "Tudo certo nos itens verificáveis. O que depende de roteiro (Fale Conosco, navegação, URLs) está em docs/stone.md."
