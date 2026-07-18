import 'dart:convert';
import 'dart:typed_data';

/// An OTP challenge returned by request-OTP (create or verify): the ABDM
/// transaction id to carry into the verify step, plus the masked destination
/// ("…ending with ******1904") to show the user.
class AbhaOtpChallenge {
  const AbhaOtpChallenge({required this.txnId, required this.message});
  final String txnId;
  final String message;

  factory AbhaOtpChallenge.fromBody(Map<String, dynamic> body) =>
      AbhaOtpChallenge(
        txnId: (body['txnId'] ?? '') as String,
        message: (body['message'] ?? 'OTP sent') as String,
      );
}

/// The linked ABHA identity we surface after create/verify. Only the fields the
/// patient sees — the ABHA number is what we persist to `patients.abha_id`.
/// The raw Aadhaar is NEVER part of this (ID-6); `photoBytes` is decoded from
/// the JPEG ABDM returns for on-screen display only.
class AbhaProfile {
  const AbhaProfile({
    required this.abhaNumber,
    required this.abhaAddress,
    required this.name,
    this.gender,
    this.dob,
    this.mobile,
    this.photoBytes,
  });

  final String abhaNumber;
  final String abhaAddress;
  final String name;
  final String? gender;
  final String? dob;
  final String? mobile;
  final Uint8List? photoBytes;

  /// Parse the ABHA-profile shape returned by enrol/byAadhaar (`ABHAProfile`
  /// with first/middle/last names) OR a login `accounts[]` entry (single `name`).
  factory AbhaProfile.fromEnrol(Map<String, dynamic> p) {
    final name = [
      p['firstName'],
      p['middleName'],
      p['lastName'],
    ].where((s) => s != null && '$s'.trim().isNotEmpty).join(' ').trim();
    return AbhaProfile(
      abhaNumber: (p['ABHANumber'] ?? p['abhaNumber'] ?? '') as String,
      abhaAddress: (p['preferredAbhaAddress'] ??
          p['preferredAddress'] ??
          _firstPhr(p['phrAddress']) ??
          '') as String,
      name: name.isEmpty ? (p['name'] ?? '') as String : name,
      gender: p['gender'] as String?,
      dob: p['dob'] as String?,
      mobile: p['mobile'] as String?,
      photoBytes: _decodePhoto(p['photo'] ?? p['profilePhoto']),
    );
  }

  static String? _firstPhr(dynamic v) =>
      (v is List && v.isNotEmpty) ? v.first.toString() : null;

  static Uint8List? _decodePhoto(dynamic v) {
    if (v is! String || v.trim().isEmpty) return null;
    try {
      return base64Decode(v.replaceAll(RegExp(r'\s'), ''));
    } catch (_) {
      return null;
    }
  }
}
