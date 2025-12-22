import 'package:flutter/foundation.dart';

import '../models/inventory_item.dart';
import '../services/inventory_service.dart';

class InventoryProvider extends ChangeNotifier {
  final _service = InventoryService();

  bool _saving = false;
  bool _loading = false;
  String? _error;
  List<InventoryItem> _items = [];

  bool get saving => _saving;
  bool get loading => _loading;
  String? get error => _error;
  List<InventoryItem> get items => _items;

  Future<void> addInventory({
    required String token,
    required int medicineId,
    required int quantity,
    required double costPrice,
    required double salePrice,
    required String expiryDate,
  }) async {
    _saving = true;
    notifyListeners();
    try {
      await _service.addInventory(
        token: token,
        medicineId: medicineId,
        quantity: quantity,
        costPrice: costPrice,
        salePrice: salePrice,
        expiryDate: expiryDate,
      );
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<void> search({
    required String token,
    String query = '',
  }) async {
    _loading = true;
    notifyListeners();
    try {
      _items = await _service.searchInventory(token: token, query: query);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
