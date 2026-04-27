## 1.3.0

- **Auto-Sobreescritura:** El updater se renombra a `updater_old.exe` antes de extraer el ZIP, evitando el error "archivo en uso" de Windows.
- **Limpieza pre-migración:** Ejecuta `php artisan optimize:clear` antes de `migrate --force` para garantizar que no haya caché vieja que interfiera.
- **Captura de errores robusta:** Toda la salida de stdout/stderr de los comandos artisan queda impresa en el log de ejecución.

## 1.0.0

- Initial version.
