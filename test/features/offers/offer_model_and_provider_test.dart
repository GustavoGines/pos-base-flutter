import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:frontend_desktop/features/offers/data/models/offer_model.dart';
import 'package:frontend_desktop/features/offers/data/offer_repository.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';

class MockOfferRepository extends Mock implements OfferRepository {
  @override
  Future<Map<String, dynamic>> relaunchOffer({
    required int id,
    required String periodType,
    DateTime? startDate,
    DateTime? endDate,
    bool duplicate = false,
  }) => (super.noSuchMethod(
    Invocation.method(#relaunchOffer, [], {
      #id: id,
      #periodType: periodType,
      #startDate: startDate,
      #endDate: endDate,
      #duplicate: duplicate,
    }),
    returnValue: Future.value(<String, dynamic>{}),
    returnValueForMissingStub: Future.value(<String, dynamic>{}),
  ) as Future<Map<String, dynamic>>);

  @override
  Future<OfferModel> toggleOfferStatus(int id) => (super.noSuchMethod(
    Invocation.method(#toggleOfferStatus, [id]),
    returnValue: Future.value(OfferModel(id: id, name: '', type: 'percentage', periodType: 'daily', isActive: true)),
    returnValueForMissingStub: Future.value(OfferModel(id: id, name: '', type: 'percentage', periodType: 'daily', isActive: true)),
  ) as Future<OfferModel>);
}

void main() {
  group('OfferModel Tests', () {
    test('Calculates status correctly for active, expired, paused and scheduled', () {
      final now = DateTime.now();

      final activeOffer = OfferModel(
        id: 1,
        name: 'Promo Activa',
        type: 'percentage',
        discountPercentage: 10,
        periodType: 'daily',
        startDate: now.subtract(const Duration(hours: 1)),
        endDate: now.add(const Duration(hours: 5)),
        isActive: true,
      );
      expect(activeOffer.status, equals(OfferStatus.active));
      expect(activeOffer.isCurrentlyActive, isTrue);
      expect(activeOffer.statusLabel, contains('Activa'));

      final expiredOffer = OfferModel(
        id: 2,
        name: 'Promo Vencida',
        type: 'percentage',
        discountPercentage: 15,
        periodType: 'daily',
        startDate: now.subtract(const Duration(days: 3)),
        endDate: now.subtract(const Duration(days: 2)),
        isActive: true,
      );
      expect(expiredOffer.status, equals(OfferStatus.expired));
      expect(expiredOffer.isExpired, isTrue);
      expect(expiredOffer.statusLabel, contains('Vencida'));

      final pausedOffer = OfferModel(
        id: 3,
        name: 'Promo Pausada',
        type: 'percentage',
        discountPercentage: 20,
        periodType: 'weekly',
        startDate: now.subtract(const Duration(days: 1)),
        endDate: now.add(const Duration(days: 5)),
        isActive: false,
      );
      expect(pausedOffer.status, equals(OfferStatus.paused));
      expect(pausedOffer.isPaused, isTrue);
      expect(pausedOffer.statusLabel, contains('Pausada'));

      final scheduledOffer = OfferModel(
        id: 4,
        name: 'Promo Programada',
        type: 'percentage',
        discountPercentage: 25,
        periodType: 'weekly',
        startDate: now.add(const Duration(days: 2)),
        endDate: now.add(const Duration(days: 7)),
        isActive: true,
      );
      expect(scheduledOffer.status, equals(OfferStatus.scheduled));
      expect(scheduledOffer.isScheduled, isTrue);
      expect(scheduledOffer.statusLabel, contains('Programada'));

      // Precedencia: Una oferta vencida con isActive: false debe reportar expired y no paused
      final expiredAndPausedOffer = OfferModel(
        id: 5,
        name: 'Promo Vencida y Pausada',
        type: 'percentage',
        discountPercentage: 15,
        periodType: 'daily',
        startDate: now.subtract(const Duration(days: 5)),
        endDate: now.subtract(const Duration(days: 2)),
        isActive: false,
      );
      expect(expiredAndPausedOffer.status, equals(OfferStatus.expired));
      expect(expiredAndPausedOffer.isExpired, isTrue);
      expect(expiredAndPausedOffer.isPaused, isFalse);

      // Validación de daysOfWeek en isCurrentlyActive
      final otherWeekdayOffer = OfferModel(
        id: 6,
        name: 'Promo Otro Día',
        type: 'percentage',
        discountPercentage: 10,
        periodType: 'weekly',
        daysOfWeek: ['non_existent_day'],
        startDate: now.subtract(const Duration(hours: 1)),
        endDate: now.add(const Duration(days: 3)),
        isActive: true,
      );
      expect(otherWeekdayOffer.status, equals(OfferStatus.active));
      expect(otherWeekdayOffer.isCurrentDayValid, isFalse);
      expect(otherWeekdayOffer.isCurrentlyActive, isFalse);
    });

    test('Detects margin warnings when discount price drops below cost price', () {
      final riskyOffer = OfferModel(
        id: 5,
        name: 'Promo Riesgosa',
        type: 'percentage',
        discountPercentage: 50,
        periodType: 'daily',
        isActive: true,
        products: [
          {
            'id': 101,
            'name': 'Aceite Girasol 900ml',
            'selling_price': '1000.00',
            'cost_price': '600.00',
          },
        ],
      );

      // Precio venta 1000 con 50% de descuento = 500. Costo = 600.
      expect(riskyOffer.hasMarginWarning, isTrue);
      expect(riskyOffer.marginWarnings.length, equals(1));
      expect(riskyOffer.marginWarnings.first['product_name'], equals('Aceite Girasol 900ml'));
      expect(riskyOffer.marginWarnings.first['discounted_price'], equals(500.0));
      expect(riskyOffer.marginWarnings.first['cost_price'], equals(600.0));
    });
  });

  group('OfferProvider Unit Tests', () {
    late MockOfferRepository mockRepo;
    late OfferProvider provider;

    setUp(() {
      mockRepo = MockOfferRepository();
      provider = OfferProvider(repository: mockRepo);
    });

    test('relaunchOffer updates active and history lists smoothly', () async {
      final now = DateTime.now();
      final relanchedOffer = OfferModel(
        id: 10,
        name: 'Promo Relanzada',
        type: 'percentage',
        discountPercentage: 15,
        periodType: 'daily',
        startDate: now.subtract(const Duration(minutes: 5)),
        endDate: now.add(const Duration(hours: 10)),
        isActive: true,
      );

      when(mockRepo.relaunchOffer(
        id: 10,
        periodType: 'daily',
        duplicate: true,
      )).thenAnswer((_) async => {
        'offer': relanchedOffer,
        'margin_warnings': [],
      });

      final result = await provider.relaunchOffer(
        id: 10,
        periodType: 'daily',
        duplicate: true,
      );

      expect(result, isNotNull);
      expect(provider.activeOffers.length, equals(1));
      expect(provider.activeOffers.first.id, equals(10));
      expect(provider.allOffers.length, equals(1));
      expect(provider.allOffers.first.name, equals('Promo Relanzada'));
    });

    test('toggleOfferStatus moves paused offer out of active list', () async {
      final now = DateTime.now();
      final activeOffer = OfferModel(
        id: 15,
        name: 'Promo Para Pausar',
        type: 'percentage',
        discountPercentage: 10,
        periodType: 'daily',
        startDate: now.subtract(const Duration(minutes: 5)),
        endDate: now.add(const Duration(hours: 10)),
        isActive: true,
      );

      final pausedOffer = OfferModel(
        id: 15,
        name: 'Promo Para Pausar',
        type: 'percentage',
        discountPercentage: 10,
        periodType: 'daily',
        startDate: now.subtract(const Duration(minutes: 5)),
        endDate: now.add(const Duration(hours: 10)),
        isActive: false,
      );

      provider.activeOffers.add(activeOffer);
      provider.allOffers.add(activeOffer);

      when(mockRepo.toggleOfferStatus(15)).thenAnswer((_) async => pausedOffer);

      final success = await provider.toggleOfferStatus(15);
      expect(success, isTrue);
      expect(provider.activeOffers.any((o) => o.id == 15), isFalse);
      expect(provider.allOffers.firstWhere((o) => o.id == 15).isActive, isFalse);
    });
  });
}
