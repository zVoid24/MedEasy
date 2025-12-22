class Medicine {
  const Medicine({
    required this.id,
    required this.brandName,
    required this.genericName,
    required this.type,
    required this.manufacturer,
    required this.brandId,
  });

  final int id;
  final int brandId;
  final String brandName;
  final String genericName;
  final String type;
  final String manufacturer;

  factory Medicine.fromJson(Map<String, dynamic> json) => Medicine(
        id: json['id'] as int,
        brandId: json['brand_id'] as int,
        brandName: json['brand_name'] as String,
        genericName: json['generic_name'] as String,
        type: json['type'] as String,
        manufacturer: json['manufacturer'] as String,
      );
}
