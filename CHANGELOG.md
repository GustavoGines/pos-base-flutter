# Changelog - Caja4U (Frontend)
Todos los cambios notables de la aplicación de caja (Flutter/Windows/Android) están documentados aquí.


## [2.1.1] - 2026-11-21
### Actualizador OTA Diferencial Ultrarrápido y Blindaje Anti-Antivirus
- Extracción diferencial inteligente por tamaño y `CRC-32` desde el directorio central del ZIP sin descomprimir ni escribir archivos sin cambios, reduciendo el tiempo de actualización de minutos a segundos.
- Descarga automática de paquete liviano de servidor (~850 KB) cuando `composer.lock` no cambia, manteniendo compatibilidad total con clientes `v1.8.5` y `v2.1.0`.
- Commit atómico de versión post-migración, protección de terminales secundarias en red LAN y lanzamiento nativo compatible con Windows 10/11 y antivirus (Avast / Defender).

## [2.1.0] - 2026-11-20
### Identidad Visual y Rebranding (Caja4U • by Dev4U)
- Nueva identidad corporativa **Caja4U • by Dev4U** en barra superior, pantalla de acceso, ventana de Windows, Android y actualizador OTA.
- Nuevos íconos de alta resolución (`app_icon.ico`, `app_logo.png` y Adaptive Icons de Android).
- Migración transparente y automática en OTA de preferencias locales (`SharedPreferences`) y accesos directos de Escritorio (`Sistema POS` -> `Caja4U`) sin pérdida de configuración en terminales en producción.
### Lotes, Vencimientos, Producción Propia y Aislamiento Modular (Opción 1A)
- Control de vencimientos por lotes en catálogo, compras, stock y campanita de alertas predictivas con validez en días sincronizada con fecha de vencimiento.
- Módulo de Producción Propia, recetas multi-nivel y Planilla Rápida Matutina para horneado/elaboración diaria.
- Aislamiento modular `batch_expiration` y `production` según rubro (`retail` vs `hardware_store`) y addons de licencia.
### Facturación Electrónica ARCA / AFIP, Libro IVA y Comprobantes
- Emisión de Factura A con validación estricta de receptor (CUIT de 11 dígitos y Condición frente al IVA) y percepciones IIBB.
- Vistas de Libro IVA Compras y Ventas, posición mensual de IVA y rediseño de comprobantes A4/Carta y térmicos 58mm/80mm con código QR oficial de ARCA/AFIP.
- Asistente paso a paso para generación de CSR y vinculación de certificados digitales ARCA/AFIP con Modo Entorno Demo (Homologación).
### Mejoras de Usabilidad, Catálogo y Proveedores
- Menú contextual con clic derecho en la tabla de catálogo (acciones individuales y masivas), cambio rápido de precio y duplicación de productos.
- Carga compacta de ítems en facturas/remitos de proveedores con soporte multi-lote y creación rápida de productos preseleccionando el proveedor actual.
- Rediseño del menú principal, unificación de carga de logo del negocio y limpieza de textos corruptos (mojibake UTF-8) en todo el sistema.

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
