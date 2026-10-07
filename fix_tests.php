<?php
$file = 'test/features/pos/checkout_fiscal_invoice_test.dart';
$content = file_get_contents($file);
$content = str_replace('));;', ')));', $content);
$content = preg_replace('/ensureVisible\(find\.byKey\((.*?)\)\);/', 'ensureVisible(find.byKey()));', $content);
file_put_contents($file, $content);
