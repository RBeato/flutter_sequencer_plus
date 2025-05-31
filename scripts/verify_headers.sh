#!/bin/bash

echo "Checking header files in build directory..."
find /Users/rbsou/Documents/CODE/FLUTTER/flutter_sequencer_plus/example/build -name "flutter_sequencer.h" -o -name "*.h" | sort

echo "\nChecking module.modulemap..."
find /Users/rbsou/Documents/CODE/FLUTTER/flutter_sequencer_plus/example/build -name "module.modulemap"

echo "\nChecking symlinks..."
ls -la /Users/rbsou/Documents/CODE/FLUTTER/flutter_sequencer_plus/example/macos/Flutter/ephemeral/.symlinks/plugins/flutter_sequencer/macos/Classes/
