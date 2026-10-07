<?php
$file = 'lib/features/pos/presentation/widgets/checkout_dialog.dart';
$content = file_get_contents($file);
$content = str_replace('),,', '),', $content);
file_put_contents($file, $content);
