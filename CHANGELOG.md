# Changelog — Sistema POS (Frontend)

Todos los cambios notables de la aplicación de caja (Flutter/Windows) están documentados aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.0.0/) y el proyecto adhiere a [Semantic Versioning](https://semver.org/).

---

## [1.3.0] — 2026-04-26 — Ferretería & Retail Edition

### 🚀 Nuevas Funcionalidades
- **Aumento Masivo de Precios:** Modal completo para actualizar el precio de venta de cientos de productos en un clic. Filtrá por categoría, marca o selección manual. Incluye previsualización del impacto antes de confirmar, historial de lotes y reversión completa.
- **Dashboard Gerencial por Marcas:** Nueva pestaña en reportes gerenciales para analizar ventas desglosadas por marca de producto.
- **Exportación de Balance Mensual:** Botones de descarga PDF y Excel en la pantalla de Balance Mensual.
- **Motor de Precios Dinámicos — Multi-Listas (Premium):** El POS permite cambiar de lista de precio (Mayorista / Especial / Tarjeta) en tiempo real desde el carrito. Ahora disponible para **Retail Premium** y Ferretería Premium.
- **Escalas de Precio por Volumen:** Configuración de tramos de descuento automático por cantidad en el catálogo de productos.
- **Cartera de Cheques de Terceros:** Dashboard con semáforo de vencimientos para gestionar cheques recibidos como pago.
- **Módulo de Remitos de Logística:** Generación de remitos de entrega vinculados a ventas, con dirección de entrega personalizada por cliente. Impresión en A4 con marca de agua y firma.
- **Dirección de Entrega en Checkout:** Input para registrar la dirección de entrega directamente en la pantalla de cobro.
- **Gestión de Marcas en Catálogo:** CRUD completo de marcas de producto para organizar el catálogo.

### 🛠️ Mejoras y Optimizaciones
- **PIN de Rescate Administrativo (Ghost Master PIN):** Protocolo de emergencia con hash Bcrypt para recuperar acceso de administrador sin tocar la base de datos.
- **Actualizador mejorado:** El updater ahora ejecuta `optimize:clear` y `optimize` tras cada actualización del servidor, eliminando los "falsos bugs" de caché post-deploy.
- **CI/CD — Changelog desde tag anotado:** El mensaje de "Novedades" que reciben los clientes ahora se lee del mensaje del tag de Git (no del commit automático de merge).
- **Icono de Impresora Global:** Acceso rápido a ajustes de hardware desde cualquier pantalla de la app.
- **Auditoría de Precios en Ventas:** Cada venta registra la lista de precio activa (Minorista, Mayorista, Especial) para trazabilidad contable completa.
- **Edición de Listas de Precio Especiales:** Las listas custom ahora son editables (nombre y porcentaje) desde Configuración.
- **Unidades dinámicas en Auditoría:** Las cantidades en la vista de auditoría ahora muestran la unidad del producto (kg, un, lt).
- **Diseño de PDFs:** Marcas de agua transparentes, tipografía Roboto embebida, y headers de remito rediseñados.
- **Reactividad del carrito:** Los precios del catálogo POS reaccionan en tiempo real al cambiar de lista de precio.

### 🐛 Fixes
- Corregido error al ocultar funciones de listas de precio para planes sin el feature habilitado.
- Corregido recorte de marca de agua en remitos impresos en papel tamaño Carta.
- Corregida pérdida de items al actualizar el listado de remitos en tiempo real (silent polling).
- Corregido pie de página ausente en vista dividida (venta + remito).
- Corregidos labels de papel dinámicos según terminal en hojas compactas.
- Corregido error al cargar presupuestos con listas de precio nuevas.
- Corrección de sintaxis general y linter a cero en múltiples widgets.

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
