#!/usr/bin/env ruby

require 'xcodeproj'

# Update Debug configuration
debug_path = 'example/macos/Runner/Configs/Debug.xcconfig'
release_path = 'example/macos/Runner/Configs/Release.xcconfig'

# Function to update config file
def update_config(file_path, config_type)
  return unless File.exist?(file_path)
  
  config = File.read(file_path)
  
  # Add CocoaPods configuration if not already present
  unless config.include?('Pods-Runner')
    config += "\n\n"
    config += "# CocoaPods integration\n"
    config += "#include \"Pods/Target Support Files/Pods-Runner/Pods-Runner.#{config_type}.xcconfig\"\n"
    
    # Write the updated configuration
    File.write(file_path, config)
    puts "✅ Updated #{File.basename(file_path)} with CocoaPods configuration"
  else
    puts "ℹ️  #{File.basename(file_path)} already contains CocoaPods configuration"
  end
end

# Update both configurations
update_config(debug_path, 'debug')
update_config(release_path, 'release')
