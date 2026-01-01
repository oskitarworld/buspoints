# Firebase Functions for Buspoints

## Notificaciones push a admins por reviews pendientes

Esta función envía una notificación push a los administradores cada vez que un usuario deja una review/comentario con status 'pending' en cualquier PDI.

- Trigger: Firestore (onCreate) sobre cualquier subcolección `reviews` bajo `pdis_v2/{pdiId}/reviews`.
- Acción: Envía notificación push al topic 'admins' con los datos del review pendiente.

## Ejemplo de función:

```js
exports.notifyAdminsOnPendingReview = functions.firestore
  .document('pdis_v2/{pdiId}/reviews/{reviewId}')
  .onCreate(async (snap, context) => {
    // ...
  });
```

## Requisitos
- Los administradores deben estar suscritos al topic 'admins' en FCM.
- El campo 'status' del review debe ser 'pending' al crearse.

## Recordatorios por usuario con Cloud Tasks (Madrid)

Se ha añadido soporte para programar un recordatorio único por usuario exactamente 7 días después de su `createdAt` si el usuario queda en estado `pending`. Esto usa Cloud Tasks y un handler HTTPS seguro `pendingReminderHandler`.

Pasos rápidos (CLI):

1) Crear la cola (región: Madrid):

```bash
gcloud tasks queues create buspoints-reminders-queue --location=europe-southwest1
```

2) Dar permisos a la cuenta de servicio:

```bash
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member=serviceAccount:YOUR_PROJECT_ID@appspot.gserviceaccount.com \
  --role=roles/cloudtasks.enqueuer
```

3) Configurar variables runtime (SMTP + settings de Tasks):

```bash
firebase functions:config:set \
  smtp.email="mi@correo.com" \
  smtp.password="SECRET_SMTP_PASSWORD" \
  smtp.host="mail.buspoints.net" \
  smtp.port="465" \
  smtp.secure="true" \
  tasks.queue="buspoints-reminders-queue" \
  tasks.location="europe-southwest1" \
  tasks.key="UNA_CLAVE_SECRETA_LARGA_PARA_HANDSHAKE"
```

4) Activar API Cloud Tasks (si no está activa):

```bash
gcloud services enable cloudtasks.googleapis.com
```

5) Desplegar funciones:

```bash
firebase deploy --only functions
```

Notas:
- `tasks.key` es usado por el handler para validar llamadas; la tarea debe incluir la cabecera `x-buspoints-task-secret`.
- Si tu flujo de registro no establece `createdAt` en el mismo momento, la función usará la hora actual como fallback (puede desplazar la programación unos segundos).

