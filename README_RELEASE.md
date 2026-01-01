Release guide — Buspoints

This document explains how to create a signed Android App Bundle (AAB) or APK ready to upload to Google Play.

1) Generate an upload keystore (if you don't have one)

  mkdir -p ~/keystores
  keytool -genkey -v -keystore ~/keystores/buspoints-upload.jks -keyalg RSA -keysize 2048 -validity 9125 -alias buspoints-upload

  Keep the keystore and passwords safe. DO NOT commit the keystore to Git.

2) Create `android/key.properties`

  Create the file `android/key.properties` at the project root. Example:

  storePassword=YOUR_STORE_PASSWORD
  keyPassword=YOUR_KEY_PASSWORD
  keyAlias=buspoints-upload
  storeFile=/absolute/path/to/buspoints-upload.jks

  Use absolute path for `storeFile`.

3) Update version in `pubspec.yaml`

  Bump version and build number before each Play release.
  Example:

  version: 1.0.3+5

  The number after `+` is the Android `versionCode`.

4) Build using the helper script

  Make the script executable once:

  chmod +x scripts/build_release.sh

  Build AAB (recommended):

  ./scripts/build_release.sh

  Build APK (alternative):

  ./scripts/build_release.sh apk

  The artifact will be copied to `release/buspoints-<version>.aab` or `.apk`.

5) Verify APK signature (automated by the script for APKs)

  If you built an APK, the script will try to run `apksigner verify --print-certs` (from Android SDK build-tools) to display the certificate details. If apksigner is not found, install Android SDK build-tools and add them to PATH.

6) Test on a device

  # Install and replace existing app
  adb install -r release/buspoints-<version>.apk

  # Or run directly
  flutter run -d <device-id>

7) Upload to Google Play

  - Open Google Play Console -> App -> Release -> Create new release
  - Upload the AAB (recommended) or APK
  - Fill the release notes and follow the console steps (target & rollout)

Notes & best practices

- Use Play App Signing: generate an upload key (your keystore) and upload the AAB signed by your upload key. Google will re-sign the app with the app signing key.
- Keep the keystore and passwords in a secure vault. In CI, store them as secrets and do not write them to the repo.
- If you lose the upload key you can request Play to reset it; avoid this by keeping it safe.

Troubleshooting

- "versionCode must be > previous": increment the `+buildNumber` in `pubspec.yaml`.
- "Signing config not found": ensure `android/key.properties` exists and `android/app/build.gradle` reads it (standard Flutter template does).

If you want, I can also:
- Add CI configuration to build signed bundles using GitHub Actions.
- Add automatic uploading to Play Internal Testing using `google-play-deploy` action or `fastlane`.
