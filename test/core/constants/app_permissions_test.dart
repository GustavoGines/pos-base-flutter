import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/core/constants/app_permissions.dart';
import 'package:frontend_desktop/features/users/presentation/widgets/employee_form_dialog.dart';

void main() {
  group('AppPermissions & Matrix Specifications', () {
    test('AppPermissions.all contiene exactamente las 25 claves canónicas únicas', () {
      expect(AppPermissions.all.length, 25);
      final set = AppPermissions.all.toSet();
      expect(set.length, 25, reason: 'No deben existir claves duplicadas');

      // 1. Configuración (4)
      expect(AppPermissions.all.contains(AppPermissions.manageSettings), true);
      expect(AppPermissions.all.contains(AppPermissions.manageUsers), true);
      expect(AppPermissions.all.contains(AppPermissions.manageShifts), true);
      expect(AppPermissions.all.contains(AppPermissions.manageExpenseCategories), true);

      // 2. Finanzas (7)
      expect(AppPermissions.all.contains(AppPermissions.viewReports), true);
      expect(AppPermissions.all.contains(AppPermissions.viewExpenses), true);
      expect(AppPermissions.all.contains(AppPermissions.createExpenses), true);
      expect(AppPermissions.all.contains(AppPermissions.deleteCashMovements), true);
      expect(AppPermissions.all.contains(AppPermissions.manageCustomers), true);
      expect(AppPermissions.all.contains(AppPermissions.viewCustomersAccount), true);
      expect(AppPermissions.all.contains(AppPermissions.collectCustomerDebt), true);

      // 3. POS y Catálogo (6)
      expect(AppPermissions.all.contains(AppPermissions.applyDiscounts), true);
      expect(AppPermissions.all.contains(AppPermissions.manageCatalog), true);
      expect(AppPermissions.all.contains(AppPermissions.bulkPriceUpdate), true);
      expect(AppPermissions.all.contains(AppPermissions.adjustStock), true);
      expect(AppPermissions.all.contains(AppPermissions.viewKardex), true);
      expect(AppPermissions.all.contains(AppPermissions.voidSales), true);

      // 4. Proveedores (4)
      expect(AppPermissions.all.contains(AppPermissions.viewSuppliers), true);
      expect(AppPermissions.all.contains(AppPermissions.createSupplierInvoice), true);
      expect(AppPermissions.all.contains(AppPermissions.paySuppliers), true);
      expect(AppPermissions.all.contains(AppPermissions.manageDeliveryNotes), true);

      // 5. Cheques y Operaciones (4)
      expect(AppPermissions.all.contains(AppPermissions.viewChecks), true);
      expect(AppPermissions.all.contains(AppPermissions.endorseChecks), true);
      expect(AppPermissions.all.contains(AppPermissions.manageQuotes), true);
      expect(AppPermissions.all.contains(AppPermissions.manageTrash), true);
    });

    test('kCategorizedPermissions agrupa los 25 permisos en categorías granulares (> 5)', () {
      // Reorganización hacia más de 5 categorías lógicas y altamente específicas
      expect(kCategorizedPermissions.length, greaterThan(5));
      expect(kCategorizedPermissions.length, 9);

      final totalItems = kCategorizedPermissions.fold<int>(
        0,
        (sum, cat) => sum + cat.items.length,
      );
      expect(totalItems, 25);

      final allKeysInCategories = kCategorizedPermissions
          .expand((c) => c.items)
          .map((i) => i.key)
          .toSet();

      expect(allKeysInCategories.length, 25);
      expect(allKeysInCategories, AppPermissions.all.toSet());

      // R1: 'Categoría de Gastos' debe estar reubicada en su bloque natural (Caja Chica y Gastos)
      final gastosCat = kCategorizedPermissions.firstWhere(
        (c) => c.items.any((i) => i.key == AppPermissions.manageExpenseCategories),
      );
      expect(gastosCat.title.contains('Caja Chica') || gastosCat.title.contains('Gastos'), true);
      expect(gastosCat.items.any((i) => i.key == AppPermissions.viewExpenses), true);
      expect(gastosCat.items.any((i) => i.key == AppPermissions.createExpenses), true);
      expect(gastosCat.items.any((i) => i.key == AppPermissions.deleteCashMovements), true);

      // R1: Aislar 'Catálogo' de 'Stock'
      final catalogCat = kCategorizedPermissions.firstWhere(
        (c) => c.items.any((i) => i.key == AppPermissions.manageCatalog),
      );
      final stockCat = kCategorizedPermissions.firstWhere(
        (c) => c.items.any((i) => i.key == AppPermissions.adjustStock),
      );
      expect(identical(catalogCat, stockCat), false, reason: 'Catálogo y Stock deben estar aislados');
      expect(catalogCat.items.any((i) => i.key == AppPermissions.bulkPriceUpdate), true);
      expect(stockCat.items.any((i) => i.key == AppPermissions.viewKardex), true);

      // R1: Aislar 'Caja Chica' de 'Finanzas / Reportes'
      final reportsCat = kCategorizedPermissions.firstWhere(
        (c) => c.items.any((i) => i.key == AppPermissions.viewReports),
      );
      expect(identical(gastosCat, reportsCat), false, reason: 'Caja Chica debe estar aislada de Reportes/Finanzas');
    });

    test('kAllPermissions aplanada es compatible con vistas de empleados', () {
      expect(kAllPermissions.length, 25);
      for (final map in kAllPermissions) {
        expect(map.containsKey('key'), true);
        expect(map.containsKey('label'), true);
        expect(map.containsKey('description'), true);
        expect(map['key']!.isNotEmpty, true);
        expect(map['label']!.isNotEmpty, true);
      }
    });
  });
}
