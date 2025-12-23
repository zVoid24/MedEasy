import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../services/database_helper.dart';
import '../services/sales_service.dart';

class SalesProvider extends ChangeNotifier {
  final _service = SalesService();
  final _db = DatabaseHelper.instance;

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
      // 1. Prepare Payload
      final payload = {
        'items': items,
        'discount_percent': discountPercent,
        'paid_amount': paidAmount,
        'round_off': roundOff,
      };

      // 2. Save to Local DB (Pending Sales)
      await _db.insertPendingSale(payload);

      // 3. Update Local Inventory (Optimistic UI)
      for (var item in items) {
        final invId = item['inventory_id'] as int;
        final qty = item['quantity'] as int;
        await _db.decrementInventoryQuantity(invId, qty);
      }

      // 4. Try Sync if Online
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        await syncPendingSales(token);
      }

      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<void> syncPendingSales(String token) async {
    try {
      final pending = await _db.getPendingSales();
      if (pending.isEmpty) return;

      for (var sale in pending) {
        final id = sale['id'] as int;
        final payload = jsonDecode(sale['payload'] as String);

        try {
          await _service.createSale(
            token: token,
            items: List<Map<String, dynamic>>.from(payload['items']),
            discountPercent: (payload['discount_percent'] as num).toDouble(),
            paidAmount: (payload['paid_amount'] as num).toDouble(),
            roundOff: (payload['round_off'] as num).toDouble(),
          );
          // Success: Remove from pending
          await _db.deletePendingSale(id);
        } catch (e) {
          print('Sync failed for sale $id: $e');
          // Check for permanent errors
          final errorStr = e.toString().toLowerCase();
          if (errorStr.contains('insufficient stock') ||
              errorStr.contains('400')) {
            print('Permanent error for sale $id. Deleting...');
            await _db.deletePendingSale(id);
          }
          // Otherwise keep in pending to retry later
        }
      }
    } catch (e) {
      print('Sync error: $e');
    }
  }

  // Sync last 5 days of sales for offline cache
  Future<void> syncRecentSales(String token) async {
    try {
      final now = DateTime.now();
      final endDate = now.toIso8601String().split('T')[0];
      final startDate = now
          .subtract(const Duration(days: 5))
          .toIso8601String()
          .split('T')[0];

      final sales = await _service.getSales(
        token,
        startDate: startDate,
        endDate: endDate,
      );
      await _db.insertSalesHistory(sales);
    } catch (e) {
      print('Sync recent sales failed: $e');
    }
  }

  Future<List<dynamic>> getSales(
    String token, {
    String? startDate,
    String? endDate,
  }) async {
    try {
      // 1. Try to fetch from backend
      final sales = await _service.getSales(
        token,
        startDate: startDate,
        endDate: endDate,
      );

      // If fetching "daily" (today) or a range that falls within our cache window,
      // we could update the cache. But simpler to just rely on syncRecentSales for the bulk cache.
      // However, if we are fetching today's sales, we should probably update the cache for today.

      return sales;
    } on Exception catch (e) {
      // Check for offline/connection errors
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('socketexception') ||
          errorStr.contains('connection refused') ||
          errorStr.contains('clientexception')) {
        print('Offline mode: loading local data');
      } else {
        print('Error fetching remote sales: $e');
      }
      // 2. If failed (offline), load from local DB with filtering
      return await _db.getSalesHistory(startDate: startDate, endDate: endDate);
    }
  }
}
