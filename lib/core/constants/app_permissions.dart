class AppPermissions {
  // 1. Configuración y Administración
  static const String manageSettings = 'manage_settings';
  static const String manageUsers = 'manage_users';
  static const String manageShifts = 'manage_shifts';
  static const String manageExpenseCategories = 'manage_expense_categories';

  // 2. Finanzas, Caja Chica y Clientes
  static const String viewReports = 'view_reports';
  static const String viewExpenses = 'view_expenses';
  static const String createExpenses = 'create_expenses';
  static const String deleteCashMovements = 'delete_cash_movements';
  static const String manageCustomers = 'manage_customers';
  static const String viewCustomersAccount = 'view_customers_account';
  static const String collectCustomerDebt = 'collect_customer_debt';

  // 3. POS, Catálogo y Stock
  static const String applyDiscounts = 'apply_discounts';
  static const String manageCatalog = 'manage_catalog';
  static const String bulkPriceUpdate = 'bulk_price_update';
  static const String adjustStock = 'adjust_stock';
  static const String viewKardex = 'view_kardex';
  static const String voidSales = 'void_sales';

  // 4. Proveedores y Logística
  static const String viewSuppliers = 'view_suppliers';
  static const String createSupplierInvoice = 'create_supplier_invoice';
  static const String paySuppliers = 'pay_suppliers';
  static const String manageDeliveryNotes = 'manage_delivery_notes';

  // 5. Cheques, Presupuestos y Papelera
  static const String viewChecks = 'view_checks';
  static const String endorseChecks = 'endorse_checks';
  static const String manageQuotes = 'manage_quotes';
  static const String manageTrash = 'manage_trash';

  /// Lista exhaustiva de las 25 claves canónicas de permisos del sistema.
  static const List<String> all = [
    manageSettings,
    manageUsers,
    manageShifts,
    manageExpenseCategories,
    viewReports,
    viewExpenses,
    createExpenses,
    deleteCashMovements,
    manageCustomers,
    viewCustomersAccount,
    collectCustomerDebt,
    applyDiscounts,
    manageCatalog,
    bulkPriceUpdate,
    adjustStock,
    viewKardex,
    voidSales,
    viewSuppliers,
    createSupplierInvoice,
    paySuppliers,
    manageDeliveryNotes,
    viewChecks,
    endorseChecks,
    manageQuotes,
    manageTrash,
  ];
}
