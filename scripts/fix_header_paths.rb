#!/usr/bin/env ruby

require 'xcodeproj'

# Path to the Pods project
project_path = 'example/macos/Pods/Pods.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the flutter_sequencer target
target = project.targets.find { |t| t.name == 'flutter_sequencer' }

if target
  # Update header search paths
  target.build_configurations.each do |config|
    # Get current header search paths
    header_search_paths = config.build_settings['HEADER_SEARCH_PATHS'] || []
    
    # Add the Classes directory if not already present
    classes_path = '${PODS_ROOT}/../.symlinks/plugins/flutter_sequencer/macos/Classes'
    unless header_search_paths.include?(classes_path) || header_search_paths.include?('"' + classes_path + '"')
      header_search_paths << classes_path
      puts "✅ Added header search path: #{classes_path}"
    end
    
    # Add the recursive flag if needed
    config.build_settings['HEADER_SEARCH_PATHS'] = header_search_paths
    
    # Enable modules
    config.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
    
    # Set the module map file
    module_map_path = '${PODS_ROOT}/../.symlinks/plugins/flutter_sequencer/macos/Classes/module.modulemap'
    config.build_settings['MODULEMAP_FILE'] = module_map_path
  end
  
  # Save the project
  project.save
  puts "✅ Updated Xcode project with correct header search paths and module settings"
else
  puts "❌ Could not find flutter_sequencer target in Xcode project"
  exit 1
end
