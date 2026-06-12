# macOS build status (June 2026)

The macOS target now **compiles cleanly** with current Xcode after three fixes:

1. `flutter_sequencer.podspec`: removed `-fmodules -fcxx-modules` (clashed with
   sfizz headers / `import std` on new toolchains) and set
   `CLANG_ENABLE_MODULES => 'NO'`, matching iOS. Also added
   `Classes/AudioUnit` to `HEADER_SEARCH_PATHS` so `SfizzDSPKernel.hpp` can
   resolve `DSPKernel.hpp`.
2. `Classes/AudioUnit/Sfizz/SfizzAU.mm`: removed a duplicate
   `_isInitialized` ivar declaration that broke the whole class extension
   (previously masked by the modules failure).
3. `Classes/IInstrument/SharedInstruments/SfizzSamplerInstrument.h`: replaced
   per-callback heap allocation with stack buffers (matches iOS; no
   allocation on the audio render thread).

## Remaining blocker: no macOS binaries

Linking fails with `ld: library 'absl_bad_optional_access' not found` because
`third_party/sfizz/xcframeworks/` (downloaded by `prepare.sh` from the
`v1.0.0` GitHub release) contains **iOS-only xcframeworks** — every
`.xcframework` has only `ios-arm64` and `ios-simulator` slices, no
`macos-arm64`.

To finish macOS support, sfizz + abseil must be built for macOS (arm64, and
x86_64 if desired) and either added as slices to the existing xcframeworks or
published as a separate `xcframeworks-macos.zip` release asset that
`macos/prepare.sh` downloads.

The production apps target iOS/Android only, so this does not block releases.
