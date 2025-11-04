# Blueprint: Geo-PDI Comunitario

## Visión General

Esta aplicación es una herramienta de mapeo colaborativo diseñada para que una comunidad de usuarios pueda registrar, visualizar y gestionar Puntos de Interés (PDI) geolocalizados. La aplicación cuenta con un sistema de roles (usuarios y administradores) para la gestión y aprobación de los PDI enviados, asegurando la calidad y relevancia de los datos.

## Estilo y Diseño

*   **Tema:** La aplicación utiliza un tema moderno y limpio basado en Material 3.
    *   **Paleta de Colores:** Basada en un color semilla primario (rojo), generando esquemas de color coherentes para los modos claro y oscuro (`ColorScheme.fromSeed`).
    *   **Tipografía:** Usa una combinación de fuentes de Google Fonts para una jerarquía visual clara y legible:
        *   **Títulos/Encabezados:** `Oswald` (negrita).
        *   **Cuerpo de Texto/General:** `Roboto` y `Open Sans`.
    *   **Componentes:** Los estilos de widgets comunes como `AppBar` y `ElevatedButton` están centralizados y personalizados en el fichero `app_theme.dart` para garantizar la consistencia.

## Características Implementadas

### Módulo de Autenticación
*   Registro y Login de usuarios mediante correo electrónico y contraseña (Firebase Auth).
*   Formularios de entrada con validación en tiempo real.
*   Indicadores de carga durante las operaciones asíncronas.
*   Mecanismo de cierre de sesión seguro con diálogo de confirmación.

### Módulo de Mapa (Core)
*   Visualización de mapa interactivo (Google Maps).
*   Marcadores personalizados para representar los diferentes tipos de PDI.
*   Agrupación de marcadores (`clustering`) para un rendimiento óptimo con un gran número de puntos.
*   Capacidad de centrar el mapa en la ubicación actual del usuario.
*   Botón flotante para añadir nuevos PDI directamente desde el mapa.

### Gestión de PDI
*   Los usuarios pueden enviar nuevos PDI tocando en el mapa.
*   Formulario para añadir información del PDI (nombre, categoría, descripción).
*   **Sistema de Aprobación:**
    *   Los PDI enviados por usuarios estándar quedan en estado "pendiente".
    *   Los PDI enviados por administradores se aprueban automáticamente.

### Panel de Administración
*   **Gestión de Usuarios:**
    *   Listado completo de todos los usuarios registrados con buscador por nombre/email.
    *   Creación de nuevos usuarios (administradores o usuarios estándar).
    *   Edición de roles de usuario (promover a admin o revocar).
    *   Gestión y renovación de suscripciones de usuarios.
    *   Eliminación de usuarios con diálogo de confirmación deslizable para mayor seguridad.
*   **Aprobación de PDI:**
    *   Pantalla dedicada para que los administradores revisen y aprueben o rechacen los PDI pendientes.

### Estructura y Navegación
*   **Router:** Navegación gestionada mediante `go_router` para un enrutamiento declarativo y robusto.
*   **Menú Lateral (Drawer):**
    *   Muestra información del usuario actual (nombre, email, avatar).
    *   Navegación rápida a las secciones principales: Mapa, Perfil y Panel de Administrador (solo visible para admins).
    *   Opción para cerrar sesión.

## Correcciones y Mejoras (Sesión Actual)

En esta sesión, se ha realizado una depuración exhaustiva del código para solucionar múltiples errores y advertencias que impedían la compilación y el correcto funcionamiento de la aplicación.

*   **Plan de Acción:** Se generó y siguió un plan detallado para abordar sistemáticamente cada problema identificado por la herramienta `flutter analyze`.
*   **Eliminación de Fichero Corrupto:** Se eliminó el script `scripts/migrate_locations.dart` que contenía errores de sintaxis y referencias obsoletas.
*   **Corrección de Tema (Theming):**
    *   **Problema:** Error de tipo en `lib/config/app_theme.dart` donde una variable `Color` se usaba como `MaterialColor`, causando un crash al acceder a sus tonalidades (`shade`).
    *   **Solución:** Se cambió el tipo de la variable a `MaterialColor`, solucionando el error en la definición del tema oscuro.
*   **Corrección de Formularios:**
    *   **Problema:** Se usó el parámetro incorrecto `initialValue` en varios `DropdownButtonFormField`, causando errores de compilación en las pantallas de añadir PDI y crear usuario.
    *   **Solución:** Se reemplazó `initialValue` por el parámetro correcto `value` en `lib/screens/add_poi_screen.dart` y `lib/screens/create_user_screen.dart`.
*   **Limpieza de Código:**
    *   **Problema:** Se encontró una variable local (`isAdmin`) declarada pero no utilizada en `lib/widgets/app_drawer.dart`, generando una advertencia de `unused_local_variable`.
    *   **Solución:** Se eliminó la declaración y asignación de la variable redundante.
*   **Buenas Prácticas y Seguridad (`async`):**
    *   **Problema:** Múltiples advertencias `use_build_context_synchronously` indicaban un uso inseguro del `BuildContext` después de operaciones asíncronas, lo que podía causar crashes.
    *   **Solución:** Se añadieron comprobaciones de seguridad (`if (context.mounted)` o `if (!context.mounted) return;`) en todos los ficheros afectados (`manage_users_screen.dart`, `poi_approval_screen.dart`) antes de interactuar con el contexto, garantizando que el widget todavía está en el árbol de widgets.
*   **Corrección de Errores Propios:** Se identificó y corrigió un error de sintaxis introducido por mí mismo durante una de las correcciones, demostrando un ciclo de auto-revisión.

El resultado de esta sesión es una base de código estable, funcional y que sigue las mejores prácticas de desarrollo en Flutter.
