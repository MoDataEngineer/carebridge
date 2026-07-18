import 'package:flutter/services.dart';

/// Mobile/desktop: the platform's alert sound. (Web uses the AudioContext
/// variant via conditional import.)
Future<void> playNotificationBeep() =>
    SystemSound.play(SystemSoundType.alert);
