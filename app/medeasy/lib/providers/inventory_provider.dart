import 'package:flutter/foundation.dart';

import '../models/inventory_item.dart';
import '../services/database_helper.dart';
import '../services/inventory_service.dart';

class InventoryProvider extends ChangeNotifier {
  final _service = InventoryService();
  final _db = DatabaseHelper.instance;

  bool _saving = false;
  bool _loading = false;
  bool _searching = false;
  String? _error;
  List<InventoryItem> _items = [];
  List<InventoryItem> _searchResults = [];

  bool get saving => _saving;
  bool get loading => _loading;
  bool get searching => _searching;
  String? get error => _error;
  List<InventoryItem> get items => _items;
  List<InventoryItem> get searchResults => _searchResults;

  Future<void> loadInventory({required String token}) async {
    _loading = true;
    notifyListeners();

    // 1. Load from Local DB immediately
    try {
      _items = await _db.getInventory();
      notifyListeners(); // Show local data instantly
    } catch (e) {
      print('Error loading local inventory: $e');
    }

    // 2. Fetch from Backend
    try {
      // Empty query means load all
      final remoteItems = await _service.searchInventory(
        token: token,
        query: '',
      );

      // 3. Update Local DB
      await _db.insertInventory(remoteItems);

      // 4. Update UI with fresh data
      _items = remoteItems;
      _error = null;
    } catch (e) {
      // Only set error if we have no local data to show
      if (_items.isEmpty) {
        _error = e.toString();
      } else {
        print('Background sync failed: $e');
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> addInventory({
    required String token,
    int? medicineId,
    String? brandName,
    String? genericName,
    String? manufacturer,
    String? type,
    required int quantity,
    required double costPrice,
    required double salePrice,
    String? expiryDate,
  }) async {
    _saving = true;
    notifyListeners();
    try {
      await _service.addInventory(
        token: token,
        medicineId: medicineId,
        brandName: brandName,
        genericName: genericName,
        manufacturer: manufacturer,
        type: type,
        quantity: quantity,
        costPrice: costPrice,
        salePrice: salePrice,
        expiryDate: expiryDate ?? '',
      );
      // Refresh inventory after adding
      await loadInventory(token: token);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<void> search({required String token, String query = ''}) async {
    if (query.isEmpty) {
      clearSearch();
      return;
    }
    _searching = true;
    notifyListeners();
    try {
      // Search Local DB instead of API
      _searchResults = await _db.searchInventory(query);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _searching = false;
      notifyListeners();
    }
  }

  void clearSearch() {
    _searchResults = [];
    _searching = false;
    notifyListeners();
  }
}
