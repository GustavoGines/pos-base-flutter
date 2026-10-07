<?php
$file = 'lib/features/settings/presentation/pages/settings_screen.dart';
$content = file_get_contents($file);

// Find the SwitchListTile for MP
$patternMp = '/\/\/ Switch Habilitar Cobro QR\s*SwitchListTile\([\s\S]*?onChanged: \(val\) \{[\s\S]*?\}\),\s*const SizedBox\(height: 16\),/u';
$content = preg_replace($patternMp, '', $content);

// Find the SwitchListTile for AFIP
$patternAfip = '/\/\/ Switch Habilitar Facturación ARCA\s*SwitchListTile\([\s\S]*?onChanged: \(val\) \{[\s\S]*?\}\),\s*const SizedBox\(height: 16\),/u';
$content = preg_replace($patternAfip, '', $content);

// also fallback with raw string match if regex fails due to charset issues
$patternAfip2 = '/\/\/ Switch Habilitar Facturaci\x{00F3}n ARCA\s*SwitchListTile\([\s\S]*?onChanged: \(val\) \{[\s\S]*?\}\),\s*const SizedBox\(height: 16\),/u';
$content = preg_replace($patternAfip2, '', $content);

$patternAfip3 = '/\/\/ Switch Habilitar Facturaci.*?\s*SwitchListTile\([\s\S]*?onChanged: \(val\) \{[\s\S]*?\}\),\s*const SizedBox\(height: 16\),/u';
$content = preg_replace($patternAfip3, '', $content);


file_put_contents($file, $content);
echo "Duplicate switches removed.\n";
