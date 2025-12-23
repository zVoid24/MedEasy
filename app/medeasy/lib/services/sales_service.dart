import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config.dart';

class SalesService {
  Future<Map<String, dynamic>> createSale({
    required String token,
    required List<Map<String, dynamic>> items,
    required double discountPercent,
    required double paidAmount,
    required double roundOff,
  }) async {
    final url = Uri.parse('${AppConfig.apiBaseUrl}/sales');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'items': items,
        'discount_percent': discountPercent,
        'paid_amount': paidAmount,
        'round_off': roundOff,
      }),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      final body = jsonDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to create sale');
    }
  }

  Future<List<dynamic>> getSales(
    String token, {
    String? startDate,
    String? endDate,
  }) async {
    String query = '';
    if (startDate != null && endDate != null) {
      query = '?start_date=$startDate&end_date=$endDate';
    }

    final url = Uri.parse('${AppConfig.apiBaseUrl}/reports/sales$query');

    final response = await http.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      final body = jsonDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to fetch sales');
    }
  }
}
