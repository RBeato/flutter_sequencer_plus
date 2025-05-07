#!/bin/zsh
set -e

echo "Preparing stub libraries for iOS..."

# Create directories if they don't exist
if [ ! -d third_party ]; then
    mkdir -p third_party
fi

cd third_party

# Only clone ios-cmake if needed
if [ ! -d ios-cmake ]; then
    echo "Cloning ios-cmake..."
    git clone https://github.com/leetal/ios-cmake.git
    cd ios-cmake
    git checkout 4.4.1
    cd ..
fi

# For sfizz, we'll create a simpler approach
if [ ! -d sfizz ]; then
    mkdir -p sfizz/build
fi

cd sfizz

# This script creates an XCFramework from all required static libraries for sfizz
# for both iOS device and simulator architectures.

# List of all static libraries to include in the XCFramework
LIBS=(
  libsfizz.a
  libsfizz_import.a
  libsfizz_internal.a
  libsfizz_fmidi.a
  libsfizz_hiir_polyphase_iir2designer.a
  libst_audiofile.a
  libst_audiofile_formats.a
  libsfizz_pugixml.a
  libsfizz_parser.a
  libsfizz_filesystem_impl.a
  libabsl_cord.a
  libsfizz_tunings.a
  libsfizz_spin_mutex.a
  libsfizz_messaging.a
  libabsl_raw_hash_set.a
  libsfizz_cpuid.a
  libsfizz_cephes.a
  libsfizz_kissfft.a
  libsfizz_spline.a
  libabsl_cordz_info.a
  libwavpack.a
  libabsl_cord_internal.a
  libaiff.a
  libabsl_hash.a
  libabsl_hashtablez_sampler.a
  libabsl_cordz_handle.a
  libabsl_bad_optional_access.a
  libabsl_bad_variant_access.a
  libabsl_cordz_functions.a
  libabsl_synchronization.a
  libabsl_low_level_hash.a
  libabsl_city.a
  libabsl_crc_cord_state.a
  libabsl_graphcycles_internal.a
  libabsl_crc32c.a
  libabsl_exponential_biased.a
  libabsl_str_format_internal.a
  libabsl_kernel_timeout_internal.a
  libabsl_symbolize.a
  libabsl_time.a
  libabsl_time_zone.a
  libabsl_stacktrace.a
  libabsl_debugging_internal.a
  libabsl_demangle_internal.a
  libabsl_crc_internal.a
  libabsl_malloc_internal.a
  libabsl_civil_time.a
  libabsl_strings.a
  libabsl_crc_cpu_detect.a
  libabsl_string_view.a
  libabsl_strings_internal.a
  libabsl_throw_delegate.a
  libabsl_base.a
  libabsl_raw_logging_internal.a
  libabsl_int128.a
  libabsl_log_severity.a
  libabsl_spinlock_wait.a
)

rm -rf xcframeworks
mkdir -p xcframeworks

for LIB in "${LIBS[@]}"; do
  xcodebuild -create-xcframework \
    -library build-ios/library/lib/$LIB \
    -library build-ios-sim/library/lib/$LIB \
    -output xcframeworks/${LIB%.a}.xcframework
done

echo "Created individual XCFrameworks for all static libraries."

echo "prepare.sh script completed successfully"
