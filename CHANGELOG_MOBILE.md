# Changelog — POS Móvil (Android)

Todos los cambios notables de la aplicación móvil de Android están documentados aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.0.0/).

## [1.8.0] - 2026-08-31
### Seguridad
- Endpoint de rescate OTA ahora protegido con token secreto (X-Rescue-Token).
- Rescue Trigger acotado exclusivamente a Android: el escritorio ya no dispara migraciones de base de datos innecesariamente.
### Mejorado
- Pipeline de CI/CD: la versión de la app se sincroniza automáticamente desde el tag de GitHub al compilar el APK.
- Historial de versiones en GitHub Releases: cada APK publicado queda registrado como artefacto descargable.

## [1.7.6] - 2026-08-30
### Corregido
- Auto-selección de Categoría y Marca recién creadas al cerrar el gestor desde el formulario de producto.
- Auto-formato de URL corregido para IPs y dominios al configurar el servidor.

## [1.7.5] - 2026-08-29
### Corregido
- Error de codificación que generaba caracteres extraños (tildes, eñes) en la tabla del catálogo y carteles de error.
- Eliminada inyección automática de ruta local en la configuración para facilitar el uso de dominios Cloudflare Tunnels.
- Restaurada la selección automática de Marcas y Categorías al crearlas desde el catálogo.

## [1.7.4] - 2026-08-29
### Agregado
- Motor interno preparado para comunicación en tiempo real con el backend.
- Sistema de actualizaciones OTA rediseñado: continuo, inteligente y completamente automático.
### Corregido
- Bug del actualizador que causaba falsos positivos de actualización.
- Codificación visual corregida en toda la UI.

## [1.7.3] - 2026-08-29
### Mejorado
- Optimización de UI en pantalla de bloqueo.
- Corrección de bugs asíncronos en procesos de la app móvil.

## [1.7.2] - 2026-08-28
### Corregido
- Mensaje de error mejorado en pantalla de bloqueo de licencia.

## [1.7.1] - 2026-08-28
### Mejorado
- Mejoras de UX en el catálogo.
- Mejoras de gestión de red para reconexión automática.

## [1.6.2] - 2026-08-26
### Corregido
- Aumentado el tiempo de espera del actualizador a 20 minutos para dar tiempo a extraer archivos del backend.
- Ajuste de versiones para correcta sincronización cliente-servidor.

## [1.6.1] - 2026-08-26
### Corregido
- Corrección visual en la visualización de las Novedades de Actualización.

## [1.6.0] - 2026-08-26
### Agregado
- Nuevo Sistema de Canales de Actualización (Estable / Beta).
- Soporte oficial para despliegues móviles integrados con el servidor.
### Mejorado
- Sonido del escáner en auditorías y control de stock: sin latencia.
- Limitador de peticiones silenciosas: reduce el consumo de red y CPU del servidor en un 80%.
### Corregido
- Corrección en el Muro de Fuego que provocaba bloqueos erróneos de permisos de Acceso Remoto.
- Error visual (overflow) que deformaba la pantalla de bloqueo al abrir el teclado.

## [1.5.11] - 2026-08-25
### Corregido
- Limitadas las peticiones silenciosas para no saturar el servidor local.

## [1.5.10] - 2026-08-25
### Corregido
- Solucionado overflow al abrir teclado en pantalla de bloqueo en móviles.

## [1.5.9] - 2026-08-24
### Corregido
- Reparado el sonido del escáner.

## [1.5.8] - 2026-08-24
### Mejorado
- Ocultar badge de actualización en el Login de Android.

## [1.5.7] - 2026-08-24
### Corregido
- Latencia en el sonido del escáner en la primera lectura.

## [1.5.6] - 2026-08-24
### Mejorado
- Suavizado del sonido del escáner (onda senoidal pura).

## [1.1.0] - 2026-08-24
### Agregado
- Sistema de actualizaciones in-app (OTA). La aplicación avisa automáticamente cuando hay una nueva versión.
- Configuración de firma para Release lista para producción.
### Mejorado
- Configuración de red para descargar actualizaciones directamente de Cloudflare R2.