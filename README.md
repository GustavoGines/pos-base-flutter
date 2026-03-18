# 🚀 Sistema POS - Frontend (Desktop / Flutter)

Este repositorio contiene el **Frontend** del Sistema POS, una solución de Punto de Venta de grado empresarial construida con **Flutter** para entornos de escritorio (Windows/Linux/macOS), optimizado para velocidad, seguridad y operaciones con hardware in-situ.

## ✨ Características Principales

### 🔐 Seguridad y Auth In-Place
- **Roles y Permisos:** Acceso mediante PIN digital de 4 dígitos. Interfaces bloqueadas por rol (Admin vs Cajeros).
- **Admin PIN Dialog:** Autorización "en caliente" (ej: anular tickets sin cerrar la sesión en curso del cajero).

### 🛒 Terminal POS y Venta Ágil
- **Order Recall (Preventa):** Arquitectura Cliente-Servidor donde la terminal o un dispositivo móvil puede "Dejar en Espera" una orden; la Caja Central recibe la alerta mediante *Polling Automático* y puede recuperar la orden para cobrar, ajustándose el stock atómicamente si hay anulaciones.
- **Eco-Friendly Checkout:** Integración visual para desactivar selectivamente la impresión térmica por venta a petición del cliente.

### 📦 Gestión de Catálogo Nivel Enterprise
- **Server-Side Pagination & Search:** Motor de búsqueda asíncrono (debounced) sobre Laravel procesando miles de registros sin estresar la memoria del dispositivo.
- **Flex Responsive UI:** Tabla de productos vectorizada y elástica (Flex Layout) que se adapta matemáticamente al redimensionamiento en pantallas 4K o 1080p sin "Layout Shifts", ocultando el texto desbordado automáticamente.
- **Interactive Server-Side Sorting:** Cabeceras de tabla clickeables (Nombre, Código de Barras, Categoría, Precio, Stock, Balanza, Activo) recargando la vista desde la base de datos de manera segura y sin inyecciones SQL.
- **Bulk Update:** Actualización masiva de precios en porcentaje (filtro por categorías/marcas) ejecutada en backend.

### ⚖️ Integración Nativa Multi-Balanza
- **Balanzas Offline (EAN-13):** Parsing automático de etiquetas dinámicas leyendo precio y miligramos inyectados desde el lector.
- **Básculas Serial / COM:** Conexión nativa a balanzas de mostrador por puerto RS-232 configurado a 9600 bps vía `flutter_libserialport`.

### 🧮 Auditoría y Cierre de Caja (Z)
- Bloqueo de terminal si no existe un turno fiscal abierto.
- Aislamiento de métricas: División matemática transaccional entre Ventas Físicas (Caja), Transferencias y Tarjetas de Crédito para el total esperado (`$expectedCash`).
- Historial exhaustivo y estado de cuadre (Sobrante/Faltante).

### 🖨️ Servicios Low-Level de Impresión Térmica
- Generación de Tickets Z e Históricos inyectando perfiles HEX con cortador dinámico (`generator.cut()`) usando `esc_pos_utils_plus`.
- **Modo Red / TCP:** Conexión por IP térmica con *Socket Timeouts* ajustados a 3 segundos para prevenir el congelamiento del SO si el hardware se desconecta.
- **Aislamiento Fail-Safe (Resiliencia):** Los errores físicos de la impresora (sin papel, apagada) están aislados del `PosProvider`. Si la impresión falla, la transacción en Base de Datos se mantiene intacta, mostrando un *SnackBar* naranja notificando el fallo local sin paralizar el cobro del cliente.

## 🛠 Instalación y Configuración Local

### Requisitos previos
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (versión 3.x+) instalado.
- Soporte para build de Escritorio habilitado (`flutter config --enable-windows-desktop`).

### Pasos
1. Clonar el repositorio.
2. Descargar dependencias:
   ```bash
   flutter pub get
   ```
3. Configurar Endpoint del Backend:
   Verifica el archivo de entorno o `pos_remote_datasource.dart` (u origen base) apuntando a tu servidor Laravel (ej. `http://127.0.0.1:8000/api`).
4. Build de C/C++ Serial:
   En el primer arranque, Flutter compilará en CMake el envoltorio de `libserialport`.
5. Ejecutar la APP en modo Desktop:
   ```bash
   flutter run -d windows
   ```

---
*Producido y diseñado para entornos transaccionales ágiles y robustos.*
