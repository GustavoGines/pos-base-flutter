<?php
$file = 'lib/features/pos/presentation/widgets/checkout_dialog.dart';
$content = file_get_contents($file);

$pattern = '/(Wrap\(\s*alignment: WrapAlignment\.spaceBetween,\s*crossAxisAlignment: WrapCrossAlignment\.center,\s*spacing: 8,\s*runSpacing: 4,\s*children: \[\s*ConstrainedBox\(.*?\),)\s*(TextButton\.icon\(\s*key: const Key\(\'select_customer_fiscal_btn\'\).*?onPressed: _openCustomerPicker,\s*\),)/s';

if (preg_match($pattern, $content, $matches)) {
    $replacement = $matches[1] . "\n                  Wrap(\n                    spacing: 4,\n                    children: [\n                      " . trim($matches[2]) . ",\n                      if (_selectedCustomer != null)\n                        TextButton.icon(\n                          icon: const Icon(Icons.person_remove, size: 16, color: Colors.red),\n                          label: const Text('Quitar', style: TextStyle(color: Colors.red)),\n                          style: TextButton.styleFrom(\n                            visualDensity: VisualDensity.compact,\n                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),\n                          ),\n                          onPressed: () {\n                            setState(() {\n                              _selectedCustomer = null;\n                              _fiscalDocType = 99; // Consumidor Final\n                              _fiscalDocNumberCtrl.clear();\n                              _fiscalReceiverNameCtrl.clear();\n                              _fiscalTaxCondition = 'consumidor_final';\n                              _fiscalReceiverAddressCtrl.clear();\n                            });\n                          },\n                        ),\n                    ],\n                  ),";
    $content = str_replace($matches[0], $replacement, $content);
    file_put_contents($file, $content);
    echo "Successfully updated CheckoutDialog.\n";
} else {
    echo "Pattern not found.\n";
}
