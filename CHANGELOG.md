# Changelog — Sistema POS (Frontend)
Todos los cambios notables de la aplicación de caja (Flutter/Windows) están documentados aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.0.0/) y el proyecto adhiere a [Semantic Versioning](https://semver.org/).

## [1.6.2] - 2026-08-26
### Fixed
- Aumentado el tiempo de espera del actualizador a 20 minutos para dar tiempo a que los servidores backend extraigan miles de archivos sin marcar error falso.
- Ajuste final de versiones para correcta sincronización del cliente y servidor.
# Changelog — Sistema POS (Frontend)
Todos los cambios notables de la aplicación de caja (Flutter/Windows) están documentados aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.0.0/) y el proyecto adhiere a [Semantic Versioning](https://semver.org/).

## [1.6.1] - 2026-08-26
### Fixed
- Corrección visual en la visualización de las Novedades de Actualización (eliminación de caracteres extraños).
# Changelog — Sistema POS (Frontend)
Todos los cambios notables de la aplicación de caja (Flutter/Windows) están documentados aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.0.0/) y el proyecto adhiere a [Semantic Versioning](https://semver.org/).

## [1.6.0] - 2026-08-26
### Added
- Nuevo Sistema de Canales de Actualización (Estable / Beta) integrado.
- Soporte oficial para despliegues móviles integrados con el servidor.

### Changed
- Mejorada la experiencia de usuario: el sonido del escáner en auditorías y control de stock ahora suena natural y reacciona sin latencia.
- Optimización de Rendimiento: Limitador de peticiones silenciosas que reduce drásticamente el consumo de red y CPU del servidor al navegar entre pantallas.

### Fixed
- Seguridad Reforzada: Corrección en el Muro de Fuego que provocaba bloqueos erróneos de permisos de Acceso Remoto.

## [1.4.0] - 2026-08-21
### Nuevas Funcionalidades
- Sistema OTA (Over-The-Air): Actualización automática de frontend y backend desde el servidor de licencias central.
- Motor de Licencias (DRM): Validación de licencias con período de gracia de 72 horas, soporte para planes SaaS y Lifetime, y sincronización automática diaria.
- Feature Flags Server-Driven: La habilitación de módulos (Cuentas Corrientes, Presupuestos, Multi-Caja, etc.) se controla desde el servidor de licencias.
- Arquitectura Multi-Caja: Configuración de hardware (impresora, balanza, papel) independiente por terminal vía SharedPreferences.
- Caja Rápida (Fast POS): Modo de ingreso por código de barras sin confirmación de cantidad para comercios de alto volumen.