import 'package:flutter/foundation.dart';

import '../models/sale_report.dart';
import '../services/report_service.dart';

class ReportProvider extends ChangeNotifier {
  final _service = ReportService();

  Map<String, dynamic>? _daily;
  Map<String, dynamic>? _monthly;
  List<SaleReportEntry> _range = [];
  bool _loading = false;
  String? _error;

  Map<String, dynamic>? get daily => _daily;
  Map<String, dynamic>? get monthly => _monthly;
  List<SaleReportEntry> get range => _range;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> loadDaily(String token) async {
    await _wrap(() async => _daily = await _service.daily(token));
  }

  Future<void> loadMonthly(String token) async {
    await _wrap(() async => _monthly = await _service.monthly(token));
  }

  Future<void> loadRange(String token, {String? start, String? end}) async {
    await _wrap(() async => _range = await _service.range(token: token, start: start, end: end));
  }

  Future<void> _wrap(Future<void> Function() action) async {
    _loading = true;
    notifyListeners();
    try {
      await action();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
