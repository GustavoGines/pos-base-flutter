# Changelog — Sistema POS (Frontend)

Todos los cambios notables de la aplicación de caja (Flutter/Windows) están documentados aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.0.0/) y el proyecto adhiere a [Semantic Versioning](https://semver.org/).

---

## [1.3.0] — 2026-04-26 — Ferretería & Retail Edition

### 🚀 Nuevas Funcionalidades
- **Aumento Masivo de Precios:** Actualizá el precio de venta de cientos de productos con un solo clic. Filtrá por categoría, marca o una selección manual. Incluye previsualización del impacto antes de confirmar y reversión completa de lotes desde el historial.
- **Módulo de Remitos de Logística:** Generá remitos de entrega vinculados a cada venta, con dirección de entrega personalizada por cliente. Los remitos se imprimen en A4 con marca de agua, firma y pie de comprobante.
- **Cartera de Cheques de Terceros:** Registrá pagos con cheque de terceros directamente en la caja. El módulo incluye un dashboard con semáforo de vencimientos para gestionar el cobro de la cartera.
- **Motor de Precios Dinámicos (Listas de Precio):** Creá hasta 3 listas de precio diferenciadas (Mayorista, Especial, Tarjeta). El POS cambia de lista de precio en tiempo real desde el carrito de ventas. Ahora disponible para Retail Premium.
- **Exportación de Balance Mensual:** Descargá el balance mensual completo en PDF y Excel con un solo clic desde los reportes gerenciales.
- **Dashboard Gerencial por Marcas:** Analizá las ventas desglosadas por marca de producto.
- **Dirección de Entrega en Checkout:** Input para registrar la dirección de entrega directamente en la pantalla de cobro.
- **Gestión de Marcas en Catálogo:** CRUD completo de marcas de producto para organizar el catálogo.

### 🛠️ Mejoras y Optimizaciones
- **Modal de Novedades Responsivo:** El diálogo de actualización ahora es más amplio en escritorio (40% de la pantalla) para leer mejor todas las novedades.
- **PIN de Rescate Administrativo:** Protocolo de emergencia para recuperar acceso de administrador sin necesidad de modificar la base de datos manualmente.
- **Auditoría de Precios en Ventas:** Cada venta registra la lista de precio activa para trazabilidad contable completa.
- **Actualizador Automático Mejorado:** El actualizador limpia y regenera la caché del servidor tras cada actualización, eliminando los falsos bugs post-actualización.
- **Rendimiento en Catálogos Grandes:** Las actualizaciones masivas de precios se procesan en bloques seguros, sin riesgo de timeout en catálogos de más de 1.000 productos.
- **Icono de Impresora Global:** Acceso rápido a ajustes de hardware desde cualquier pantalla de la app.

### 🐛 Fixes
- Corregido error donde los cierres de caja y movimientos de stock se registraban a nombre del usuario incorrecto en la auditoría.
- Corregido error 500 al registrar pagos de cuenta corriente con ciertos métodos de pago.
- Corregido error 404 en reportes de ventas por marca y categoría.
- Corregido recorte de marca de agua en remitos impresos en papel tamaño Carta.
- Corregida pérdida de items al actualizar el listado de remitos en tiempo real.
- Corregido error al cargar presupuestos con listas de precio nuevas.

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
