<?php
$files = [
    'test/features/settings/presentation/pages/settings_afip_certificates_upload_test.dart',
    'test/features/settings/presentation/pages/settings_integrations_test.dart'
];

foreach ($files as $file) {
    $content = file_get_contents($file);
    // Find where the integration tab is tapped
    $pattern = '/await tester\.tap\(find\.text\(\'Integraciones\'\)\);\s*await tester\.pumpAndSettle\(\);/s';
    
    // We add a tap on 'Mercado Pago' and 'ARCA / AFIP (Facturaci\x{00F3}n Electr\x{00F3}nica)'
    $replacement = "await tester.tap(find.text('Integraciones'));\n      await tester.pumpAndSettle();\n      await tester.tap(find.text('Mercado Pago', skipOffstage: false).first);\n      await tester.tap(find.textContaining('ARCA / AFIP').first);\n      await tester.pumpAndSettle();";
    
    $content = preg_replace($pattern, $replacement, $content);
    file_put_contents($file, $content);
}
echo "Tests patched.\n";
