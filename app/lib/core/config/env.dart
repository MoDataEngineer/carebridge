import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralized, typed access to environment config.
///
/// Values come from a `.env` file at runtime (never committed — see `.env.example`).
/// Only client-safe values belong here; server-only secrets (service role key,
/// Claude API key, FCM key, JWT signing secret) must NEVER be loaded into the client.
class Env {
  const Env._();

  /// Safe lookup: returns null if dotenv was never loaded (e.g. in widget tests
  /// where `main()` doesn't run), instead of throwing NotInitializedError.
  static String? _get(String key) =>
      dotenv.isInitialized ? dotenv.maybeGet(key) : null;

  static String get supabaseUrl => _get('SUPABASE_URL') ?? '';
  static String get supabaseAnonKey => _get('SUPABASE_ANON_KEY') ?? '';

  /// D3: gate ABHA-as-mandatory. Default false for the pilot.
  static bool get requireAbha =>
      (_get('REQUIRE_ABHA') ?? 'false').toLowerCase() == 'true';

  /// True when Supabase creds are present; lets the app boot in placeholder mode
  /// (Phase 1) without crashing if `.env` is absent.
  static bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  // ---- Phase 11: Firebase Phone OTP (client-safe web config values) ----
  static String get firebaseApiKey => _get('FIREBASE_API_KEY') ?? '';
  static String get firebaseAppId => _get('FIREBASE_APP_ID') ?? '';
  static String get firebaseMessagingSenderId =>
      _get('FIREBASE_MESSAGING_SENDER_ID') ?? '';
  static String get firebaseProjectId => _get('FIREBASE_PROJECT_ID') ?? '';

  /// True when the Firebase client config is present — real OTP flows switch
  /// on; absent config keeps the demo (no-OTP) login working.
  static bool get hasFirebase =>
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseProjectId.isNotEmpty;
}
