/// Cross-platform notification chime with no added dependency: Web Audio API
/// on web, the platform alert sound elsewhere. Import THIS file, never the
/// platform variants directly.
library;

export 'notification_sound_io.dart'
    if (dart.library.js_interop) 'notification_sound_web.dart';
