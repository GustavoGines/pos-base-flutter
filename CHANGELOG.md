# Changelog — Sistema POS (Frontend)

Todos los cambios notables de la aplicación de caja (Flutter/Windows) están documentados aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.0.0/) y el proyecto adhiere a [Semantic Versioning](https://semver.org/).

---

## [1.3.0] — 2026-04-28 — Ferretería & Retail Edition

### 🚀 Nuevas Funcionalidades
- **Aumento Masivo de Precios:** Actualizá cientos de productos en un clic desde la nueva pantalla. Filtrá, previsualizá el impacto y deshacé cambios si te equivocás.
- **Generación de Remitos:** Imprimí remitos de entrega tamaño A4 con marca de agua, firma y la dirección exacta del cliente directamente desde la caja.
- **Cartera de Cheques:** Nuevo dashboard visual con alertas de colores (semáforo) para llevar el control de vencimientos de todos los cheques recibidos.
- **Exportación de Reportes:** Descargá tu balance mensual completo en PDF y Excel con un solo clic, y analizá tus ventas por marca desde el nuevo dashboard gerencial.
- **Listas de Precio en Caja:** Cambiá la lista de precios (Minorista/Mayorista) desde el carrito de compras y mirá cómo reaccionan los precios en tiempo real.

### ✨ Mejoras Visuales
- **Dashboard Financiero Compacto:** Rediseñamos el panel de resumen en el Registro de Ventas. Las tarjetas de totales ahora son mucho más compactas y se organizan inteligentemente en bloque. Esto te permite ver todos los métodos de pago fácilmente sin robarle espacio vertical a la lista de tickets, permitiéndote ver muchas más ventas a la vez sin tener que hacer scroll.

### 🛠️ Mejoras de Estabilidad y Optimizaciones
- **Canales de Distribución (Release Channels):** Implementación de canales Beta y Stable para actualizaciones OTA. Ahora el equipo de desarrollo puede enviar versiones "invisibles" al servidor de licencias (Canal Beta) para realizar pruebas reales en hardware sin afectar a clientes en producción (Canal Stable).
- **Modo Desarrollador Oculto:** Nuevo "Easter Egg" en la pantalla de ajustes que permite alternar la terminal entre el canal de actualizaciones estable y el de pruebas con una interfaz interactiva.
- **Ecosistema de Actualización Resiliente (OTA v2):** El sistema ahora es 100% inteligente. Verifica físicamente las versiones locales antes de descargar, auto-detecta la ruta del servidor (con opción de ajuste manual en Red), y utiliza un protocolo de auto-renombrado para evadir bloqueos de Windows, garantizando que el sistema nunca quede "roto" tras una actualización.
- **Actualizador a Prueba de Cortes (OTA v3):** El proceso de instalación de actualizaciones fue rediseñado desde cero para ser completamente independiente de la aplicación. El ZIP de actualización ahora se guarda en el directorio de instalación (no en la carpeta temporal del sistema), evitando que Windows lo elimine si el sistema se reinicia o la app se cierra durante la descarga. El instalador se lanza como un proceso completamente separado del sistema operativo, garantizando que la instalación continúe correctamente incluso después de que la aplicación se cierre. Funciona de forma confiable en todas las versiones de Windows, incluyendo Windows 11 con Defender activado.
- **Registro de Actividad del Actualizador (Log OTA):** Cada vez que el sistema instala una actualización, genera un registro detallado en la carpeta de instalación. Al abrir la app después de una actualización, el sistema muestra automáticamente si la instalación fue exitosa ✅ o si hubo algún problema ❌, con el detalle completo para diagnóstico. Esto aplica a todos los clientes de producción y permite al soporte técnico identificar cualquier problema de forma remota.
- **Novedades Cómodas:** La ventana de actualizaciones (esta que estás leyendo) ahora es mucho más grande en pantallas de escritorio para mayor comodidad.
- **Ajustes Rápidos:** Agregamos un acceso directo con ícono de impresora en todas las pantallas para configurar el hardware al instante.
- **Visualización:** Ahora la auditoría muestra la unidad de medida (Kg, Lts) y los PDFs de venta mejoraron su diseño con marcas de agua más profesionales.

### 🐛 Fixes
- Corregido recorte de marca de agua en remitos impresos en papel tamaño Carta.
- Corregida pérdida visual de items al actualizar el listado de remitos.
- Corregido error visual donde los presupuestos no reflejaban el precio de listas nuevas.
- **[CRÍTICO] Módulos Premium bloqueados post-actualización:** Corregido bug donde, tras actualizar a v1.3.0, los módulos Premium (Listas de Precio, Remítos, Cheques) aparecían bloqueados a pesar de tener licencia activa. El problema era una combinación de caché de base de datos obsoleta y un payload incompleto del servidor de licencias. Solucionado con un Failsafe local en el backend.
- **[CRÍTICO] Actualizador se cerraba sin instalar nada (Windows 11):** Corregido bug donde la aplicación se cerraba correctamente pero el instalador nunca llegaba a ejecutarse en Windows 11. El proceso instalador quedaba atado al árbol de procesos de la app y era eliminado por Windows al cerrar esta. Solucionado lanzando el instalador como proceso completamente independiente del sistema operativo.
- **[CRÍTICO] Loop de actualización infinito:** Corregido bug donde, tras fallar la instalación, la app volvía a ofrecer la misma actualización indefinidamente porque el archivo de instalación temporal era eliminado y el sistema no registraba el intento fallido. Ahora el archivo persiste en el directorio de instalación y el sistema registra el estado completo del proceso.
- **[CRÍTICO] Reseteo forzado de URL del Servidor:** Corregido bug donde la aplicación forzaba constantemente la IP del servidor al valor de producción al reiniciar, ignorando las configuraciones manuales de red del usuario en la pantalla de Settings.
- **[CRÍTICO] Actualizador del Servidor bloqueado por UAC:** Reemplazado el mecanismo de invocación del instalador para evitar que el diálogo de actualización quedara congelado indefinidamente mientras Windows esperaba confirmación de permisos de administrador. Solucionado con un Failsafe local en el backend.
- **[CRÍTICO] Updater congelado:** Corregido escenario donde el diálogo de actualización quedaba bloqueado sin respuesta al ejecutar el servidor de licencias en modo cold-start (Render tarda 2-3 min en despertar). Se agregó timeout explícito de 2 minutos al proceso de PowerShell.

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
