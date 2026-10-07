<?php
$file = 'test/features/pos/checkout_fiscal_invoice_test.dart';
$content = file_get_contents($file);

$targets = [
    "'Factura Fiscal ARCA'",
    "'Factura A'",
    "'Factura B'",
    "'Factura C'",
];

foreach ($targets as $t) {
    $search = "await tester.tap(find.text($t));";
    $replace = "await tester.ensureVisible(find.text($t));\n        await tester.tap(find.text($t));";
    $content = str_replace($search, $replace, $content);
}

// For keys
$keys = [
    "'fiscal_doc_number_field'",
    "'fiscal_receiver_name_field'",
    "'fiscal_receiver_address_field'",
];

foreach ($keys as $k) {
    $search = "await tester.enterText(find.byKey(const Key($k))";
    $replace = "await tester.ensureVisible(find.byKey(const Key($k)));\n        await tester.enterText(find.byKey(const Key($k))";
    $content = str_replace($search, $replace, $content);
}

file_put_contents($file, $content);
