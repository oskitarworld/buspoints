#!/usr/bin/env bash
set -euo pipefail

# Script rápido para generar un APK de release SIN FIRMAR y copiarlo a build/output
# Uso: desde la raíz del proyecto
#   ./scripts/build_unsigned_apk.sh

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_DIR="$ROOT_DIR/android"
OUT_DIR="$ROOT_DIR/builds"

echo "Proyecto: $ROOT_DIR"
mkdir -p "$OUT_DIR"

echo "Limpiando build Gradle..."
cd "$ANDROID_DIR"
./gradlew clean || true

echo "Generando APK de release (sin firmar si no hay signingConfig)..."
# Produce: android/app/build/outputs/apk/release/app-release-unsigned.apk (o app-release.apk if hay signing)
./gradlew assembleRelease

SRC_APK="$ANDROID_DIR/app/build/outputs/apk/release/app-release-unsigned.apk"
if [ ! -f "$SRC_APK" ]; then
  # fallback: some setups produce app-release.apk
  SRC_APK="$ANDROID_DIR/app/build/outputs/apk/release/app-release.apk"
fi

if [ ! -f "$SRC_APK" ]; then
  echo "No se encontró APK de release generado. Revisa la salida de Gradle para errores." >&2
  exit 2
fi

DEST_APK="$OUT_DIR/app-release-unsigned-$(date +%Y%m%d%H%M%S).apk"
cp "$SRC_APK" "$DEST_APK"

echo "APK copiado a: $DEST_APK"

echo "Para instalar en un dispositivo conectado por USB ejecuta:" 
echo "  adb install -r $DEST_APK"

echo "Nota: si la instalación falla por firma, firma el APK o instala una versión debug con 'flutter build apk --debug'."

echo "Listo."