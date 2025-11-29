# Uncomment the next line to define a global platform for your project
platform :ios, '17.0'

target 'VoiceInk-ios' do
  # Use static frameworks to avoid sandbox issues
  use_frameworks! :linkage => :static

  # ML Kit On-Device Translation
  pod 'GoogleMLKit/Translate', '~> 8.0'

  target 'VoiceInk-iosTests' do
    inherit! :search_paths
    # Pods for testing
  end

  target 'VoiceInkKeyboard' do
    inherit! :search_paths
    # Pods for keyboard extension
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    end
  end
  
  # Fix resources script to avoid sandbox issues
  installer.pods_project.targets.each do |target|
    target.build_phases.each do |phase|
      if phase.is_a?(Xcodeproj::Project::Object::PBXShellScriptBuildPhase)
        if phase.name == '[CP] Copy Pods Resources' || phase.shell_script.include?('resources-to-copy')
          phase.shell_script = phase.shell_script.gsub(
            '${SRCROOT}/Pods/resources-to-copy-${TARGET_NAME}.txt',
            '${TARGET_TEMP_DIR}/resources-to-copy-${TARGET_NAME}.txt'
          )
        end
      end
    end
  end
end

