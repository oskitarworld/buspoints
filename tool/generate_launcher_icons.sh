#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
echo "Running flutter pub get..."
flutter pub get
echo "Generating launcher icons with flutter_launcher_icons..."
flutter pub run flutter_launcher_icons:main
echo "Done. You should rebuild the app to see the new icons (flutter clean && flutter run or flutter build apk)."