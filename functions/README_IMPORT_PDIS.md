Importar PDI desde KML a Firestore

Este script importa las Placemarks del archivo KML `assets/pdifull_icon/pdi_full.kml` a la colección `pdis` en Firestore.

Requisitos
- Node 20 (las funciones usan Node 20 en `package.json`)
- Un service account JSON con permisos para escribir en Firestore

Pasos rápidos (modo directo, escribe en Firestore)

1) Desde la carpeta `functions/` instala dependencias:

```bash
cd functions
npm install
```

2) Exporta la variable de entorno para las credenciales de servicio (zsh):

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/ruta/a/tu/service-account.json"
```

3) Ejecuta el import (escribirá directamente en `pdis`):

```bash
npm run import-pdis
```

Notas
- El script creará documentos con IDs automáticos en la colección `pdis`.
- Intenta extraer `name`, `description`, `Point` (coordenadas) y `ExtendedData` si existe.
- Si no ves el archivo KML en la ruta esperada, verifica `assets/pdifull_icon/pdi_full.kml`.

Si quieres un dry-run antes de escribir, pide explícitamente y puedo añadir esa opción.
