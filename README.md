# myapp

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:


For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Quick: build an APK for testing on Android

I added a helper script at `tool/build_apk.sh` that you can run from the repo root.

1) Debug APK (fast, unsigned debug build):

	 ./tool/build_apk.sh debug

	 Output: build/app/outputs/flutter-apk/app-debug.apk

2) Release APK (signed for production):

	 ./tool/build_apk.sh release

	 Output: build/app/outputs/flutter-apk/app-release.apk

Signing notes for release builds
- Create (or use) a Java keystore (example):

	keytool -genkey -v -keystore ~/my-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias my-key-alias

- Create `android/key.properties` (don't commit it) with:

	storePassword=<your-store-password>
	keyPassword=<your-key-password>
	keyAlias=my-key-alias
	storeFile=/absolute/path/to/my-release-key.jks

- `android/app/build.gradle` already contains a signingConfig template. If you need, adapt it to point to `key.properties`.

Install on a connected device

	adb install -r build/app/outputs/flutter-apk/app-debug.apk

Or for release APK:

	adb install -r build/app/outputs/flutter-apk/app-release.apk

If you prefer an AAB for Play Store upload:

	flutter build appbundle --release
