Firestore indexes
=================

Qué incluimos
- `firestore.indexes.json` contiene la definición de índices para desplegar con Firebase CLI.
- Actualmente incluye un índice para `collectionGroup: "reviews"` con `status` orden ascendente — esto es lo que la app necesita para la consulta `collectionGroup('reviews').where('status', ...)`.

Cómo desplegar (desde tu máquina)
1. Instala la CLI si no la tienes:

```bash
npm install -g firebase-tools
```

2. Inicia sesión (si no lo has hecho antes):

```bash
firebase login
```

3. Desde la raíz del repo, revisa el archivo y despliega los índices:

```bash
# (opcional) limpia o revisa
cat firestore.indexes.json

# desplegar (reemplaza <PROJECT_ID> por tu project id o alias)
firebase deploy --only firestore:indexes --project <PROJECT_ID>
```

4. En Firebase Console → Firestore → Indexes verás el índice en estado "Building" y después "Ready".

Nota
- El despliegue tarda unos minutos en construir el índice según el tamaño de los datos.
- Asegúrate de desplegar sobre el mismo proyecto que la app usa (`lib/firebase_options.dart` contiene el projectId usado por la app). Si la app apunta a otro proyecto, crea/selecciona ese proyecto en la CLI (`firebase use <alias>`).

Si necesitas ayuda, pega la salida del comando `firebase deploy --only firestore:indexes --project <PROJECT_ID>` y te ayudo a interpretar cualquier error.