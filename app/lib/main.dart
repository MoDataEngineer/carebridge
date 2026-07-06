import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/supabase_client.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load env flags. In Phase 1 the real `.env` may be absent — fall back to the
  // committed `.env.example` so the placeholder app still boots.
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    await dotenv.load(fileName: '.env.example');
  }

  // No-op unless Supabase creds are present (placeholder mode otherwise).
  // (OTP needs no client config — it's Supabase-hosted, D12.)
  await SupabaseService.init();

  runApp(const ProviderScope(child: CareBridgeApp()));
}

class CareBridgeApp extends StatelessWidget {
  const CareBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'CareBridge',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: appRouter,
    );
  }
}
