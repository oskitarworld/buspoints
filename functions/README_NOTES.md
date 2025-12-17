Preparación para desplegar Cloud Functions

Este archivo explica pasos rápidos para preparar y desplegar las funciones desde la carpeta `functions/`.

1) Asegúrate de usar Node 20 (recomendado con nvm):

   nvm install 20
   nvm use 20

2) Instala dependencias:

   cd functions
   npm install

   Este repositorio incluye una entrada `overrides` en package.json para forzar una versión segura de `protobufjs`.

3) Ejecuta audit y aplica correcciones automáticas:

   npm audit
   npm audit fix

   Revisa `audit-after-fix.json` si existe para ver qué queda pendiente.

4) Probar localmente con emuladores (recomendado):

   firebase emulators:start --only functions,firestore

5) Desplegar (una vez validado):

   firebase login
   firebase use buspoint-49ea0
   firebase deploy --only functions

Notas:
- Si `npm install` falla por incompatibilidad de engine, revisa que `node -v` muestre v20.x.
- Si la auditoría sigue mostrando vulnerabilidades relacionadas con `protobufjs`, puedes intentar actualizar `firebase-admin` (p. ej. `npm install firebase-admin@latest --save`), luego repetir `npm install` y `npm audit`.
- Siempre prueba con los emuladores antes de desplegar en producción.

Update applied in repo:

- The dependency `firebase-admin` in `functions/package.json` has been updated to `^14.0.0` to try to pull transitive fixes for protobufjs-related advisories. After running `npm install` you should re-run `npm audit` and verify whether the advisory is resolved.

If you see any errors when running `npm install`, paste the terminal output here and I will help you triage them.
