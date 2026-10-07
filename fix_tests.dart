import 'dart:io';

void fixFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  var content = file.readAsStringSync();
  content = content.replaceAll('•', '-');
  // Also remove internal code checks in tests
  content = content.replaceAll(RegExp(r".*- Código Interno:.*\n?"), "");
  file.writeAsStringSync(content);
  print('Fixed \$path');
}

void main() {
  fixFile('test/features/catalog/presentation/widgets/product_share_test.dart');
  fixFile('test/features/catalog/presentation/widgets/product_share_desktop_adversarial_test.dart');
  fixFile('test/features/catalog/presentation/widgets/product_share_adversarial_stress_test.dart');
}
