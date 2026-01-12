/// Seconds per microsecond
const SECONDS_PER_US = 1 / 1000000;

/// The size of the event buffer in the native backend
/// Increased for fewer under-runs during fast passages and dense grids
const BUFFER_SIZE = 4096;

/// Interval to "top off" each track's buffer, in milliseconds
/// PERFORMANCE: Increased from 250ms to 500ms to reduce FFI overhead by 50%
/// 500ms (2x per second) is still frequent enough for smooth playback
const TOP_OFF_PERIOD_MS = 500;

/// "Lead frames" account for the fact that it may take some time to build the
/// events and sync them with the native sequencer engine.
const LEAD_FRAMES = 1024;

/// The patch number to select from a sf2 file.
const DEFAULT_PATCH_NUMBER = 0;

/// Enable verbose logging for timing and loop diagnostics
/// NOTE: Disable in production builds for better performance
const DEBUG_SEQUENCER_LOGS = false;

/// Legacy switch kept for backwards compatibility (not used by runtime path).
/// Default to allowing native scheduling on iOS (host apps can override at runtime
/// via GlobalState().setIosNativeSchedulingEnabled(false)).
const DISABLE_NATIVE_SCHEDULING_IOS = false;
