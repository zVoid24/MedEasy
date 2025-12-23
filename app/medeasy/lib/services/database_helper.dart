import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/inventory_item.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('medeasy.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE sales_history (
          id INTEGER PRIMARY KEY,
          total_amount REAL,
          created_at TEXT,
          items TEXT -- JSON string of items
        )
      ''');
    }
  }

  Future<void> _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';

    // Inventory Table
    await db.execute('''
      CREATE TABLE inventory (
        inventory_id INTEGER PRIMARY KEY,
        medicine_id INTEGER,
        brand_name TEXT NOT NULL,
        generic_name TEXT NOT NULL,
        manufacturer TEXT NOT NULL,
        type TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_cost REAL NOT NULL,
        unit_price REAL NOT NULL,
        expiry_date TEXT
      )
    ''');

    // Pending Sales Table
    await db.execute('''
      CREATE TABLE pending_sales (
        id $idType,
        payload $textType,
        created_at $textType
      )
    ''');

    // Sales History Table (Offline Cache)
    await db.execute('''
      CREATE TABLE sales_history (
        id INTEGER PRIMARY KEY,
        total_amount REAL,
        created_at TEXT,
        items TEXT -- JSON string of items
      )
    ''');
  }

  // Inventory Operations
  Future<void> insertInventory(List<InventoryItem> items) async {
    final db = await database;
    final batch = db.batch();

    // Clear existing inventory to ensure we have a fresh copy from backend
    // In a more complex app, we might do a diff, but for now replacing is safer/easier
    batch.delete('inventory');

    for (var item in items) {
      batch.insert('inventory', {
        'inventory_id': item.inventoryId,
        'medicine_id': item.medicineId,
        'brand_name': item.brandName,
        'generic_name': item.genericName,
        'manufacturer': item.manufacturer,
        'type': item.type,
        'quantity': item.quantity,
        'unit_cost': item.unitCost,
        'unit_price': item.unitPrice,
        'expiry_date': item.expiryDate,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<InventoryItem>> getInventory() async {
    final db = await database;
    final result = await db.query('inventory', orderBy: 'brand_name ASC');

    return result
        .map(
          (json) => InventoryItem(
            inventoryId: json['inventory_id'] as int,
            medicineId: json['medicine_id'] as int?,
            brandName: json['brand_name'] as String,
            genericName: json['generic_name'] as String,
            manufacturer: json['manufacturer'] as String,
            type: json['type'] as String,
            quantity: json['quantity'] as int,
            unitCost: json['unit_cost'] as double,
            unitPrice: json['unit_price'] as double,
            expiryDate: json['expiry_date'] as String?,
          ),
        )
        .toList();
  }

  Future<List<InventoryItem>> searchInventory(String query) async {
    final db = await database;
    final result = await db.query(
      'inventory',
      where: 'brand_name LIKE ? OR generic_name LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'brand_name ASC',
    );

    return result
        .map(
          (json) => InventoryItem(
            inventoryId: json['inventory_id'] as int,
            medicineId: json['medicine_id'] as int?,
            brandName: json['brand_name'] as String,
            genericName: json['generic_name'] as String,
            manufacturer: json['manufacturer'] as String,
            type: json['type'] as String,
            quantity: json['quantity'] as int,
            unitCost: json['unit_cost'] as double,
            unitPrice: json['unit_price'] as double,
            expiryDate: json['expiry_date'] as String?,
          ),
        )
        .toList();
  }

  Future<void> updateInventoryQuantity(int inventoryId, int newQuantity) async {
    final db = await database;
    await db.update(
      'inventory',
      {'quantity': newQuantity},
      where: 'inventory_id = ?',
      whereArgs: [inventoryId],
    );
  }

  Future<void> decrementInventoryQuantity(int inventoryId, int amount) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE inventory SET quantity = quantity - ? WHERE inventory_id = ?',
      [amount, inventoryId],
    );
  }

  // Pending Sales Operations
  Future<int> insertPendingSale(Map<String, dynamic> salePayload) async {
    final db = await database;
    return await db.insert('pending_sales', {
      'payload': jsonEncode(salePayload),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // Sales History Operations
  Future<void> insertSalesHistory(List<dynamic> sales) async {
    final db = await database;
    final batch = db.batch();

    // Clear old history first (optional, or keep appending)
    batch.delete('sales_history');

    for (var sale in sales) {
      batch.insert('sales_history', {
        'id': sale['id'],
        'total_amount': sale['total_amount'],
        'created_at': sale['created_at'],
        'items': jsonEncode(sale['items']),
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getSalesHistory({
    String? startDate,
    String? endDate,
  }) async {
    final db = await database;
    String? whereClause;
    List<dynamic>? whereArgs;

    if (startDate != null && endDate != null) {
      whereClause = 'created_at BETWEEN ? AND ?';
      // Append time to cover the full day
      whereArgs = ['${startDate}T00:00:00', '${endDate}T23:59:59'];
    }

    // Fetch confirmed sales
    final List<Map<String, dynamic>> historyMaps = await db.query(
      'sales_history',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );

    final historyList = List.generate(historyMaps.length, (i) {
      return {
        'id': historyMaps[i]['id'],
        'total_amount': historyMaps[i]['total_amount'],
        'created_at': historyMaps[i]['created_at'],
        'items': jsonDecode(historyMaps[i]['items']),
        'discount': 0,
        'paid_amount': historyMaps[i]['total_amount'],
        'due_amount': 0,
        'user_id': 0,
        'is_pending': false,
      };
    });

    // Fetch pending sales
    String? pendingWhere;
    List<dynamic>? pendingArgs;
    if (startDate != null && endDate != null) {
      pendingWhere = 'created_at BETWEEN ? AND ?';
      pendingArgs = ['${startDate}T00:00:00', '${endDate}T23:59:59'];
    }

    final List<Map<String, dynamic>> pendingMaps = await db.query(
      'pending_sales',
      where: pendingWhere,
      whereArgs: pendingArgs,
      orderBy: 'created_at DESC',
    );

    final pendingList = <Map<String, dynamic>>[];
    for (var map in pendingMaps) {
      final payload = jsonDecode(map['payload'] as String);
      final items = List<Map<String, dynamic>>.from(payload['items']);

      // Hydrate items if missing details
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0.0;

        if (item['brand_name'] == null || unitPrice <= 0.01) {
          final invId = item['inventory_id'] as int;
          final invList = await db.query(
            'inventory',
            where: 'inventory_id = ?',
            whereArgs: [invId],
          );
          if (invList.isNotEmpty) {
            final inv = invList.first;
            final invPrice = (inv['sale_price'] as num?)?.toDouble() ?? 0.0;

            items[i] = {
              ...item,
              'brand_name': item['brand_name'] ?? inv['brand_name'],
              'unit_price': unitPrice > 0.01 ? unitPrice : invPrice,
              'sale_price': unitPrice > 0.01 ? unitPrice : invPrice,
              'subtotal':
                  item['subtotal'] ??
                  ((unitPrice > 0.01 ? unitPrice : invPrice) *
                      ((item['quantity'] as num?)?.toInt() ?? 0)),
            };
          } else {
            // Fallback if inventory item also missing (unlikely but safe)
            items[i] = {
              ...item,
              'brand_name': item['brand_name'] ?? 'Unknown Item',
              'unit_price': unitPrice,
              'sale_price': unitPrice,
              'subtotal': item['subtotal'] ?? 0.0,
            };
          }
        }
      }

      final total = items.fold<double>(
        0,
        (sum, item) =>
            sum +
            ((item['sale_price'] as num?)?.toDouble() ?? 0.0) *
                ((item['quantity'] as num?)?.toInt() ?? 0),
      );
      // Apply discount logic roughly for display
      final discountPercent =
          (payload['discount_percent'] as num?)?.toDouble() ?? 0.0;
      final discountAmount = (total * discountPercent) / 100;
      final roundOff = (payload['round_off'] as num?)?.toDouble() ?? 0.0;
      final netTotal = total - discountAmount + roundOff;

      pendingList.add({
        'id': 'PENDING-${map['id']}', // Temporary ID
        'total_amount': netTotal,
        'created_at': map['created_at'],
        'items': items,
        'discount': discountAmount,
        'paid_amount': (payload['paid_amount'] as num?)?.toDouble() ?? 0.0,
        'due_amount': 0, // Simplified
        'user_id': 0,
        'is_pending': true,
      });
    }

    // Merge and sort
    final combined = [...pendingList, ...historyList];
    combined.sort((a, b) {
      final dateA = DateTime.parse(a['created_at']);
      final dateB = DateTime.parse(b['created_at']);
      return dateB.compareTo(dateA);
    });

    return combined;
  }

  Future<List<Map<String, dynamic>>> getPendingSales() async {
    final db = await database;
    return await db.query('pending_sales', orderBy: 'created_at ASC');
  }

  Future<void> deletePendingSale(int id) async {
    final db = await database;
    await db.delete('pending_sales', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getExpiringItems(int days) async {
    final db = await database;
    final now = DateTime.now();
    final expiryLimit = now.add(Duration(days: days));
    final nowStr = now.toIso8601String().split('T')[0];
    final limitStr = expiryLimit.toIso8601String().split('T')[0];

    return await db.query(
      'inventory',
      where: 'expiry_date BETWEEN ? AND ?',
      whereArgs: [nowStr, limitStr],
      orderBy: 'expiry_date ASC',
    );
  }
}
