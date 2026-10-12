# Changelog - Sistema POS (Frontend)
Todos los cambios notables de la aplicación de caja (Flutter/Windows) están documentados aquí.


## [2.0.1] - 2026-10-12
### Correcciones
- Corrección de codificación UTF-8 en pantalla de configuraciones (eliminación de caracteres mojibake en títulos, listas de precios, asignación de terminal y planes).
- Actualización de compatibilidad de Java 21 para Gradle 9 y Android SDK 36 en pipeline móvil.

## [2.0.0] - 2026-10-12
### E-commerce y Plataformas Web
- Módulo de integraciones omnicanal para Mercado Libre, WooCommerce, Tiendanube y plataforma web propia.
- Acciones directas de importación y exportación de catálogo y sincronización en tiempo real.
- Bloqueo y protección de funciones de sincronización según plan contratado con diálogo interactivo de actualización.
### Importación Excel
- Carga de planillas Excel mediante arrastrar y soltar (Drag and Drop) con soporte extendido y barra de progreso en tiempo real.
### Seguridad y Operaciones
- Acceso protegido por PIN de seguridad para operaciones administrativas sensibles.
- Soporte para adjuntos y comprobantes en arqueos y movimientos de caja.
- Visualización de bitácora técnica de sincronización en vivo.
### Facturación e Interfaz de Usuario
- Rediseño de la cabecera de comprobantes y facturas con logo dinámico, datos de contacto y CAE.
- Prevención de desbordamientos visuales (overflow) en pantallas de bajas resoluciones y ventanas reducidas.
- Soporte transparente para canales de actualización estable y beta.

## [1.8.5] - 2026-09-06
### Agregado
- Botón de refresco manual en el catálogo.
- Soporte para escanear códigos de barras desde el móvil hacia el formulario de producto de PC en tiempo real.
- Formulario móvil nivelado con todos los campos de la PC.

## [1.8.4] - 2026-09-03
### Gran Actualizacion (Mejoras desde v1.4.4)
- **Soporte Oficial para App Movil:** Nuevo modulo API para control de stock, lectura de codigos de barra y ventas desde el celular.
- **Acceso Remoto y 4G:** Soporte nativo para Cloudflare Tunnels (Smart Auto-Fallback), permitiendo conectar el celular desde cualquier lugar sin configurar IPs.
- **Sincronizacion Ultra Rapida:** Las ventas hechas con el celular o la PC se reflejan al instante en todos los dispositivos conectados.
- **Seguridad y Licencias Anti-Pirateria:** Sistema de validacion de licencias integrado con pantalla de bloqueo.
- **Actualizaciones 100% Automaticas:** Sistema continuo e inteligente para el servidor y la caja (con soporte para rutas locales dinamicas).
- **Mejoras de Estabilidad en Red:** Correccion de conexion 4G lenta y soporte para Websockets en cualquier subdominio (ej. api-cliente).
- **Adaptabilidad de Pantallas:** Las pantallas de Cheques y Reportes ahora se adaptan perfectamente sin errores graficos al achicar la ventana al minimo.
- **Manejo de Errores Mejorado:** Interfaz pulida con notificaciones profesionales flotantes al crear categorias o marcas.
