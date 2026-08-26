# Changelog — Sistema POS (Frontend)
Todos los cambios notables de la aplicación de caja (Flutter/Windows) están documentados aquí.

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