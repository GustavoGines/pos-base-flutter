import os
import re

replacements = [
    (re.compile(r'conexi.n'), 'conexión'),
    (re.compile(r'est. encendido'), 'está encendido'),
    (re.compile(r'Categor.a'), 'Categoría'),
    (re.compile(r'Categor.as'), 'Categorías'),
    (re.compile(r'c.digo'), 'código'),
    (re.compile(r'.xito'), 'éxito'),
    (re.compile(r'm.dulo'), 'módulo'),
    (re.compile(r'detect.'), 'detectó'),
    (re.compile(r'anomal.a'), 'anomalía'),
    (re.compile(r'suscripci.n'), 'suscripción'),
    (re.compile(r'ingres. una'), 'ingresá una'),
    (re.compile(r'v.lida'), 'válida'),
    (re.compile(r'SESI..N'), 'SESIÓN'),
    (re.compile(r't.cnico'), 'técnico'),
    (re.compile(r'encontr.'), 'encontró'),
    (re.compile(r'acci.n'), 'acción'),
    (re.compile(r'Configuraci.n'), 'Configuración'),
    (re.compile(r'M.vil'), 'Móvil'),
    (re.compile(r'CR.TICO'), 'CRÍTICO'),
    (re.compile(r'Inicializaci.n'), 'Inicialización'),
    (re.compile(r'fall.'), 'falló'),
    (re.compile(r'.nicamente'), 'únicamente'),
    (re.compile(r'migraci.n'), 'migración'),
    (re.compile(r'sesi.n'), 'sesión'),
    (re.compile(r'autom.ticamente'), 'automáticamente'),
    (re.compile(r'excepci.n'), 'excepción'),
    (re.compile(r'inv.lida'), 'inválida'),
    (re.compile(r'Verific. tu'), 'Verificá tu'),
]

count = 0
for root, _, files in os.walk(r'c:\laragon\www\Sistema_POS\pos-frontend\lib'):
    for file in files:
        if file.endswith('.dart'):
            path = os.path.join(root, file)
            try:
                with open(path, 'r', encoding='utf-8', errors='replace') as f:
                    content = f.read()
                
                changed = False
                for pattern, repl in replacements:
                    new_content, n = pattern.subn(repl, content)
                    if n > 0:
                        content = new_content
                        changed = True
                
                if changed:
                    with open(path, 'w', encoding='utf-8') as f:
                        f.write(content)
                    count += 1
            except Exception as e:
                pass
print(f'Fixed {count} files.')
