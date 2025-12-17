# Generar build de release (AAB / APK) — instrucciones

Este documento explica cómo crear un AAB firmado listo para subir al Play Console y cómo generar APKs de prueba.

1) Generar un keystore (si no tienes uno)

```bash
keytool -genkeypair -v \
  -keystore ~/keystore.jks \
  -storetype JKS \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias uploadkey
```

2) Crear `android/key.properties` desde la plantilla (NO subir este archivo a git)

- Copia `android/key.properties.template` a `android/key.properties` y rellena los campos:

```
storePassword=TU_STORE_PASSWORD
keyPassword=TU_KEY_PASSWORD
keyAlias=uploadkey
storeFile=/Users/<tu_usuario>/keystore.jks
```

3) Construir el App Bundle (recomendado para Play Store)

```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

El AAB se generará en `build/app/outputs/bundle/release/app-release.aab`.

4) Alternativa: build APK para pruebas

Monolítico (todos los ABIs, grande):

```bash
flutter build apk --release
```

Por ABI (más pequeño):

```bash
flutter build apk --target-platform=android-arm64 --split-per-abi
```

5) Versionado

Puedes actualizar la versión en `pubspec.yaml` (campo `version: x.y.z+build`) o pasar flags al build:

```bash
flutter build appbundle --release --build-name=1.0.1 --build-number=2
```

6) Notas y buenas prácticas

- No subas `android/key.properties` al repositorio.
- Usa la misma clave/alias para la subida a Play (upload key) o sigue el proceso de Google Play App Signing.
- Prueba la app en un dispositivo antes de publicar.
