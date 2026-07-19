import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_client.dart';

/// Doctor photo / clinic logo upload (0030). Images land in the PUBLIC
/// 'branding' bucket under the clinic's own folder (storage policy enforces
/// the prefix); the resulting URL is saved via carebridge_set_branding, which
/// re-checks scope server-side. Non-PHI assets only.
/// The clinic's current branding: doctor-id -> photo URL, plus the logo.
class ClinicBranding {
  const ClinicBranding({this.photos = const {}, this.logoUrl});
  final Map<String, String> photos;
  final String? logoUrl;
}

abstract class BrandingRepository {
  /// Returns the public URL now saved on the doctor (or the clinic when
  /// [doctorId] is null -> clinic logo).
  Future<String> upload({
    required String clinicId,
    required Uint8List bytes,
    required String extension,
    String? doctorId,
  });

  /// Current photos/logo for [clinicId] (from the public directory RPC).
  Future<ClinicBranding> current(String clinicId);
}

class SupabaseBrandingRepository implements BrandingRepository {
  SupabaseBrandingRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<String> upload({
    required String clinicId,
    required Uint8List bytes,
    required String extension,
    String? doctorId,
  }) async {
    // Server-side upload (branding-upload edge function, service role):
    // client-side storage RLS 403'd even under permissive policies on this
    // project, so the scope check + write happen server-side (0030 notes).
    final ext = extension.replaceAll('.', '').toLowerCase();
    final res = await _client.functions.invoke('branding-upload', body: {
      'doctor_id': doctorId,
      'ext': ext,
      'data': base64Encode(bytes),
    });
    final data = (res.data ?? {}) as Map<String, dynamic>;
    final url = data['url'] as String?;
    if (url == null) {
      throw StateError((data['detail'] ?? data['error'] ?? 'upload failed').toString());
    }
    return url;
  }

  @override
  Future<ClinicBranding> current(String clinicId) async {
    final rows = await _client.rpc('carebridge_bookable_doctors');
    final photos = <String, String>{};
    String? logo;
    for (final m in (rows ?? []) as List) {
      if (m['clinic_id'] != clinicId) continue;
      logo ??= m['logo_url'] as String?;
      final p = m['photo_url'] as String?;
      if (p != null && p.isNotEmpty) photos[m['doctor_id'] as String] = p;
    }
    return ClinicBranding(photos: photos, logoUrl: logo);
  }
}

final brandingRepositoryProvider = Provider<BrandingRepository>((ref) {
  if (!SupabaseService.isInitialized) {
    throw StateError('Supabase not initialized — provide a BrandingRepository override.');
  }
  return SupabaseBrandingRepository(SupabaseService.client);
});
