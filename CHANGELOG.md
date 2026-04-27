# Changelog — Sistema POS (Frontend)

Todos los cambios notables de la aplicación de caja (Flutter/Windows) están documentados aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.0.0/) y el proyecto adhiere a [Semantic Versioning](https://semver.org/).

---

## [1.3.0] — 2026-04-26 — Ferretería & Retail Edition

### 🚀 Nuevas Funcionalidades
- **Aumento Masivo de Precios:** Actualizá cientos de productos en un clic desde la nueva pantalla. Filtrá, previsualizá el impacto y deshacé cambios si te equivocás.
- **Generación de Remitos:** Imprimí remitos de entrega tamaño A4 con marca de agua, firma y la dirección exacta del cliente directamente desde la caja.
- **Cartera de Cheques:** Nuevo dashboard visual con alertas de colores (semáforo) para llevar el control de vencimientos de todos los cheques recibidos.
- **Exportación de Reportes:** Descargá tu balance mensual completo en PDF y Excel con un solo clic, y analizá tus ventas por marca desde el nuevo dashboard gerencial.
- **Listas de Precio en Caja:** Cambiá la lista de precios (Minorista/Mayorista) desde el carrito de compras y mirá cómo reaccionan los precios en tiempo real.

### ✨ Mejoras Visuales
- **Dashboard Financiero Compacto:** Rediseñamos el panel de resumen en el Registro de Ventas. Las tarjetas de totales ahora son mucho más compactas y se organizan inteligentemente en bloque. Esto te permite ver todos los métodos de pago fácilmente sin robarle espacio vertical a la lista de tickets, permitiéndote ver muchas más ventas a la vez sin tener que hacer scroll.

### 🛠️ Mejoras de Estabilidad y Optimizaciones
- **Updater Auto-Reparable:** El actualizador ahora se auto-renombra para evadir bloqueos de Windows y la caja dispara un rescate automático de base de datos tras la actualización.
- **Sincronización Perfecta:** Mejoramos el motor de actualizaciones. Ahora el sistema detecta de forma mucho más inteligente y precisa la versión exacta que tenés instalada, garantizando que tu caja y tu servidor estén siempre sincronizados sin margen de error.
- **Actualizaciones 100% Confiables:** Eliminamos los "falsos avisos" de actualización. Tu sistema ahora verifica físicamente los archivos instalados antes de descargar cualquier novedad, brindándote una experiencia más fluida y segura.
- **Novedades Cómodas:** La ventana de actualizaciones (esta que estás leyendo) ahora es mucho más grande en pantallas de escritorio para mayor comodidad.
- **Ajustes Rápidos:** Agregamos un acceso directo con ícono de impresora en todas las pantallas para configurar el hardware al instante.
- **Visualización:** Ahora la auditoría muestra la unidad de medida (Kg, Lts) y los PDFs de venta mejoraron su diseño con marcas de agua más profesionales.

### 🐛 Fixes
- Corregido recorte de marca de agua en remitos impresos en papel tamaño Carta.
- Corregida pérdida visual de items al actualizar el listado de remitos.
- Corregido error visual donde los presupuestos no reflejaban el precio de listas nuevas.
- **Fix crítico OTA:** Eliminada la ruta hardcodeada `C:\laragon\www\...` del actualizador. La ruta del backend ahora se calcula dinámicamente relativa al ejecutable, garantizando compatibilidad con cualquier entorno de instalación.

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
