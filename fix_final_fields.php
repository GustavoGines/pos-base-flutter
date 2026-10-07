<?php
$file = 'test/features/settings/presentation/pages/settings_adversarial_challenge_test.dart';
$content = file_get_contents($file);
$content = str_replace('BusinessSettings _settings;', 'final BusinessSettings _settings;', $content);
$content = str_replace('bool _isLoading = false;', 'final bool _isLoading = false;', $content);
$content = str_replace('bool _isLoadingIntegrations = false;', 'final bool _isLoadingIntegrations = false;', $content);
file_put_contents($file, $content);
echo "Fields made final.\n";
