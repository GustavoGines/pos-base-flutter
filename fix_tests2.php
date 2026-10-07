<?php
$file = 'test/features/pos/checkout_fiscal_invoice_test.dart';
$content = file_get_contents($file);
$content = preg_replace('/^\s*await tester\.ensureVisible\(find\.byKey\(\)\)\);\n/m', '', $content);
file_put_contents($file, $content);
