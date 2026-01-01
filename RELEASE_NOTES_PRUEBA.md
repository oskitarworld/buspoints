Release notes - Prueba rápida

Fecha: 17 de diciembre de 2025
Versión: prueba-local (no publicada)

Resumen corto (qué cambiará al probar):

- Prevención de logins concurrentes: ahora el inicio de sesión intenta registrar la sesión por dispositivo. Si detecta intentos desde otro dispositivo, incrementa `suspiciousAttempts`.
- Bloqueo automático: tras 3 intentos "sospechosos" la cuenta pasa a estado `cancelled`. Esto es irreversible por el usuario; un admin puede reactivar la cuenta desde el panel de administración.
- Monitor server-side (Cloud Functions): hay una función en `functions/` que monitorea `suspiciousAttempts` y notifica a administradores cuando se alcanza el umbral (archivo presente en el repo, pendiente despliegue).
- UI Admin: nueva pantalla "Eventos de seguridad" para ver cuentas bloqueadas/sospechosas y reactivarlas.
- Drawer corregido: se reemplazó el Drawer corrupto, se quitó la insignia roja numérica y se añadió un diálogo de desglose para admins.
- Enviados (push): la pantalla de "Enviados (push)" ahora usa una función callable (`getAdminPushes`) para evitar errores de reglas de Firestore.

Instrucciones rápidas para generar un APK de prueba (macOS)

A) APK de debug (recomendado para pruebas rápidas)
- Genera un APK de debug (firmado con la clave de debug del SDK, listo para instalar en dispositivos de prueba):

```bash
# desde la raíz del proyecto
flutter pub get
flutter clean
flutter build apk --debug
```

- Resultado: `build/app/outputs/flutter-apk/app-debug.apk` — instálalo con `adb`:

```bash
# conectar el dispositivo por USB o usar emulador
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

B) APK de release sin firmar (si necesitas un APK release no firmado)
- Si prefieres un APK de release sin firmar (útil para firmarlo después fuera del proyecto), usa gradle assembleRelease:

```bash
# desde la carpeta android
cd android
./gradlew assembleRelease
```

- Resultado típico: `android/app/build/outputs/apk/release/app-release-unsigned.apk`
- Puedes instalarlo en un dispositivo (si el APK no está firmado algunas instalaciones pueden fallar; en general para instalar en Android debes firmarlo o usar `adb install` con permisos de desarrollador):

```bash
adb install -r android/app/build/outputs/apk/release/app-release-unsigned.apk
```

Notas y requisitos
- Asegúrate de tener instalado y configurado Flutter, Android SDK y `adb` en macOS.
- Si aparecen errores de Gradle / Kotlin (después de las modificaciones en el repo), ejecuta:

```bash
# detener daemons y limpiar caches (macOS)
./gradlew --stop
rm -rf ~/.gradle/caches/
rm -rf $HOME/.gradle/daemon/
# opcional: limpiar kotlin-dsl cache (si existe)
rm -rf ~/.kotlin-dsl/
```

- Para usar la función callable `getAdminPushes` y el monitor, debes desplegar las Cloud Functions desde la carpeta `functions/` con tu `firebase` CLI:

```bash
cd functions
npm install
firebase deploy --only functions
```

Si quieres, preparo ahora un pequeño script `scripts/build_debug_apk.sh` y lo añado al repo para ejecutarlo localmente, y/o genero el archivo `app-release-unsigned.apk` vía gradle modificando temporalmente la configuración de signing (te explico paso a paso).