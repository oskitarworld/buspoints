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
