import 'package:flutter/foundation.dart';
import '../services/sales_service.dart';

class SalesProvider extends ChangeNotifier {
  final _service = SalesService();

  bool _saving = false;
  String? _error;

  bool get saving => _saving;
  String? get error => _error;

  Future<void> createSale({
    required String token,
    required List<Map<String, dynamic>> items,
    required double discountPercent,
    required double paidAmount,
    required double roundOff,
  }) async {
    _saving = true;
    _error = null;
    notifyListeners();
    try {
      await _service.createSale(
        token: token,
        items: items,
        discountPercent: discountPercent,
        paidAmount: paidAmount,
        roundOff: roundOff,
      );
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}
