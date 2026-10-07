import 'dart:io';

void main() {
  final file = File('lib/features/catalog/utils/product_share_helper.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll('- Precio: `\${', '- Precio: \\\$\${');
  content = content.replaceAll('- Mayorista: `\${', '- Mayorista: \\\$\${');
  content = content.replaceAll('- Tarjeta: `\${', '- Tarjeta: \\\$\${');
  file.writeAsStringSync(content);
  print('Done');
}
