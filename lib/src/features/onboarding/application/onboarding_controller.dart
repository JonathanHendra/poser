import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../business/application/business_providers.dart';
import '../../business/domain/business_repository.dart';

final onboardingProvider = ChangeNotifierProvider.autoDispose
    .family<OnboardingController, String>((ref, uid) {
      final controller = OnboardingController(
        uid,
        ref.read(businessRepositoryProvider),
      );
      unawaited(controller.load());
      return controller;
    });

class OnboardingController extends ChangeNotifier {
  OnboardingController(this.uid, this.repository);
  final String uid;
  final BusinessRepository repository;
  Map<String, dynamic> values = {};
  bool loading = true, saving = false, _disposed = false;
  bool ready = false;
  BusinessProfile? existingProfile;
  String? error;
  Future<void> _writes = Future.value();
  Timer? _draftDebounce;
  Map<String, dynamic>? _pendingDraft;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    ready = false;
    existingProfile = null;
    error = null;
    _notify();
    try {
      existingProfile = await repository.profile(uid);
      if (existingProfile != null) {
        ready = true;
        loading = false;
        _notify();
        return;
      }
      values = await repository.draft(uid) ?? {};
      if ((values['store'] as String? ?? '').trim().isEmpty) {
        values['store'] = values['name'] as String? ?? '';
      }
      ready = true;
    } catch (_) {
      error = 'Draft belum dapat dibuka. Silakan coba lagi.';
    }
    loading = false;
    _notify();
  }

  Future<void> flushDraft() {
    _draftDebounce?.cancel();
    final snapshot = _pendingDraft;
    _pendingDraft = null;
    if (snapshot != null) _queueDraft(snapshot);
    return _writes;
  }

  void update(String key, Object value) {
    values[key] = value;
    _pendingDraft = Map<String, dynamic>.from(values);
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 350), flushDraft);
    _notify();
  }

  void _queueDraft(Map<String, dynamic> snapshot) {
    _writes = _writes
        .then((_) => repository.saveDraft(uid, snapshot))
        .catchError((Object e) {
          error = 'Draft belum tersimpan. Periksa ruang penyimpanan.';
          _notify();
        });
  }

  Future<bool> finish({String? ownerName}) async {
    if (saving) return false;
    saving = true;
    error = null;
    _notify();
    try {
      await flushDraft();
      final storeName = (values['store'] as String? ?? '').trim();
      final profile = BusinessProfile(
        businessType: values['type'] as String? ?? 'Warung',
        ownerName: ownerName?.trim().isNotEmpty == true
            ? ownerName!.trim()
            : values['owner'] as String? ?? storeName,
        address: values['address'] as String? ?? '',
        phone: values['phone'] as String? ?? '',
        storeName: storeName,
        currency: values['currency'] as String? ?? 'IDR',
        logo: values['logo'] == null
            ? null
            : base64Decode(values['logo'] as String),
      );
      await repository.activate(uid, profile);
      return true;
    } on FormatException catch (e) {
      error = e.message;
      return false;
    } catch (_) {
      error = 'Usaha belum tersimpan. Periksa penyimpanan lalu coba lagi.';
      return false;
    } finally {
      saving = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(flushDraft());
    super.dispose();
  }
}
