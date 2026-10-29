import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/features/catalog/data/models/product_model.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/offers/data/models/offer_model.dart';
import 'package:frontend_desktop/features/offers/data/offer_repository.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';

/// OF-01: el filtro "Ofertas" del Acceso Rápido no debe depender de que el producto en oferta
/// esté entre los 500 primeros del catálogo en memoria.
class _FakeOfferRepository extends Fake implements OfferRepository {
  final List<List<int>> requestedIds = [];
  Future<List<Product>> Function(List<int> ids)? handler;

  @override
  Future<List<Product>> getProductsByIds(List<int> ids) {
    requestedIds.add(List<int>.from(ids));
    return handler?.call(ids) ?? Future.value(ids.map(_product).toList());
  }
}

Product _product(int id) => ProductModel(
      id: id,
      name: 'Producto $id',
      internalCode: 'P-$id',
      costPrice: 50,
      sellingPrice: 100,
      stock: 10,
      active: true,
      isSoldByWeight: false,
    );

OfferModel _offer(int id, List<int> productIds, {List<String>? daysOfWeek}) {
  final now = DateTime.now();
  return OfferModel(
    id: id,
    name: 'Oferta $id',
    type: 'percentage',
    discountPercentage: 10,
    periodType: 'weekly',
    daysOfWeek: daysOfWeek,
    startDate: now.subtract(const Duration(hours: 1)),
    endDate: now.add(const Duration(days: 3)),
    isActive: true,
    products: productIds.map((pid) => {'id': pid, 'selling_price': '100.00'}).toList(),
  );
}

void main() {
  late _FakeOfferRepository repo;
  late OfferProvider provider;

  setUp(() {
    repo = _FakeOfferRepository();
    provider = OfferProvider(repository: repo);
  });

  test('trae solo los productos en oferta vigente que faltan en el catálogo en memoria', () async {
    provider.activeOffers.addAll([
      _offer(1, [267, 269, 276]),
      _offer(2, [999], daysOfWeek: ['non_existent_day']), // no vigente hoy
    ]);

    // OF-01: currentlyActiveOfferProductIds debe excluir ofertas no vigentes hoy
    expect(provider.currentlyActiveOfferProductIds, equals({267, 269, 276}));

    await provider.syncOfferOnlyProducts({1, 2, 267});

    expect(repo.requestedIds, [
      [269, 276]
    ]);
    expect(provider.offerOnlyProducts.map((p) => p.id), [269, 276]);
  });

  test('es idempotente si el conjunto faltante no cambió, y force vuelve a consultar', () async {
    provider.activeOffers.add(_offer(1, [269]));

    await provider.syncOfferOnlyProducts({1});
    await provider.syncOfferOnlyProducts({1, 2}); // mismo faltante [269]
    expect(repo.requestedIds.length, 1);

    await provider.syncOfferOnlyProducts({1}, force: true);
    expect(repo.requestedIds.length, 2);

    provider.invalidateOfferOnlyProducts();
    await provider.syncOfferOnlyProducts({1});
    expect(repo.requestedIds.length, 3);
  });

  test('si ya no falta ningún producto, vacía la lista sin consultar al servidor', () async {
    provider.activeOffers.add(_offer(1, [269]));
    await provider.syncOfferOnlyProducts({1});
    expect(provider.offerOnlyProducts, isNotEmpty);

    await provider.syncOfferOnlyProducts({1, 269}); // el catálogo ahora lo incluye
    expect(provider.offerOnlyProducts, isEmpty);
    expect(repo.requestedIds.length, 1);
  });

  test('ante error de red conserva la lista anterior y no reintenta en cada llamada', () async {
    provider.activeOffers.add(_offer(1, [269, 276]));
    await provider.syncOfferOnlyProducts({1, 276}); // trae [269]
    expect(provider.offerOnlyProducts.map((p) => p.id), [269]);

    repo.handler = (_) => Future.error(Exception('sin red'));
    await provider.syncOfferOnlyProducts({1}); // ahora faltan [269, 276] -> falla
    expect(provider.offerOnlyProducts.map((p) => p.id), [269]);

    await provider.syncOfferOnlyProducts({1}); // mismo faltante: no reintenta
    expect(repo.requestedIds.length, 2);
  });

  test('descarta una respuesta vieja si llegó otra sincronización después', () async {
    provider.activeOffers.add(_offer(1, [269, 276]));
    final slow = Completer<List<Product>>();
    repo.handler = (ids) => ids.length == 2 ? slow.future : Future.value(ids.map(_product).toList());

    final first = provider.syncOfferOnlyProducts({1}); // pide [269, 276] (lenta)
    await provider.syncOfferOnlyProducts({1, 276}); // pide [269] (rápida)
    slow.complete([_product(269), _product(276)]);
    await first;

    expect(provider.offerOnlyProducts.map((p) => p.id), [269]);
  });
}
