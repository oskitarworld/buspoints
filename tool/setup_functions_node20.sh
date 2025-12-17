#!/usr/bin/env bash
# setup_functions_node20.sh
# Utility script to prepare the functions/ folder for Node 20, install deps and attempt to fix npm audit issues.
# Run this from the repo root: ./tool/setup_functions_node20.sh
# NOTE: This script will NOT deploy functions. It only prepares the local functions environment.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FUNCTIONS_DIR="$REPO_ROOT/functions"

echo "Repo root: $REPO_ROOT"

# Detect shell profile file to source nvm (zsh or bash)
PROFILE_FILES=("$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile")
NVM_INIT=""
for f in "${PROFILE_FILES[@]}"; do
  if [ -f "$f" ]; then
    NVM_INIT="$f"
    break
  fi
done

# Install nvm if not present
if ! command -v nvm >/dev/null 2>&1; then
  echo "nvm not found. Installing nvm..."
  # Install nvm (official install script)
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
  # try to source nvm from typical locations
  if [ -f "$HOME/.nvm/nvm.sh" ]; then
    export NVM_DIR="$HOME/.nvm"
    # shellcheck source=/dev/null
    . "$HOME/.nvm/nvm.sh"
  elif [ -n "$NVM_INIT" ]; then
    # shellcheck source=/dev/null
    . "$NVM_INIT"
  fi
else
  echo "nvm is already installed"
  # ensure nvm is loaded in this shell
  if [ -s "$HOME/.nvm/nvm.sh" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.nvm/nvm.sh"
  fi
fi

# Ensure nvm is available now
if ! command -v nvm >/dev/null 2>&1; then
  echo "ERROR: nvm not found after install. Please source your shell profile or restart the shell and re-run this script." >&2
  exit 2
fi

# Install and use Node 20
NODE_VERSION=20
echo "Installing and using Node $NODE_VERSION (via nvm)..."
nvm install $NODE_VERSION
nvm use $NODE_VERSION

echo "Node version: $(node -v)"
echo "npm version: $(npm -v)"

# Enter functions dir
if [ ! -d "$FUNCTIONS_DIR" ]; then
  echo "ERROR: functions directory not found at $FUNCTIONS_DIR" >&2
  exit 3
fi
cd "$FUNCTIONS_DIR"

echo "Installing npm dependencies inside functions/ ..."
npm install

echo "Running 'npm audit' to detect vulnerabilities..."
npm audit --json > audit-result.json || true

echo "Saved audit result to functions/audit-result.json"

# Try automatic audit fix
echo "Attempting 'npm audit fix'..."
npm audit fix || true

# Re-run audit
npm audit --json > audit-after-fix.json || true

echo "Audit after fix saved to functions/audit-after-fix.json"

# Helpful guidance if protobufjs appears in the audit
if grep -q "protobufjs" audit-after-fix.json 2>/dev/null || grep -q "protobufjs" audit-result.json 2>/dev/null; then
  echo "\nDetected 'protobufjs' in audit output. Common fixes:\n"
  echo "1) Try upgrading firebase-admin to the latest compatible version:\n   npm install firebase-admin@latest --save"
  echo "2) If that doesn't remove the advisory, consider adding an npm override in package.json, e.g. 'overrides': { 'protobufjs': 'X.Y.Z' } and then npm install. Use with caution."
fi

cat <<'EOF'

Done. Next recommended steps:
 - Inspect functions/audit-after-fix.json and decide whether to upgrade firebase-admin.
 - If you upgrade firebase-admin, run 'npm install' again and re-run 'npm audit'.
 - Test functions locally with the Firebase emulator before deploying:
     firebase emulators:start --only functions,firestore
 - When ready, deploy:
     firebase deploy --only functions

Remember: firebase deploy requires you to be authenticated (firebase login) and have the correct project selected (firebase use <project-id>).

EOF
