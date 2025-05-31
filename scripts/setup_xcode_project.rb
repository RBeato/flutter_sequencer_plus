#!/usr/bin/env ruby

require 'xcodeproj'

# Path to the Xcode project
project_path = 'example/macos/Runner.xcodeproj'

# Open the Xcode project
project = Xcodeproj::Project.open(project_path)

# Find or create a "Copy Files" build phase for Frameworks
main_target = project.targets.find { |t| t.name == 'Runner' }

# Add a new "Run Script" build phase
script_phase = main_target.new_shell_script_build_phase("Setup Audio Libraries")
script_phase.shell_script = '${SRCROOT}/scripts/setup_audio_libs.sh'

# Move the script phase before "Link Binary With Libraries"
link_phase = main_target.build_phases.find { |phase| phase.display_name == 'Link Binary With Libraries' }
if link_phase
  main_target.build_phases.unshift(main_target.build_phases.delete(script_phase))
end

# Add Frameworks directory to the framework search paths
project.build_configuration_list.set_setting('FRAMEWORK_SEARCH_PATHS', '$(inherited) $(PROJECT_DIR)/$(BUILT_PRODUCTS_DIR)/$(FRAMEWORKS_FOLDER_PATH)')
project.build_configuration_list.set_setting('LD_RUNPATH_SEARCH_PATHS', '$(inherited) @executable_path/../Frameworks')

# Save the project
project.save

puts "Xcode project updated successfully!"
