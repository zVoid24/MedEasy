class InventoryItem {
  const InventoryItem({
    required this.inventoryId,
    required this.medicineId,
    required this.brandName,
    required this.genericName,
    required this.manufacturer,
    required this.type,
    required this.quantity,
    required this.unitCost,
    required this.unitPrice,
    this.totalCost,
    this.expiryDate,
  });

  final int inventoryId;
  final int medicineId;
  final String brandName;
  final String genericName;
  final String manufacturer;
  final String type;
  final int quantity;
  final double unitCost;
  final double unitPrice;
  final double? totalCost;
  final String? expiryDate;

  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
        inventoryId: json['inventory_id'] as int,
        medicineId: json['medicine_id'] as int,
        brandName: json['brand_name'] as String,
        genericName: json['generic_name'] as String,
        manufacturer: json['manufacturer'] as String,
        type: json['type'] as String,
        quantity: (json['quantity'] as num).toInt(),
        unitCost: (json['unit_cost'] as num).toDouble(),
        unitPrice: (json['unit_price'] as num).toDouble(),
        totalCost: (json['total_cost'] as num?)?.toDouble(),
        expiryDate: json['expiry_date'] as String?,
      );
}
