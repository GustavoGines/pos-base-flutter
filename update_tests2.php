<?php
$file = 'test/features/pos/checkout_fiscal_invoice_test.dart';
$content = file_get_contents($file);

$content = preg_replace(
    "/(await tester\.enterText\(find\.byKey\((.*?)\), .*?\);)/",
    "await tester.ensureVisible(find.byKey()); ",
    $content
);

file_put_contents($file, $content);
