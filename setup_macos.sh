#!/bin/bash
set -e

echo "🚀 Setting up Flutter Sequencer Plus for macOS..."

# Install required Ruby gem for Xcode project manipulation
echo "📦 Installing xcodeproj Ruby gem..."
if ! command -v xcodeproj &> /dev/null; then
    echo "Installing xcodeproj gem (requires sudo)..."
    sudo gem install xcodeproj --no-document
else
    echo "xcodeproj is already installed"
fi

# Install audio dependencies
echo "🔊 Installing audio libraries via Homebrew..."
if [ -f "./scripts/install_audio_deps.sh" ]; then
    chmod +x ./scripts/install_audio_deps.sh
    ./scripts/install_audio_deps.sh
else
    echo "⚠️  install_audio_deps.sh not found. Please run this script from the project root."
    exit 1
fi

# Update Xcode project
echo "🛠  Updating Xcode project..."
if [ -f "./scripts/setup_xcode_project.rb" ]; then
    ruby ./scripts/setup_xcode_project.rb
else
    echo "⚠️  setup_xcode_project.rb not found. Please run this script from the project root."
    exit 1
fi

# Clean and update Flutter dependencies
echo "🧹 Cleaning and updating Flutter dependencies..."
cd example
flutter clean
rm -rf macos/Podfile.lock macos/Pods
flutter pub get

# Install CocoaPods dependencies
echo "☕ Installing CocoaPods dependencies..."
cd macos

# Set UTF-8 encoding for CocoaPods
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Run pod install with verbose output for debugging
if ! pod install --repo-update; then
    echo "⚠️  CocoaPods installation failed. Trying with --verbose..."
    pod install --repo-update --verbose || {
        echo "❌ CocoaPods installation failed. Please check the error messages above."
        echo "💡 You might need to run 'pod repo update' manually first."
        exit 1
    }
fi
cd ..

echo "✅ Setup complete! You can now run the app with 'flutter run -d macos'"
echo "   Note: You may need to open the Xcode workspace and sign the app with your Apple ID"
echo "   Xcode workspace: example/macos/Runner.xcworkspace"
