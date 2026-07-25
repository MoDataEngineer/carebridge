import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/design_tokens.dart';
import '../../shared/widgets/connect_tracker_tile.dart';
import '../../shared/widgets/pills_loader.dart';
import 'vitals_models.dart';
import 'vitals_repository.dart';

/// "Connect your tracker" (epic §3, Phase 12). Lists the on-device sources the
/// patient can connect. Connecting is FREE and patient-initiated; it only turns
/// on reading from the phone's health hub into the patient's own view — it does
/// NOT share anything with a doctor (that's a separate `wearable` grant, §5).
class ConnectTrackerScreen extends ConsumerStatefulWidget {
  const ConnectTrackerScreen({super.key});

  @override
  ConsumerState<ConnectTrackerScreen> createState() => _ConnectTrackerScreenState();
}

class _ConnectTrackerScreenState extends ConsumerState<ConnectTrackerScreen> {
  List<VitalsConnection>? _connections;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await ref.read(vitalsRepositoryProvider).connections();
    if (mounted) setState(() => _connections = c);
  }

  Future<void> _toggle(VitalsConnection c) async {
    final repo = ref.read(vitalsRepositoryProvider);
    // The real on-device source requests OS HealthKit/Health Connect permission
    // here before recording the connection (two consent layers, §5).
    if (c.connected) {
      await repo.disconnect(c.provider);
    } else {
      await repo.connect(c.provider);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final connections = _connections;

    return Scaffold(
      appBar: AppBar(title: const Text('Connect a tracker')),
      body: connections == null
          ? const Center(child: PillsLoader())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Text(
                  'Connect a health app to see your steps, workouts, sleep and '
                  'heart rate here. It stays on your phone and in your private '
                  'Ayulekha record — nothing is shared with a doctor unless you '
                  'turn that on separately.',
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.lg),
                for (final c in connections)
                  ConnectTrackerTile(
                    title: c.provider.label,
                    subtitle: c.provider.blurb,
                    icon: c.provider.icon,
                    connected: c.connected,
                    onConnect: () => _toggle(c),
                  ),
                const SizedBox(height: AppSpacing.sm),
                // Connected sources can be turned off; offer it inline.
                for (final c in connections)
                  if (c.connected)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => _toggle(c),
                        child: Text('Disconnect ${c.provider.label}'),
                      ),
                    ),
              ],
            ),
    );
  }
}
