# Changelog — Sistema POS (Frontend)
Todos los cambios notables de la aplicación de caja (Flutter/Windows) están documentados aquí.

## [1.6.6] - 2026-08-26
### Novedades de esta Gran Actualización (desde v1.4.4)
- **Soporte Oficial para la App Móvil:** El sistema ahora cuenta con todo el motor interno preparado para comunicarse en tiempo real con nuestra nueva Aplicación Móvil.
- **Actualizaciones 100% Automáticas:** Rediseñamos por completo el sistema de actualización. Ahora, cuando haya mejoras tanto para la caja como para el servidor, el proceso será continuo, inteligente y completamente automático, sin requerir clics innecesarios.
- **Mayor Estabilidad y Resiliencia:** Mejoramos la conexión de red y le dimos al sistema la capacidad de manejar grandes volúmenes de datos durante las actualizaciones sin interrumpir tu trabajo.
- **Limpieza y Pulido Visual:** Eliminamos textos innecesarios y pulimos las pantallas para que tu experiencia de uso sea más limpia y profesional.
- **Validación Estricta de Actualización:** El actualizador ahora garantiza de forma estricta que la memoria del servidor se purgue completamente para eliminar los "falsos avisos" de actualización pendiente.
## [1.6.4] - 2026-08-26
### Mejoras
- Mejora de UX (Actualización Integral): Eliminado el cartel intermedio de "App actualizada con éxito" si el sistema detecta que debe continuar automáticamente con la actualización del Servidor. Ahora el proceso es 100% continuo sin requerir clics adicionales.

## [1.6.3] - 2026-08-26
### Mejoras
- Mejora de UX: Tras finalizar una actualización con éxito, la tarjeta de aviso se oculta instantáneamente (de forma optimista) para una respuesta visual más limpia.
- Mejora de UX (Actualización Integral): Al reiniciar la aplicación tras actualizar la interfaz (Fase 1), el actualizador del servidor (Fase 2) se inicia automáticamente sin requerir que el usuario haga clic por segunda vez.

## [1.6.2] - 2026-08-26
### Correcciones
- Aumentado el tiempo de espera del actualizador a 20 minutos para dar tiempo a que los servidores backend extraigan miles de archivos sin marcar error falso.
- Ajuste final de versiones para correcta sincronización del cliente y servidor.

## [1.6.1] - 2026-08-26
### Correcciones
- Solucionado el problema de renderización de caracteres especiales y emojis (Mojibake) en los textos de Novedades del actualizador. El changelog ahora se lee y procesa estrictamente en formato UTF-8 nativo.
- Simplificado el formato del historial de actualizaciones en pantalla, eliminando negritas de Markdown y subtítulos innecesarios para mejorar la legibilidad y evitar confusión visual.

## [1.6.0] - 2026-08-26
### Mejoras
- Actualización mayor para dar soporte completo a la App Móvil.

---
## [1.4.0] - 2026-08-21
### Novedades
- Lanzamiento inicial estable con Auto-Updater.