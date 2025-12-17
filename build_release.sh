#!/usr/bin/env bash
set -euo pipefail

# Script de ayuda para crear builds de release (AAB y APK).
# Uso: ./build_release.sh [aab|apk|apk-arm64]

CMD=${1:-aab}

echo "Limpiando proyecto..."
flutter clean
flutter pub get

if [ "$CMD" = "aab" ]; then
  echo "Construyendo appbundle (AAB)..."
  flutter build appbundle --release
  echo "AAB generado: build/app/outputs/bundle/release/app-release.aab"
elif [ "$CMD" = "apk" ]; then
  echo "Construyendo APK monolítico (todas las ABIs)..."
  flutter build apk --release
  echo "APK generado: build/app/outputs/flutter-apk/app-release.apk"
elif [ "$CMD" = "apk-arm64" ]; then
  echo "Construyendo APK arm64-v8a..."
  flutter build apk --target-platform=android-arm64 --split-per-abi
  echo "APKs generados: build/app/outputs/flutter-apk/"
else
  echo "Comando desconocido: $CMD"
  echo "Opciones: aab | apk | apk-arm64"
  exit 2
fi


echo "Done."
