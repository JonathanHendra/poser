import 'dart:typed_data';
import '../../../core/domain/rational.dart';

class BusinessProfile {
  const BusinessProfile({
    required this.businessType,
    required this.ownerName,
    required this.address,
    required this.phone,
    required this.storeName,
    this.currency = 'IDR',
    this.logo,
  });
  final String businessType, ownerName, address, phone, storeName;
  final String currency;
  final Uint8List? logo;
  void validate() {
    if (!['IDR', 'USD', 'SGD', 'MYR', 'EUR'].contains(currency) ||
        (logo != null && (logo!.isEmpty || logo!.length > 2097152))) {
      throw const FormatException('Mata uang atau logo usaha tidak valid.');
    }
    if ([
      businessType,
      ownerName,
      address,
      phone,
      storeName,
    ].any((v) => v.trim().isEmpty)) {
      throw const FormatException('Lengkapi informasi usaha.');
    }
  }
}

class LocalProduct {
  const LocalProduct({
    this.id,
    required this.name,
    required this.unit,
    required this.price,
    required int stock,
    this.exactStock,
    this.sku,
    this.barcode,
    this.photo,
    this.productType = 'goods',
    this.category,
  }) : _stock = stock;
  final int? id;
  final String name, unit;
  final String productType;
  final String? category;
  final String? sku, barcode;
  final Uint8List? photo;
  final int price, _stock;
  final Rational? exactStock;
  Rational get stock => exactStock ?? Rational.of(_stock);
  void validate() {
    if (name.trim().isEmpty ||
        unit.trim().isEmpty ||
        !['goods', 'service'].contains(productType) ||
        (productType == 'service' && !stock.isZero) ||
        price < 0 ||
        stock.isNegative ||
        price > 9007199254740991 ||
        stock.numerator.abs() > BigInt.from(maxExactInteger) ||
        stock.denominator > BigInt.from(maxExactInteger)) {
      throw const FormatException(
        'Nama, satuan, harga dan stok produk tidak valid.',
      );
    }
    if (photo != null && (photo!.isEmpty || photo!.length > 5242880)) {
      throw const FormatException('Foto maksimal 5 MB.');
    }
  }
}

abstract interface class BusinessRepository {
  Future<BusinessProfile?> profile(String ownerId);
  Future<Map<String, dynamic>?> draft(String ownerId);
  Future<void> saveDraft(String ownerId, Map<String, dynamic> draft);
  Future<void> updateProfile(String ownerId, BusinessProfile profile);
  Future<void> activate(
    String ownerId,
    BusinessProfile profile, {
    LocalProduct? firstProduct,
  });
  Future<List<LocalProduct>> products(String ownerId);
  Future<void> addProduct(String ownerId, LocalProduct product);
}
