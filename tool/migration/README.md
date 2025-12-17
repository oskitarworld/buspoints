# Migración de POIs (pdis)

Este directorio contiene scripts para migrar los POIs desde los archivos KML en `assets/pdis` a Firestore con campos normalizados (`slug`, `category`, `position`, `name`, `description`, ...). También hay un script seguro para borrar la colección antigua en lotes una vez verificado el resultado.

Resumen del flujo recomendado

1. Hacer backup de la colección `pdis` con `gcloud` o exportar con un script (no incluido aquí).
2. Ejecutar el script de migración para crear `pdis_v2` (no sobrescribe la colección original):

   - El script leerá todos los `.kml` en `assets/pdis` y usará el nombre del archivo para inferir la `category`.
   - Crea documentos con `slug` sanitizado (solo letras, números, `-` y `_`).
   - Usa escrituras en batch (<= 500 operaciones) y espera entre batches para no golpear límites.

3. Verificar en la consola de Firestore que `pdis_v2` contiene los documentos con el formato esperado.
4. (Opcional) Cuando todo esté validado, puedes ejecutar el script `delete_collection.js` apuntando a la colección `pdis` para eliminarla en lotes.

Prerequisitos

- Node.js 16+ y npm
- Tener la clave del service account con permisos de Firestore (archivo JSON). En tu repo hay un archivo de ejemplo en `tool/buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json` — puedes usarlo si corresponde.

Instalación de dependencias

```bash
cd tool/migration
npm install
```

Ejecutar migración (ejemplo)

```bash
# Exporta la ruta a la key del service account o pásala como argumento
export GOOGLE_APPLICATION_CREDENTIALS="/ruta/a/buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json"
node migrate_pdis_from_kml.js --project buspoint-49ea0
```

Parámetros importantes

- --project: ID del proyecto (opcional si tu JSON contiene el project_id)
- --source-dir: ruta a los KML (por defecto `../../assets/pdis` desde el directorio del script)
- --target-collection: colección destino (por defecto `pdis_v2`)

Ejecutar borrado en lotes (opcional y destructivo)

```bash
# Borra la colección original pdis en lotes de 500
node delete_collection.js --project buspoint-49ea0 --collection pdis
```

Advertencias

- No borres la colección original hasta comprobar que la migración a `pdis_v2` está correcta.
- Revisa las reglas de Firestore y las credenciales. Estos scripts usan el Admin SDK con privilegios.
- Si tus POIs vienen en otro formato distinto a KML (p. ej. CSV o JSON), el script es fácil de adaptar.

Si quieres, puedo adaptar el script para leer un JSON/CSV específico que tengas con datos canonizados en vez de los KML.

## Copiar documentos existentes de `pdis` a `pdis_v2`

Si prefieres migrar los documentos ya existentes en Firestore (colección `pdis`) en vez de re-parsar los KML, hay un script adicional `copy_pdis_to_pdis_v2.js` que hace exactamente eso: lee por lotes `pdis`, normaliza `slug` y `category` y escribe en `pdis_v2` usando el `slug` como ID.

Ejemplos:

  # Dry-run (no escribe)
  npm run copy -- --serviceAccount ../tool/buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json --dryRun

  # Ejecutar copia real (escribe en pdis_v2)
  npm run copy -- --serviceAccount ../tool/buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json

El script añade campos `migrated_from` y `migrated_at` para trazabilidad.
