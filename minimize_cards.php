<?php
$file = 'lib/features/settings/presentation/pages/settings_screen.dart';
$content = file_get_contents($file);

$content = str_replace('initiallyExpanded: _mpQrEnabled,', 'initiallyExpanded: false,', $content);
$content = str_replace('initiallyExpanded: _afipEnabled,', 'initiallyExpanded: false,', $content);

file_put_contents($file, $content);
echo "Done.\n";
