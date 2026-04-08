import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:frontend_desktop/core/network/api_client.dart';

/// Entidad liviana para usar en la pantalla de presupuestos.
class QuoteItem {
  final int? productId;
  final String productName;
  final double unitPrice;
  final double quantity;
  final double subtotal;

  QuoteItem({
    this.productId,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    required this.subtotal,
  });

  Map<String, dynamic> toJson() => {
        if (productId != null) 'product_id': productId,
        'product_name': productName,
        'unit_price': unitPrice,
        'quantity': quantity,
      };
}

class Quote {
  final int id;
  final String quoteNumber;
  final String status;
  final double subtotal;
  final double total;
  final String? customerName;
  final String? customerPhone;
  final String? notes;
  final String? validUntil;
  final List<QuoteItem> items;
  final String? createdAt;

  Quote({
    required this.id,
    required this.quoteNumber,
    required this.status,
    required this.subtotal,
    required this.total,
    this.customerName,
    this.customerPhone,
    this.notes,
    this.validUntil,
    required this.items,
    this.createdAt,
  });

  factory Quote.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List? ?? [];
    return Quote(
      id: json['id'] as int,
      quoteNumber: json['quote_number']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      subtotal: double.tryParse(json['subtotal']?.toString() ?? '0') ?? 0,
      total: double.tryParse(json['total']?.toString() ?? '0') ?? 0,
      customerName: json['customer_name']?.toString(),
      customerPhone: json['customer_phone']?.toString(),
      notes: json['notes']?.toString(),
      validUntil: json['valid_until']?.toString(),
      createdAt: json['created_at']?.toString(),
      items: rawItems.map((i) => QuoteItem(
        productId: i['product_id'] as int?,
        productName: i['product_name']?.toString() ?? '',
        unitPrice: double.tryParse(i['unit_price']?.toString() ?? '0') ?? 0,
        quantity: double.tryParse(i['quantity']?.toString() ?? '1') ?? 1,
        subtotal: double.tryParse(i['subtotal']?.toString() ?? '0') ?? 0,
      )).toList(),
    );
  }
}

/// Repositorio HTTP simple para presupuestos.
class QuoteRepository {
  final String baseUrl;
  final ApiClient client;

  QuoteRepository({required this.baseUrl, required this.client});

  String get _base => '$baseUrl/api/quotes';

  Future<Quote> createQuote({
    required List<QuoteItem> items,
    String? customerName,
    String? customerPhone,
    String? notes,
    String? validUntil,
    int? userId,
  }) async {
    final body = jsonEncode({
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'notes': notes,
      'valid_until': validUntil,
      'user_id': userId,
      'items': items.map((i) => i.toJson()).toList(),
    });

    final response = await client.post(
      Uri.parse(_base),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode == 201) {
      return Quote.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    throw Exception('Error al guardar presupuesto: ${response.body}');
  }

  Future<List<Quote>> listQuotes({String? search, String? status}) async {
    final params = <String, String>{};
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (status != null && status.isNotEmpty) params['status'] = status;

    final uri = Uri.parse(_base).replace(queryParameters: params.isEmpty ? null : params);
    final response = await client.get(uri);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final rawList = data['data'] as List? ?? [];
      return rawList.map((j) => Quote.fromJson(j as Map<String, dynamic>)).toList();
    }
    throw Exception('Error al cargar presupuestos');
  }
}
