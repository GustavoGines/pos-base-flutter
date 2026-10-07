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

$lines = explode(PHP_EOL, $content);
foreach ($lines as $i => $line) {
    if (strpos($line, 'await tester.enterText(find.byKey') !== false) {
        preg_match('/find\.byKey\(.*?\)/', $line, $matches);
        if (isset($matches[0])) {
            $lines[$i] = "        await tester.ensureVisible(" . $matches[0] . ");" . PHP_EOL . $line;
        }
    }
}
$content = implode(PHP_EOL, $lines);

file_put_contents($file, $content);
