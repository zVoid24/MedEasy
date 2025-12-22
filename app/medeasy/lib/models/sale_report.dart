class SaleItemDetail {
  const SaleItemDetail({
    required this.saleId,
    required this.medicineId,
    required this.inventoryId,
    required this.brandName,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });

  final int saleId;
  final int medicineId;
  final int inventoryId;
  final String brandName;
  final int quantity;
  final double unitPrice;
  final double subtotal;

  factory SaleItemDetail.fromJson(Map<String, dynamic> json) =>
      SaleItemDetail(
        saleId: json['sale_id'] as int,
        medicineId: json['medicine_id'] as int,
        inventoryId: json['inventory_id'] as int,
        brandName: json['brand_name'] as String,
        quantity: (json['quantity'] as num).toInt(),
        unitPrice: (json['unit_price'] as num).toDouble(),
        subtotal: (json['subtotal'] as num).toDouble(),
      );
}

class SaleReportEntry {
  const SaleReportEntry({
    required this.id,
    required this.totalAmount,
    required this.discount,
    required this.paidAmount,
    required this.dueAmount,
    required this.createdAt,
    required this.items,
  });

  final int id;
  final double totalAmount;
  final double discount;
  final double paidAmount;
  final double dueAmount;
  final String createdAt;
  final List<SaleItemDetail> items;

  factory SaleReportEntry.fromJson(Map<String, dynamic> json) =>
      SaleReportEntry(
        id: json['id'] as int,
        totalAmount: (json['total_amount'] as num).toDouble(),
        discount: (json['discount'] as num).toDouble(),
        paidAmount: (json['paid_amount'] as num).toDouble(),
        dueAmount: (json['due_amount'] as num).toDouble(),
        createdAt: json['created_at'] as String,
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => SaleItemDetail.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
