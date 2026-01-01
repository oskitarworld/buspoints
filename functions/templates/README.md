Uso de plantillas de correo (Mustache)

Esta carpeta contiene las plantillas HTML y TXT para los correos que envía BusPoints.

Archivos esperados (ya presentes):
- welcome.html
- welcome.txt
- pending_reminder.html
- pending_reminder.txt
- subscription_confirmed.html
- subscription_confirmed.txt

Helper de renderizado
- `index.js` exporta `render(name, view)`.
  - name: el prefijo del fichero de plantilla (por ejemplo `welcome`, `pending_reminder`, `subscription_confirmed`).
  - view: objeto que contiene las variables de Mustache (por ejemplo: `{ name: 'Usuario', isTrial: true, trialExpiry: '...' }`).
  - devuelve `{ html, text }` con las plantillas renderizadas (o `null` si no existe la variante).

Ejemplo de uso desde `functions/index.js`:

```js
const templates = require('./templates'); // path relativo desde functions/index.js

const view = { name: 'Usuario', isTrial: true, trialExpiry: '1 enero 2026' };
const rendered = templates.render('welcome', view);

const mailOptions = {
  from: smtpEmail,
  to: userEmail,
  subject: 'Bienvenido a BusPoints',
  text: rendered.text || 'Texto fallback',
  html: rendered.html || ('<pre>' + (rendered.text || '') + '</pre>')
};

await transporter.sendMail(mailOptions);
```

Notas:
- Guarda una versión en texto plano (`*.txt`) como fallback para clientes que no aceptan HTML.
- Usa variables Mustache (`{{name}}`, `{{#isTrial}}...{{/isTrial}}`) para manejar condicionales simples.
- Si necesitas i18n, crea subcarpetas `es/` y `en/` o usa convenciones `welcome_es.html` / `welcome_en.html` y selecciona la plantilla según `user.locale`.

Buenas prácticas:
- Mantén CSS simple y en línea dentro del HTML.
- No incluyas JavaScript en emails.
- Prueba en clientes reales (Gmail, Outlook, móviles) antes de enviar a producción.
