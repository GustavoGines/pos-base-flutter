# 🚀 Sistema POS - Frontend (Desktop / Flutter)

Este repositorio contiene el **Frontend** del Sistema POS, una solución de Punto de Venta de grado empresarial construida con **Flutter** para entornos de escritorio (Windows/Linux/macOS), optimizado para velocidad, seguridad y operaciones con hardware in-situ.

## ✨ Características Principales

### 🔐 Seguridad y Auth In-Place
- **Roles y Permisos:** Acceso mediante PIN digital de 4 dígitos. Interfaces bloqueadas por rol (Admin vs Cajeros).
- **Admin PIN Dialog:** Autorización "en caliente" (ej: anular tickets sin cerrar la sesión en curso del cajero).

### 🛒 Terminal POS y Venta Ágil
- **Order Recall (Preventa):** Arquitectura Cliente-Servidor donde la terminal o un dispositivo móvil puede "Dejar en Espera" una orden; la Caja Central recibe la alerta mediante *Polling Automático* y puede recuperar la orden para cobrar, ajustándose el stock atómicamente si hay devoluciones parciales en ventanilla.
- **Smart Search Bar:** Búsqueda asíncrona por código de barras o substrings del nombre del ítem.

### ⚖️ Integración Nativa Multi-Balanza
- **Balanzas Offline (EAN-13):** Parsing automático de etiquetas (códigos inician con '20') leyendo precio y miligramos inyectados desde el lector.
- **Básculas Serial / COM:** Conexión nativa a balanzas de fiambrería por el puerto (COM) configurado vía `flutter_libserialport` detectando peso estable automáticamente.

### 🧮 Auditoría y Cierre de Caja (Z)
- Bloqueo de POS si el turno no fue aperturado (Fondo Inicial).
- Matemática en tiempo real de cuadrícula (Ventas Netas - Fondo). 
- Historial exhaustivo de Turnos Cerrados, visualización de tickets procesados y status de Cuadre Exacto, Sobrante o Faltante por sesión/usuario.

### 📦 Gestión Completa de Catálogo
- CRUD dinámico. Parámetros de costo, precio final con IVA, categorías, y tags de Venta al Peso o Venta Unitaria.
- **Bulk Update:** Actualización masiva de precios en porcentaje (filtro por categorías/marcas).
- Carga y mermas de stock transaccionales.

### 🖨️ Servicios Low-Level de Impresión Térmica
- Generación de Tickets Z e Históricos inyectando perfiles HEX con cortador dinámico usando `esc_pos_utils_plus` directamente en red Wi-Fi LAN / IP térmica o adaptadores crudos paralelos configurados desde la app.

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
