import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';

void main() {
  group('CurrencyFormatter Extension Tests', () {
    
    group('toCurrency()', () {
      test('Debe omitir los decimales si el numero es un entero exacto', () {
        expect(1500.toCurrency(), '1.500');
        expect(1500.0.toCurrency(), '1.500');
        expect(0.toCurrency(), '0');
        expect(2.toCurrency(), '2');
      });

      test('Debe mostrar 2 decimales si el numero tiene una fraccion real', () {
        expect(1500.5.toCurrency(), '1.500,50');
        expect(120.75.toCurrency(), '120,75');
        expect(0.99.toCurrency(), '0,99');
        // El comportamiento por defecto de Intl es redondear si hay mas decimales
        expect(120.758.toCurrency(), '120,76'); 
      });
    });

    group('toQty()', () {
      test('Debe retornar la cantidad exacta sin decimales si es unidad entera', () {
        expect(1.toQty(), '1');
        expect(5.0.toQty(), '5');
        expect(25.000.toQty(), '25');
      });

      test('Debe mostrar decimales unicamente hasta el necesario para evitar ceros sobrantes', () {
        expect(1.5.toQty(), '1.5');
        expect(1.500.toQty(), '1.5');
        expect(2.25.toQty(), '2.25');
        expect(2.250.toQty(), '2.25');
      });

      test('Debe truncar a 3 decimales maximo (comportamiento de balanza)', () {
        expect(1.1234.toQty(), '1.123'); // Porque toQty hace toStringAsFixed(3)
        expect(0.333333.toQty(), '0.333');
      });
    });

    group('toInputFormat()', () {
      test('Debe formatear valores enteros sin puntos ni comas de miles', () {
        expect(2400.toInputFormat(), '2400');
        expect(2400.0.toInputFormat(), '2400');
      });

      test('Debe convertir el punto a coma decimal para inputs sin separador de miles', () {
        expect(2400.5.toInputFormat(), '2400,50');
        expect(2.4.toInputFormat(), '2,40');
      });
    });

    group('Fracciones universales y helpers (1/N)', () {
      test('parseQuantityOrFraction soporta fracciones, comas, decimales y rechaza inválidos', () {
        expect(parseQuantityOrFraction('1/16'), closeTo(0.0625, 1e-6));
        expect(parseQuantityOrFraction('3 / 16'), closeTo(0.1875, 1e-6));
        expect(parseQuantityOrFraction('0,0625'), closeTo(0.0625, 1e-6));
        expect(parseQuantityOrFraction('1/0'), isNull);
        expect(parseQuantityOrFraction('0'), isNull);
        expect(parseQuantityOrFraction('0', allowZero: true), 0.0);
        expect(parseQuantityOrFraction('abc'), isNull);
      });

      test('calcUnitsFitStock calcula 16 combos exactos con stock=1 y qty=0.063 (1/16 redondeado)', () {
        expect(calcUnitsFitStock(1.0, 0.063), 16);
        expect(calcUnitsFitStock(1.0, 1 / 16), 16);
        expect(calcUnitsFitStock(0.937, 0.063), 15);
        expect(calcUnitsFitStock(1.0, 0.167), 6);
        expect(calcUnitsFitStock(1.0, 0.050), 20);
        expect(calcUnitsFitStock(2.0, 0.042), 48); // 2 * 1/24
      });

      test('toUnitStockDisplay reconoce dieciseisavos (1/16, 15/16)', () {
        expect(0.0625.toUnitStockDisplay(), '1/16 u');
        expect(0.9375.toUnitStockDisplay(), '15/16 u');
        expect(0.937.toUnitStockDisplay(), '15/16 u');
      });

      test('formatQuantityInput conserva 0.0625 y redondea 1/6 a 0.167', () {
        expect(formatQuantityInput(1.0), '1');
        expect(formatQuantityInput(0.0625), '0.0625');
        expect(formatQuantityInput(0.167), '0.167');
        expect(roundQtyForStorage(0.0625), 0.063);
      });
    });

  });
}
