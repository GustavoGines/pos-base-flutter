# Changelog — Sistema POS (Frontend)

Todos los cambios notables de la aplicación de caja (Flutter/Windows) están documentados aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.0.0/) y el proyecto adhiere a [Semantic Versioning](https://semver.org/).

---
## [1.4.0] - 2026-05-09 - Cuentas de Consumo Interno, Dashboard de Presupuestos y Pagos Mixtos

### 🚀 Nuevas Funcionalidades (Comerciales)
- **Dashboard de Presupuestos Enterprise:** Rediseño completo de la grilla de presupuestos para que veas mucha más información en una sola pantalla. La selección de presupuestos es ahora ultra-rápida y fluida, ideal para negocios con mucho volumen.
- **Limpieza de Caja a un Clic:** Se agregó un botón rojo de "Vaciar" en el panel del Ticket Actual. Ahora podés vaciar un carrito entero si el cliente se arrepiente sin necesidad de borrar los productos uno por uno.
- **Precisión Total en Listas de Precios:** Ahora, cuando recuperás un presupuesto guardado, el sistema respeta de forma inteligente el modificador de la lista de precios (Mayorista, Tarjetas, etc.), garantizando que cobres exactamente el precio correcto.
- **Sincronización Perfecta de Horarios:** Todas las fechas y horas de creación de presupuestos se ajustan automáticamente al horario local (Argentina), eliminando cualquier desfasaje.
- **Pagos Combinados en Cuenta Corriente:** ¡Ahora podés recibir pagos múltiples en una sola operación! Si un cliente salda su deuda pagando una parte en Efectivo y el resto por Transferencia, el sistema lo permite automáticamente calculando la diferencia en tiempo real.
- **Cuentas de Consumo Interno (Dueños/Socios):** Se agregó la capacidad de crear "Cuentas Internas". Si vos o un socio retiran mercadería del local, ya no se ensuciarán tus estadísticas de ventas ni ganancias.
- **Reporte Gerencial de Consumo Interno:** Nuevo módulo exclusivo en Reportes para auditar y valorizar toda la mercadería retirada por los dueños o empleados, calculado a precio de costo.
- **Ventas Fiadas en el Arqueo de Caja:** El Cierre de Turno ahora detalla explícitamente cuánto dinero se vendió bajo la modalidad de "Cuenta Corriente" (fiado), separándolo del efectivo y tarjetas para que las cuentas siempre cuadren.
- **Claridad Visual en Saldos:** Mejoramos la pantalla de Cuentas Corrientes. En lugar de mostrar signos negativos confusos, ahora indica con claridad "Deuda a Pagar" (en rojo), "Saldo a Favor" (en verde) o "Cuenta al Día" (en gris).

### 🐛 Correcciones y Estabilidad
- **Blindaje Total de Cajas (Multi-Terminal):** Se solucionó definitivamente un error de sincronización donde, al cobrar velozmente en una terminal secundaria, la venta podía registrarse accidentalmente bajo el turno de la computadora principal. Ahora cada venta está 100% blindada a su propia caja física, asegurando un historial de Turnos perfecto.

---
## [1.3.9] - 2026-05-08 - Actualización de Precios Dinámicos y Estabilidad de Cajas

### 🚀 Mejoras Comerciales
- **Protección contra Inflación en Presupuestos:** Ahora, al recuperar un presupuesto guardado para facturarlo, el sistema actualizará automáticamente todos los artículos a los precios vigentes del catálogo. ¡Asegurá tu margen de ganancia sin importar cuándo se armó el presupuesto!
- **Configuración Inmediata de Impresoras:** Ajustá o cambiá tu impresora de tickets y empezá a imprimir al instante. Ya no es necesario reiniciar el sistema para que tome los nuevos parámetros.

### 🐛 Solución de Problemas
- **Seguridad en Multi-Caja:** Mejoramos el control de sesiones al alternar entre distintas cajas físicas. El sistema ahora garantiza que cada terminal opere bajo su propio turno abierto, previniendo errores de facturación cruzada y protegiendo la integridad de tus cierres de caja.



## [1.3.8] - 2026-05-07 - OTA Version Detection Fix

### 🐛 Fixes
- **Detección de versión del backend:** Corregido un defecto en `UpdateService` donde si `/version-check` fallaba (timeout, URL de entorno incorrecta, etc.), el sistema usaba el valor cacheado de `SharedPreferences['backend_version']` como fallback. Esto causaba que al cambiar de entorno (ej: `Sistema_POS` → `Sistema_POS_test`) o al configurar el backend por primera vez, el frontend enviara una versión incorrecta al servidor de licencias y no detectara actualizaciones disponibles. Ahora el fallback siempre es `0.0.0`, garantizando que el servidor de licencias siempre detecte la actualización.
- **Actualizador OTA (`.bat`):** Corregido un defecto donde los argumentos enviados a `Start-Process` vía archivo `.bat` eran destruidos por PowerShell al parsear comillas dobles, causando que el updater leyera la ruta truncada en el primer espacio. Ahora los argumentos se pasan como un array de PowerShell seguro (`'arg1', 'arg2'`).

## [1.3.7] - 2026-05-06 - Auto-Retry Connection

### 🚀 Mejoras
- **Conectividad de Red:** Implementado un "Reintento Automático Invisible" en la pantalla de carga inicial. Si la aplicación arranca antes que la tarjeta de red (Wi-Fi) o Laragon, espera automáticamente 2 segundos en segundo plano y reintenta la conexión una vez antes de mostrar un error al usuario.

## [1.3.6] - 2026-05-06 - Dynamic Network IP Fix for Updater

### 🐛 Fixes
- **Sincronización en Redes LAN:** Corregido un defecto crítico en `UpdateService` donde las PCs secundarias intentaban consultar la versión local contra `127.0.0.1` (fallback de fábrica) en lugar de utilizar la IP dinámica del servidor configurada en Ajustes (`pos_api`). Este error causaba que las terminales fallaran silenciosamente en la consulta local y siempre enviaran su versión antigua al servidor de licencias, generando falsas alertas de actualización.

## [1.3.5] - 2026-05-06 - Strict Cache Busting Fix

### 🐛 Fixes
- **Sincronización de Versiones (PCs Secundarias):** Implementado un "Cache Buster" matemático (Timestamp dinámico) en el chequeo de versión local (`/version-check`) para evadir el almacenamiento en caché de algunos routers de red o de la pila HTTP de Windows, asegurando que las terminales secundarias detecten el servidor actualizado instantáneamente y no entren en bucles.

## [1.3.4] - 2026-05-06 - OTA Path & A4 Printer Fix

### 🚀 Mejoras
- **Impresión de Copias:** El botón "Imprimir Copia" en el Historial de Ventas ahora detecta si la impresora configurada es A4/Carta y despliega correctamente la vista previa en PDF visual, en lugar de fallar enviando comandos térmicos.

### 🐛 Fixes
- **Actualizador OTA:** Resuelto un error crítico (`PathAccessException: errno = 5`) que ocurría al intentar descargar actualizaciones en la carpeta de instalación en Windows (Archivos de Programa) sin permisos de Administrador. Ahora los archivos ZIP se descargan de forma segura en la carpeta `%TEMP%` del sistema operativo.

## [1.3.3] — 2026-05-06 — Stock Sync Fix

### 🐛 Fixes
- **Notificaciones de Stock:** Corregido error visual donde la campanita de alertas de stock crítico no se refrescaba automáticamente tras anular un ticket de venta desde el historial.

---

## [1.3.1] — 2026-05-04 — Frontend Hotfixes

### 🐛 Fixes
- **Startup Connection Fallback:** Corregido un fallo técnico donde el diálogo emergente para configurar la IP del servidor fallaba silenciosamente por un problema de contexto `BuildContext` si el backend principal estaba caído durante el arranque inicial de la aplicación.
- **Productividad de Catálogo:** Agregada la funcionalidad de cálculo de porcentaje de ganancia automático para derivar precio de venta desde el costo en la creación y edición de productos, con persistencia de preferencias de usuario.
- **Generación de Código de Barras:** Corregido fallo donde limpiar el código de barras no enviaba el valor vacío al servidor para autogenerar un código EAN-13 interno.
- **Flujo de Creación Rápida:** Al crear una nueva Marca o Categoría desde la ventana de producto, el desplegable ahora la selecciona automáticamente.

---

## [1.3.0] — 2026-04-28 — Ferretería & Retail Edition

### 🚀 Nuevas Funcionalidades
- **Aumento Masivo de Precios:** Actualizá cientos de productos en un clic desde la nueva pantalla de gestión. Filtrá por categoría, previsualizá el impacto económico real antes de confirmar y deshacé los cambios si cometés un error.
- **Generación de Remitos:** Imprimí remitos de entrega en formato A4 con marca de agua, campo de firma del receptor y la dirección exacta del cliente, directamente desde la pantalla de caja sin pasos adicionales.
- **Cartera de Cheques:** Nuevo panel de control visual con sistema de alertas por colores (semáforo verde/amarillo/rojo) para llevar el seguimiento de todos los cheques recibidos y sus fechas de vencimiento en un solo lugar.
- **Exportación de Reportes Gerenciales:** Descargá tu balance mensual completo en formato PDF o Excel con un solo clic. Analizá tus ventas por marca y categoría desde el nuevo dashboard gerencial con gráficos interactivos.
- **Listas de Precio en Caja:** Cambiá entre listas de precios (Minorista, Mayorista, Tarjeta) directamente desde el carrito de compras y visualizá el impacto en los precios en tiempo real sin interrumpir la atención al cliente.

### ✨ Mejoras Visuales
- **Dashboard Financiero Compacto:** Rediseñamos el panel de resumen en el Registro de Ventas. Las tarjetas de totales son ahora más compactas y se organizan en bloques inteligentes, permitiéndote ver todos los métodos de pago sin perder espacio vertical en la lista de tickets. Podés revisar muchas más ventas de un vistazo sin necesidad de hacer scroll.

### 🛠️ Mejoras de Estabilidad y Actualizaciones (OTA)
- **Canales de Distribución (Release Channels):** El equipo de desarrollo puede ahora enviar versiones de prueba al Canal Beta sin afectar a los clientes del Canal Stable (producción). Esto permite validar actualizaciones en hardware real antes de publicarlas masivamente.
- **Modo Desarrollador Oculto:** Un acceso especial en la pantalla de Ajustes permite al técnico de soporte alternar el canal de actualizaciones entre Stable y Beta de forma segura y sin modificar código.
- **Actualizador Inteligente (OTA v2):** El sistema verifica físicamente la versión instalada antes de descargar, auto-detecta la ruta del servidor local y utiliza un mecanismo de renombrado para evadir los bloqueos de Windows al reemplazar archivos en uso. El sistema nunca queda en estado inconsistente tras una actualización.
- **Actualizador a Prueba de Fallos (OTA v3):** El instalador fue rediseñado completamente para funcionar de forma independiente a la aplicación. El archivo de actualización (ZIP) se guarda en el directorio de instalación —no en la carpeta temporal del sistema— garantizando que sobreviva cualquier cierre inesperado. El instalador se ejecuta como un proceso del sistema operativo completamente desacoplado, asegurando que la instalación continúe aunque la app se haya cerrado. Compatible con todas las versiones de Windows, incluyendo Windows 11 con Defender y UAC activados.
- **Orquestación Inteligente de Actualizaciones (Smart Chaining):** Si el sistema detecta que tanto la App como el Servidor necesitan actualizarse, ya no muestra dos diálogos separados. En su lugar, muestra un único diálogo de **"Actualización Integral del Sistema"** que guía al usuario por el proceso en el orden correcto y seguro: primero la App (que contiene el motor de instalación), y al reiniciarse, el Servidor se actualiza automáticamente sin que el usuario tenga que ir a Ajustes. Los botones de actualización del Servidor también quedan bloqueados si la App no está en la última versión, evitando inconsistencias entre componentes.
- **Registro de Actividad del Actualizador (Log OTA):** Cada actualización genera un archivo de registro detallado (`updater_log.txt`) en la carpeta de instalación. Al abrir la app después de una actualización, el sistema muestra automáticamente un diálogo con el resultado: ✅ éxito con la versión instalada, o ❌ error con el log completo para diagnóstico remoto. El soporte técnico puede pedirle este archivo a cualquier cliente para resolver problemas sin necesidad de visita presencial.
- **Ajustes Rápidos de Hardware:** Acceso directo con ícono de impresora visible en todas las pantallas para configurar impresoras y balanzas sin ir a Ajustes.
- **Mejoras en la Auditoría y PDFs:** La auditoría de stock ahora muestra la unidad de medida (Kg, Lt, Un) de cada producto. Los PDFs de venta mejoraron su diseño con marcas de agua más profesionales.

### 🐛 Correcciones
- Corregido recorte de marca de agua en remitos impresos en papel tamaño Carta.
- Corregida pérdida visual de ítems al actualizar el listado de remitos.
- Corregido error visual donde los presupuestos no reflejaban el precio de listas nuevas al modificarlas.
- **[CRÍTICO] Módulos Premium bloqueados post-actualización:** Corregido bug donde, tras actualizar a v1.3.0, los módulos Premium (Listas de Precio, Remitos, Cheques) aparecían bloqueados a pesar de tener licencia activa. La causa era una combinación de caché de base de datos obsoleta y un payload incompleto desde el servidor de licencias. Solucionado con un mecanismo de validación local de respaldo en el backend.
- **[CRÍTICO] Actualizador se cerraba sin instalar nada (Windows 11):** La app se cerraba correctamente al actualizar, pero el instalador nunca llegaba a ejecutarse. El proceso estaba enlazado al árbol de procesos de la app y Windows lo terminaba automáticamente al cerrar esta. Solucionado mediante el lanzamiento del instalador como proceso completamente independiente del sistema operativo (técnica `DETACHED_PROCESS`).
- **[CRÍTICO] Loop de actualización infinito:** Tras un fallo en la instalación, la app volvía a ofrecer la misma actualización indefinidamente porque el ZIP temporal era eliminado por Windows y el sistema no registraba que el intento había ocurrido. Ahora el archivo persiste en el directorio de instalación y el sistema escribe el resultado del proceso para recordarlo al próximo inicio.
- **[CRÍTICO] Diálogo de actualización congelado (cold-start del servidor):** El diálogo de actualización quedaba bloqueado sin respuesta cuando el servidor de licencias estaba en modo de reposo (Render demora 2-3 minutos en responder el primer request). Solucionado con un timeout explícito configurable en el proceso de descarga.
- **[CRÍTICO] Versión mostrada como "desconocida" tras actualizar:** El diálogo de confirmación post-actualización mostraba "vdesconocida" en lugar del número de versión real. El instalador ahora incluye la versión directamente en el archivo de resultado, sin depender de datos escritos por la app antes de cerrarse.
- **[CRÍTICO] Reseteo forzado de URL del Servidor:** La app sobrescribía la IP del servidor al valor de producción por defecto en cada reinicio, ignorando la configuración manual del técnico en la pantalla de Red. Corregido eliminando el reset automático al iniciar.

---

## [1.2.4] — 2026-04-14 — Updater Resilience

### 🛠️ Mejoras
- Refactorización del updater para mayor resiliencia: espera inteligente con detección de lock en el `.exe`, fallback de renombramiento para archivos bloqueados, y auto-protección para no sobreescribirse a sí mismo durante la actualización.
- El updater del backend añade soporte para el argumento `--component` para distinguir actualizaciones de frontend vs backend.

---

## [1.1.0] — 2026-03-xx — Infraestructura OTA y Licencias

### 🚀 Nuevas Funcionalidades
- **Sistema OTA (Over-The-Air):** Actualización automática de frontend y backend desde el servidor de licencias central.
- **Motor de Licencias (DRM):** Validación de licencias con período de gracia de 72 horas, soporte para planes SaaS y Lifetime, y sincronización automática diaria.
- **Feature Flags Server-Driven:** La habilitación de módulos (Cuentas Corrientes, Presupuestos, Multi-Caja, etc.) se controla desde el servidor de licencias.
- **Arquitectura Multi-Caja:** Configuración de hardware (impresora, balanza, papel) independiente por terminal vía `SharedPreferences`.
- **Caja Rápida (Fast POS):** Modo de ingreso por código de barras sin confirmación de cantidad para comercios de alto volumen.

---

[1.3.0]: https://github.com/GustavoGines/pos-base-flutter/compare/v1.2.4...v1.3.0
[1.2.4]: https://github.com/GustavoGines/pos-base-flutter/compare/v1.1.0...v1.2.4
[1.1.0]: https://github.com/GustavoGines/pos-base-flutter/releases/tag/v1.1.0
