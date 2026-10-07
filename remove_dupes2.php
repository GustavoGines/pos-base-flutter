<?php
$file = 'lib/features/settings/presentation/pages/settings_screen.dart';
$content = file_get_contents($file);

$lines = explode(PHP_EOL, $content);
$new_lines = [];
$skip = false;
foreach ($lines as $line) {
    if (strpos($line, '// Switch Habilitar Cobro QR') !== false || strpos($line, '// Switch Habilitar Facturaci') !== false) {
        $skip = true;
        continue;
    }
    if ($skip) {
        if (strpos($line, 'onChanged: (val) {') !== false) {
            continue;
        }
        if (strpos($line, '  },') !== false) {
            continue;
        }
        if (strpos($line, '  ),') !== false) {
            continue;
        }
        if (strpos($line, '  const SizedBox(height: 16),') !== false) {
            $skip = false;
            continue;
        }
        continue; // skip other inner lines
    }
    $new_lines[] = $line;
}

file_put_contents($file, implode(PHP_EOL, $new_lines));
echo "Done.\n";
