import 'dart:convert';

import '../core/http_client.dart';
import '../models/sale_report.dart';

class ReportService {
  Future<Map<String, dynamic>> daily(String token) async {
    final client = ApiClient(token: token);
    final response = await client.get('/reports/sales/daily');
    if (response.statusCode != 200) {
      throw ApiError('Unable to load daily report');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> monthly(String token) async {
    final client = ApiClient(token: token);
    final response = await client.get('/reports/sales/monthly');
    if (response.statusCode != 200) {
      throw ApiError('Unable to load monthly report');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<SaleReportEntry>> range({
    required String token,
    String? start,
    String? end,
  }) async {
    final client = ApiClient(token: token);
    final response = await client.get('/reports/sales', params: {
      if (start != null && start.isNotEmpty) 'start_date': start,
      if (end != null && end.isNotEmpty) 'end_date': end,
    });
    if (response.statusCode != 200) {
      throw ApiError('Unable to load report');
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded.map((e) => SaleReportEntry.fromJson(e as Map<String, dynamic>)).toList();
  }
}
