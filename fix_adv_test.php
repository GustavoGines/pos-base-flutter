<?php
$file = 'test/features/settings/presentation/pages/settings_adversarial_challenge_test.dart';
if (!file_exists($file)) {
    echo "File not found.";
    exit;
}
$content = file_get_contents($file);
$content = str_replace('id: 1,', '', $content);
$content = str_replace("import 'dart:convert';", '', $content);
file_put_contents($file, $content);
echo "Fixed test file.\n";
