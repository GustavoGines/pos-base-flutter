# Changelog 📝 Sistema POS (Frontend)
Todos los cambios notables de la aplicación de caja (Flutter/Windows) están documentados aquí.

## [1.7.0] - 2026-08-26
### Novedades de esta Gran Actualización (desde v1.4.4)
- **Soporte Oficial para la App Móvil:** El sistema ahora cuenta con todo el motor interno preparado para comunicarse en tiempo real con nuestra nueva Aplicación Móvil.
- **Actualizaciones 100% Automáticas:** Rediseñamos por completo el sistema de actualización. Ahora, cuando haya mejoras tanto para la caja como para el servidor, el proceso será continuo, inteligente y completamente automático, sin requerir clics innecesarios.
- **Personalización Extrema del Terminal:** Agregamos 4 nuevos modos de vista para los productos de Acceso Rápido (Tarjetas grandes, medianas, lista clásica y modo 'supermercado' ultra compacto) para adaptarse perfectamente a tu forma de vender. Además, podés ajustar libremente qué porción de la pantalla ocupa el carrito y qué porción ocupan los productos.
- **Mayor Estabilidad y Resiliencia:** Mejoramos la conexión de red y le dimos al sistema la capacidad de manejar grandes volúmenes de datos durante las actualizaciones sin interrumpir tu trabajo.
- **Limpieza y Pulido Visual:** Eliminamos textos innecesarios y pulimos las pantallas para que tu experiencia de uso sea más limpia y profesional. Corregido un pequeño error visual donde el botón de actualización persistía en el menú principal.

## [1.6.4] - 2026-08-26
### Mejoras
- Mejora de UX (Actualización Integral): Eliminado el cartel intermedio de "App actualizada con éxito" si el sistema detecta que debe continuar automáticamente con la actualización del Servidor. Ahora el proceso es 100% continuo sin requerir clics adicionales.

## [1.6.3] - 2026-08-26
### Bugs Arreglados
- Solucionado el problema donde la ventana de "Actualización del Servidor" desaparecía prematuramente.
- Solucionado el error de conexión (EOF) y tiempos de espera de Laravel durante las actualizaciones grandes, ignorando de forma segura los errores de interrupción de stream.

## [1.6.2] - 2026-08-26
### Bugs Arreglados
- Solucionado un problema de visualización en el Changelog donde los acentos y tildes se mostraban incorrectamente con símbolos raros.
- Correcciones menores en el sistema de actualización OTA para mayor fluidez.

## [1.6.1] - 2026-08-25
### Mejoras
- Optimizada la pantalla de actualización para que sea estéticamente idéntica a la pantalla de conexión.
- Eliminados textos de debug en la UI principal para darle un toque más limpio y profesional al usuario final.

## [1.5.0] - 2026-08-25
### Características Nuevas
- **Actualización Dual Automática:** El sistema ahora detecta y orquesta tanto las actualizaciones del Frontend (Caja) como del Backend (Servidor) de forma secuencial. Una vez descargada la caja, se notifica y se levanta automáticamente el script del servidor.

## [1.4.4] - 2026-08-25
### Mejoras
- Versión base estable con soporte OTA.
