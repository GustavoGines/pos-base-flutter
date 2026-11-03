# Changelog - Caja4U (Frontend)
Todos los cambios notables de la aplicación de caja (Flutter/Windows/Android) están documentados aquí.


## [2.1.0] - 2026-11-03
### Identidad Visual y Rebranding (Caja4U • by Dev4U)
- Nueva identidad corporativa **Caja4U • by Dev4U** en barra superior, pantalla de acceso, ventana de Windows, Android y actualizador OTA.
- Nuevos íconos de alta resolución (`app_icon.ico`, `app_logo.png` y Adaptive Icons de Android).
- Migración transparente y automática en OTA de preferencias locales (`SharedPreferences`) y accesos directos de Escritorio (`Sistema POS` -> `Caja4U`) sin pérdida de configuración en terminales en producción.
### Facturación Electrónica ARCA / AFIP y Comprobantes
- Emisión de Factura A con validación estricta de receptor (CUIT de 11 dígitos y Condición frente al IVA).
- Generación de Comprobante PDF A4 con código QR oficial de ARCA/AFIP, desglose impositivo discriminado y CAE.
- Asistente paso a paso para generación de CSR y vinculación de certificados digitales ARCA/AFIP.
- Modo Entorno Demo (Homologación) con credenciales de prueba en 1 clic.
### Mejoras de Usabilidad y Estabilidad
- Rediseño del menú principal con botones más amplios y legibles en resoluciones estándar y táctiles.
- Unificación de carga del logo del negocio y refresco automático de configuración en cambios de ruta.
- Limpieza de textos corruptos (mojibake UTF-8) en todo el sistema.

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
