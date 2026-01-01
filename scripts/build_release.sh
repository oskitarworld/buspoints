#!/usr/bin/env bash
# build_release.sh
# Simple helper to build a signed AAB (recommended) or APK for Play Store.
# Usage:
#   ./scripts/build_release.sh           # build AAB (default)
#   ./scripts/build_release.sh aab       # build AAB (same as default)
#   ./scripts/build_release.sh apk       # build release APK
#
# Requirements:
# - A keystore configured in android/key.properties (or use env vars below)
# - Flutter and Android SDK in PATH
# - Run from the repo root (where pubspec.yaml sits)

set -euo pipefail
IFS=$'\n\t'

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# Read version from pubspec.yaml
PUBSPEC_VERSION_LINE=$(grep "^version:" pubspec.yaml || true)
PUBSPEC_VERSION=$(echo "$PUBSPEC_VERSION_LINE" | awk '{print $2}' || true)
# Fallback
if [ -z "$PUBSPEC_VERSION" ]; then
  PUBSPEC_VERSION="unknown"
fi

TYPE="aab"
if [ $# -gt 0 ]; then
  TYPE="$1"
fi

echo "Building project at $PROJECT_ROOT"
echo "Version: $PUBSPEC_VERSION"
echo "Target: $TYPE"

# If key.properties is not present, attempt to create it from environment variables
# (useful for CI) or from macOS Keychain entries (local dev) when available.
if [ ! -f "android/key.properties" ]; then
  # Prefer explicit environment variables
  if [ -n "${KEYSTORE_PATH:-}" ] && [ -n "${KEYSTORE_PASSWORD:-}" ] && [ -n "${KEY_PASSWORD:-}" ] && [ -n "${KEY_ALIAS:-}" ]; then
    mkdir -p android
    cat > android/key.properties <<EOF
storePassword=${KEYSTORE_PASSWORD}
keyPassword=${KEY_PASSWORD}
keyAlias=${KEY_ALIAS}
storeFile=${KEYSTORE_PATH}
EOF
    echo "Created android/key.properties from environment variables."
  else
    # Try macOS Keychain (defaults)
    if [ "$(uname)" = "Darwin" ] && command -v security >/dev/null 2>&1; then
      # Default keychain item names (you can change these before running):
      STORE_ITEM_NAME="buspoints_storePassword"
      KEY_ITEM_NAME="buspoints_keyPassword"
      # Only attempt if KEYSTORE_PATH env var exists (path to .jks)
      if [ -n "${KEYSTORE_PATH:-}" ]; then
        STORE_PASS=""
        KEY_PASS=""
        if security find-generic-password -s "$STORE_ITEM_NAME" -w >/dev/null 2>&1; then
          STORE_PASS=$(security find-generic-password -s "$STORE_ITEM_NAME" -w)
        fi
        if security find-generic-password -s "$KEY_ITEM_NAME" -w >/dev/null 2>&1; then
          KEY_PASS=$(security find-generic-password -s "$KEY_ITEM_NAME" -w)
        fi
        if [ -n "$STORE_PASS" ] && [ -n "$KEY_PASS" ]; then
          mkdir -p android
          cat > android/key.properties <<EOF
storePassword=${STORE_PASS}
keyPassword=${KEY_PASS}
keyAlias=${KEY_ALIAS:-buspoints-upload}
storeFile=${KEYSTORE_PATH}
EOF
          echo "Created android/key.properties from macOS Keychain entries ($STORE_ITEM_NAME / $KEY_ITEM_NAME)."
        else
          echo "WARNING: android/key.properties not found and no KEYSTORE_* env vars or Keychain entries available."
          echo "You can create it with (example):"
          echo "  cat > android/key.properties <<EOF\nstorePassword=YOUR_STORE_PASSWORD\nkeyPassword=YOUR_KEY_PASSWORD\nkeyAlias=your-key-alias\nstoreFile=/absolute/path/to/your.jks\nEOF"
          sleep 2
        fi
      else
        echo "WARNING: android/key.properties not found. Set KEYSTORE_PATH and KEYSTORE_PASSWORD/KEY_PASSWORD/KEY_ALIAS env vars or create android/key.properties manually."
        echo "You can create it with (example):"
        echo "  cat > android/key.properties <<EOF\nstorePassword=YOUR_STORE_PASSWORD\nkeyPassword=YOUR_KEY_PASSWORD\nkeyAlias=your-key-alias\nstoreFile=/absolute/path/to/your.jks\nEOF"
        sleep 2
      fi
    else
      echo "WARNING: android/key.properties not found. Make sure you have a keystore and key.properties configured."
      echo "You can create it with (example):"
      echo "  cat > android/key.properties <<EOF\nstorePassword=YOUR_STORE_PASSWORD\nkeyPassword=YOUR_KEY_PASSWORD\nkeyAlias=your-key-alias\nstoreFile=/absolute/path/to/your.jks\nEOF"
      sleep 2
    fi
  fi
fi

# Clean + pub get
echo "Cleaning and fetching dependencies..."
flutter clean
flutter pub get

if [ "$TYPE" = "aab" ] || [ "$TYPE" = "bundle" ]; then
  echo "Building app bundle (AAB)..."
  flutter build appbundle --release
  SRC="build/app/outputs/bundle/release/app-release.aab"
  if [ ! -f "$SRC" ]; then
    echo "ERROR: AAB not found at $SRC"
    exit 1
  fi
  mkdir -p release
  OUT="release/buspoints-${PUBSPEC_VERSION}.aab"
  cp "$SRC" "$OUT"
  echo "AAB created: $OUT"
elif [ "$TYPE" = "apk" ]; then
  echo "Building release APK..."
  flutter build apk --release
  SRC="build/app/outputs/flutter-apk/app-release.apk"
  if [ ! -f "$SRC" ]; then
    echo "ERROR: APK not found at $SRC"
    exit 1
  fi
  mkdir -p release
  OUT="release/buspoints-${PUBSPEC_VERSION}.apk"
  cp "$SRC" "$OUT"
  echo "APK created: $OUT"
  # Try to verify APK signature with apksigner if available
  APKSIGNER_TOOL=""
  if command -v apksigner >/dev/null 2>&1; then
    APKSIGNER_TOOL="$(command -v apksigner)"
  else
    # try to locate SDK build-tools
    if [ -n "${ANDROID_SDK_ROOT:-}" ]; then
      BT_DIR=$(ls -1d "$ANDROID_SDK_ROOT"/build-tools/* 2>/dev/null | sort -V | tail -n1 || true)
      if [ -n "$BT_DIR" ] && [ -f "$BT_DIR/apksigner" ]; then
        APKSIGNER_TOOL="$BT_DIR/apksigner"
      fi
    fi
    if [ -z "$APKSIGNER_TOOL" ] && [ -n "${ANDROID_HOME:-}" ]; then
      BT_DIR=$(ls -1d "$ANDROID_HOME"/build-tools/* 2>/dev/null | sort -V | tail -n1 || true)
      if [ -n "$BT_DIR" ] && [ -f "$BT_DIR/apksigner" ]; then
        APKSIGNER_TOOL="$BT_DIR/apksigner"
      fi
    fi
  fi

  if [ -n "$APKSIGNER_TOOL" ]; then
    echo "Verifying APK signature with: $APKSIGNER_TOOL"
    "$APKSIGNER_TOOL" verify --print-certs "$OUT" || echo "apksigner verify returned non-zero (check output above)"
  else
    echo "apksigner not found in PATH or ANDROID_SDK_ROOT/ANDROID_HOME; skipping APK signature verification."
  fi
else
  echo "Unknown build type: $TYPE"
  echo "Valid types: aab (default), apk"
  exit 1
fi

# Print final file size
echo "Result file:" $(ls -lh "$OUT")

echo "Done. Upload the AAB to Google Play Console (Internal/Production) or test the APK on a device."