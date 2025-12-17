#!/usr/bin/env bash
# build_apk.sh - Utility to build a Flutter APK (debug or release)
# Usage:
#   ./tool/build_apk.sh debug
#   ./tool/build_apk.sh release
# Notes:
# - For a release build you must configure a keystore and `android/key.properties` (see below)
# - Run from the repository root.

set -euo pipefail
MODE=${1:-debug}
DO_INSTALL=false
if [ "${2:-}" = "install" ] || [ "${1:-}" = "install" ]; then
  DO_INSTALL=true
  # allow usage: ./tool/build_apk.sh install  or ./tool/build_apk.sh debug install
  if [ "${1:-}" = "install" ]; then
    MODE=debug
  else
    MODE=${1:-debug}
  fi
fi

echo "==> Starting APK build (mode: $MODE)"

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: 'flutter' command not found in PATH. Install Flutter and ensure it's on PATH." >&2
  exit 2
fi

echo "Running flutter pub get..."
flutter pub get

# Generate launcher icons so the native app uses `assets/images/logo_escritorio.png` as configured
if [ -x "$(pwd)/tool/generate_launcher_icons.sh" ]; then
  echo "Generating launcher icons..."
  ./tool/generate_launcher_icons.sh
else
  echo "generate_launcher_icons.sh not found or not executable; skipping icon generation"
fi

# Clean previous build artifacts to avoid stale outputs and reduce build issues
echo "Running flutter clean..."
flutter clean

if [ "$MODE" = "release" ]; then
  echo "Building release APK..."
  echo "Ensure you have configured android/key.properties and a keystore."
  flutter build apk --release
  echo "Release APK: build/app/outputs/flutter-apk/app-release.apk"
  echo "Optional smaller per-ABI APKs: flutter build apk --split-per-abi"
else
  echo "Building debug APK..."
  flutter build apk --debug
  echo "Debug APK: build/app/outputs/flutter-apk/app-debug.apk"
fi

if [ "$DO_INSTALL" = true ]; then
  APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
  if [ "$MODE" = "release" ]; then
    APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
  fi
  if ! command -v adb >/dev/null 2>&1; then
    echo "ERROR: 'adb' not found in PATH. Install Android Platform Tools and ensure 'adb' is available." >&2
    exit 2
  fi
  echo "Installing APK to connected device(s): $APK_PATH"
  adb devices
  adb install -r "$APK_PATH" && echo "APK instalado correctamente." || { echo "Error instalando APK."; exit 3; }
  echo "You can run: adb logcat -s flutter:V "
fi

if [ "$DO_INSTALL" = false ]; then
  echo "Done. To install on a connected device run (adb must be available):"
  if [ "$MODE" = "release" ]; then
    echo "  adb install -r build/app/outputs/flutter-apk/app-release.apk"
  else
    echo "  adb install -r build/app/outputs/flutter-apk/app-debug.apk"
  fi
fi

exit 0
