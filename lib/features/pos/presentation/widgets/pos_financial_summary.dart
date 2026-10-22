import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pos_provider.dart';
import 'package:frontend_desktop/core/utils/currency_formatter.dart';

class PosFinancialSummary extends StatelessWidget {
  const PosFinancialSummary({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PosProvider>(
      builder: (context, pos, _) {
        final grossSubtotal = pos.cartGrossSubtotal;
        final savings = pos.cartTotalSavings;
        final hasSavings = pos.hasCartDiscounts;
        final surcharge = pos.cartTotalSurcharge;
        final hasSurcharge = pos.hasCartSurcharges;
        final totalUnits = pos.cartTotalUnits;
        final itemCount = pos.cart.length;

        final appliesIibb = pos.appliesIibbPerception;
        final iibbAmount = pos.cartIibbPerceptionAmount;
        final iibbRate = pos.iibbPerceptionRate;

        final applyShipping = pos.currentRequiresDispatch && pos.currentFulfillmentStatus == 'pending' && pos.shippingCost > 0;
        final shippingCost = pos.shippingCost;

        final grandTotal = pos.cartTotal;

        if (pos.cart.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TOTAL:',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                  ),
                ),
                Text(
                  '\$0,00',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blueGrey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Encabezado con contador de ítems
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'RESUMEN DEL TICKET',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: Colors.blueGrey.shade600,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$itemCount art. (${totalUnits % 1 == 0 ? totalUnits.toInt() : totalUnits.toStringAsFixed(2)} un.)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Divider(height: 1, thickness: 0.8),
              const SizedBox(height: 4),

              // Subtotal Regular de Lista
              _buildRow(
                label: 'Subtotal Lista:',
                value: '\$${grossSubtotal.toCurrency()}',
                color: Colors.blueGrey.shade800,
                fontSize: 12.5,
              ),

              // Descuentos y Ofertas Aplicadas (si aplica)
              if (hasSavings) ...[
                const SizedBox(height: 2),
                _buildRow(
                  label: pos.activeTierDiscountLabel,
                  value: '-\$${savings.toCurrency()}',
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ],

              // Recargo por Lista de Precios (ej: Lista Tarjeta o Custom con incremento)
              if (hasSurcharge) ...[
                const SizedBox(height: 2),
                _buildRow(
                  label: pos.activeTierSurchargeLabel,
                  value: '+\$${surcharge.toCurrency()}',
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ],

              // Percepción IIBB (si aplica al cliente)
              if (appliesIibb && iibbAmount > 0) ...[
                const SizedBox(height: 2),
                _buildRow(
                  label: 'Percepción IIBB (${iibbRate.toStringAsFixed(1)}%):',
                  value: '+\$${iibbAmount.toCurrency()}',
                  color: Colors.orange.shade800,
                  fontSize: 12,
                ),
              ],

              // Flete logístico (si aplica)
              if (applyShipping) ...[
                const SizedBox(height: 2),
                _buildRow(
                  label: '🚚 Envío a Domicilio:',
                  value: '+\$${shippingCost.toCurrency()}',
                  color: Colors.blueGrey.shade700,
                  fontSize: 12,
                ),
              ],

              const SizedBox(height: 4),
              const Divider(height: 1, thickness: 1.2),
              const SizedBox(height: 4),

              // Fila destacada de TOTAL
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Text(
                    'TOTAL:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        '\$${grandTotal.toCurrency()}',
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF2E7D32), // Verde esmeralda moderno
                          letterSpacing: -0.5,
                        ),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRow({
    required String label,
    required String value,
    Color? color,
    FontWeight fontWeight = FontWeight.normal,
    double fontSize = 12.5,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              color: color ?? Colors.blueGrey.shade700,
              fontWeight: fontWeight,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight == FontWeight.normal ? FontWeight.w600 : fontWeight,
            color: color ?? Colors.blueGrey.shade900,
          ),
        ),
      ],
    );
  }
}
