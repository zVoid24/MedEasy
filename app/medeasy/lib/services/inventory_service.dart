import 'dart:convert';

import '../core/http_client.dart';
import '../models/inventory_item.dart';

class InventoryService {
  Future<void> addInventory({
    required String token,
    required int medicineId,
    required int quantity,
    required double costPrice,
    required double salePrice,
    required String expiryDate,
  }) async {
    final client = ApiClient(token: token);
    final response = await client.post('/inventory', {
      'medicine_id': medicineId,
      'quantity': quantity,
      'cost_price': costPrice,
      'sale_price': salePrice,
      'expiry_date': expiryDate,
    });
    if (response.statusCode != 201) {
      throw ApiError(_messageFromResponse(response.body));
    }
  }

  Future<List<InventoryItem>> searchInventory({
    required String token,
    String query = '',
  }) async {
    final client = ApiClient(token: token);
    final response = await client.get(
      '/inventory/search',
      params: query.isEmpty ? null : {'query': query},
    );
    if (response.statusCode != 200) {
      throw ApiError(_messageFromResponse(response.body));
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded.map((e) => InventoryItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  String _messageFromResponse(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      return decoded['error'] as String? ?? 'Unexpected error';
    } catch (_) {
      return 'Unexpected error';
    }
  }
}
