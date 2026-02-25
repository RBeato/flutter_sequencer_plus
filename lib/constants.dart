/// Seconds per microsecond
const SECONDS_PER_US = 1 / 1000000;

/// The size of the event buffer in the native backend.
/// MUST match C++ Buffer.h template default (1024). A mismatch causes
/// _scheduleEventsOptimized to over-iterate, triggering the clear-retry
/// path that wipes near-future events and replaces them with far-future
/// ones the audio thread can't reach yet — resulting in silence.
const BUFFER_SIZE = 1024;

/// Interval to "top off" each track's buffer, in milliseconds
/// Faster refill cadence improves stability at loop wraps and pattern changes
const TOP_OFF_PERIOD_MS = 250;

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
