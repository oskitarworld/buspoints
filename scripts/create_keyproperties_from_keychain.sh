#!/usr/bin/env bash
# create_keyproperties_from_keychain.sh
# Reads passwords from macOS Keychain (items named buspoints_storePassword and
# buspoints_keyPassword) and writes android/key.properties pointing to
# KEYSTORE_PATH. Useful for local dev where you stored the passwords in Keychain.

set -euo pipefail
IFS=$'\n\t'

if [ "$(uname)" != "Darwin" ]; then
  echo "This helper is for macOS only (uses security CLI)."
  exit 1
fi

if ! command -v security >/dev/null 2>&1; then
  echo "security CLI not found. This script requires macOS security command."
  exit 1
fi

if [ -z "${KEYSTORE_PATH:-}" ]; then
  echo "Please set KEYSTORE_PATH environment variable to the absolute path of your .jks file."
  echo "Example: export KEYSTORE_PATH=\"$HOME/keystores/buspoints-upload.jks\""
  exit 1
fi

STORE_ITEM_NAME="buspoints_storePassword"
KEY_ITEM_NAME="buspoints_keyPassword"

if ! security find-generic-password -s "$STORE_ITEM_NAME" -w >/dev/null 2>&1; then
  echo "Keychain item $STORE_ITEM_NAME not found. Store the store password first:"
  echo "  security add-generic-password -a \"$USER\" -s \"$STORE_ITEM_NAME\" -w \"YOUR_STORE_PASSWORD\""
  exit 1
fi

if ! security find-generic-password -s "$KEY_ITEM_NAME" -w >/dev/null 2>&1; then
  echo "Keychain item $KEY_ITEM_NAME not found. Store the key password first:"
  echo "  security add-generic-password -a \"$USER\" -s \"$KEY_ITEM_NAME\" -w \"YOUR_KEY_PASSWORD\""
  exit 1
fi

STORE_PASS=$(security find-generic-password -s "$STORE_ITEM_NAME" -w)
KEY_PASS=$(security find-generic-password -s "$KEY_ITEM_NAME" -w)

mkdir -p android
cat > android/key.properties <<EOF
storePassword=${STORE_PASS}
keyPassword=${KEY_PASS}
keyAlias=${KEY_ALIAS:-buspoints-upload}
storeFile=${KEYSTORE_PATH}
EOF

echo "android/key.properties created from Keychain entries."
