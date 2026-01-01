#!/usr/bin/env bash
# Deploy Firestore indexes from firestore.indexes.json
# Usage: ./scripts/deploy_firestore_indexes.sh <PROJECT_ID>
# Example: ./scripts/deploy_firestore_indexes.sh buspoint-123

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <FIREBASE_PROJECT_ID_OR_ALIAS>"
  exit 1
fi
PROJECT="$1"

# Ensure firebase-tools is available
if ! command -v firebase >/dev/null 2>&1; then
  echo "firebase CLI not found. Installing globally via npm..."
  npm install -g firebase-tools
fi

echo "Deploying Firestore indexes to project: $PROJECT"
# Ensure we're in the repo root
cd "$(dirname "$0")/.."

# Optional: show the file and ask for confirmation
if [ ! -f firestore.indexes.json ]; then
  echo "firestore.indexes.json not found in $(pwd). Make sure you run this from the repo root."
  exit 1
fi

echo "Using firestore.indexes.json:" 
jq . firestore.indexes.json || true

echo "You will be prompted to login if required."

firebase login --no-localhost || true
firebase deploy --only firestore:indexes --project "$PROJECT"

echo "Deploy command completed. Check Firebase Console → Firestore → Indexes to monitor build progress."