#!/usr/bin/env bash
set -euo pipefail

# Script para construir un APK debug de Flutter y, si hay dispositivos conectados,
# instalarlo automáticamente vía adb.
# Uso:
#   ./scripts/build_debug_apk_and_install.sh
# Requisitos:
# - Flutter SDK en PATH
# - Android SDK + adb en PATH
# - Dispositivo Android con depuración USB habilitada y conectado, o un emulador

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Ejecutando: flutter pub get"
flutter pub get

echo "==> Construyendo APK (debug)..."
flutter build apk --debug

APK_PATH="$ROOT_DIR/build/app/outputs/flutter-apk/app-debug.apk"

if [ ! -f "$APK_PATH" ]; then
  echo "ERROR: APK no encontrado en: $APK_PATH"
  echo "Revisa la salida del build o ejecuta 'flutter build apk --debug' manualmente."
  exit 1
fi

echo "APK generado en: $APK_PATH"

echo "==> Intentando instalar en dispositivos conectados (via adb)..."
if ! command -v adb >/dev/null 2>&1; then
  echo "adb no encontrado en PATH. Puedes instalar el APK manualmente con:\n  adb install -r $APK_PATH\nO usar: flutter install --debug"
  exit 0
fi

# Listar dispositivos (omitir la cabecera)
DEVICES=$(adb devices | sed '1d' | awk '{print $1}' | grep -v '^$' || true)

if [ -z "$DEVICES" ]; then
  echo "No se han detectado dispositivos adb. Puedes conectar uno o usar 'flutter install --debug'."
  exit 0
fi

for d in $DEVICES; do
  echo "Instalando en: $d"
  adb -s "$d" install -r "$APK_PATH" && echo "Instalado en $d" || echo "Fallo al instalar en $d"
done

echo "Listo."
