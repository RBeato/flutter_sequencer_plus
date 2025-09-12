/// Seconds per microsecond
const SECONDS_PER_US = 1 / 1000000;

/// The size of the event buffer in the native backend
const BUFFER_SIZE = 1024;

/// Interval to "top off" each track's buffer, in milliseconds
const TOP_OFF_PERIOD_MS = 1000;

/// "Lead frames" account for the fact that it may take some time to build the
/// events and sync them with the native sequencer engine.
const LEAD_FRAMES = 1024;

/// The patch number to select from a sf2 file.
const DEFAULT_PATCH_NUMBER = 0;

/// Enable verbose logging for timing and loop diagnostics
const DEBUG_SEQUENCER_LOGS = true;

/// When true, the library will avoid scheduling events natively on iOS and
/// let the host app (example) handle real-time dispatch from Dart instead.
/// This prevents double-triggers at loop boundaries when both native and Dart
/// dispatch are active.
const DISABLE_NATIVE_SCHEDULING_IOS = true;
