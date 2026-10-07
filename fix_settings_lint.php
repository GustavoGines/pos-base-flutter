<?php
$file = 'test/features/settings/presentation/pages/settings_adversarial_challenge_test.dart';
$content = file_get_contents($file);
$content = str_replace('BusinessSettings? _settings;', 'final BusinessSettings? _settings;', $content);
file_put_contents($file, $content);
echo "Done.\n";
