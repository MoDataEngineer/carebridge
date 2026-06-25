import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';

/// Thin wrapper around Supabase initialization.
///
/// Phase 1: initializes only when creds exist, so the placeholder app runs
/// offline. Real auth/data wiring happens in later phases.
class SupabaseService {
  const SupabaseService._();

  static bool _initialized = false;
  static bool get isInitialized => _initialized;

  static Future<void> init() async {
    if (!Env.hasSupabase || _initialized) return;
    await Supabase.initialize(
      url: Env.supabaseUrl,
      // `publishableKey` is the current name for what was the anon/public key.
      publishableKey: Env.supabaseAnonKey,
    );
    _initialized = true;
  }

  /// Throws if accessed before init — callers in later phases should guard on
  /// [isInitialized] or ensure [init] ran.
  static SupabaseClient get client => Supabase.instance.client;
}
