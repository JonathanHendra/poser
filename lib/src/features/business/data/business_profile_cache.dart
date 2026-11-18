import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/business_repository.dart';

class BusinessProfileCache {
  final _preferences = SharedPreferencesAsync();
  Future<void> save(String uid, BusinessProfile profile) =>
      _preferences.setString(
        'pospro.profile.$uid',
        jsonEncode({
          'type': profile.businessType,
          'owner': profile.ownerName,
          'address': profile.address,
          'phone': profile.phone,
          'store': profile.storeName,
          'currency': profile.currency,
          'logo': profile.logo == null ? null : base64Encode(profile.logo!),
        }),
      );
  Future<BusinessProfile?> load(String uid) async {
    final encoded = await _preferences.getString('pospro.profile.$uid');
    if (encoded == null) return null;
    final data = jsonDecode(encoded) as Map<String, dynamic>;
    final profile = BusinessProfile(
      businessType: data['type'] as String,
      ownerName: data['owner'] as String,
      address: data['address'] as String,
      phone: data['phone'] as String,
      storeName: (data['store'] ?? data['name']) as String,
      currency: data['currency'] as String? ?? 'IDR',
      logo: data['logo'] == null ? null : base64Decode(data['logo'] as String),
    );
    profile.validate();
    return profile;
  }
}
