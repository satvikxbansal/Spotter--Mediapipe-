platform :ios, '17.0'

target 'VirtualTrainer' do
  use_frameworks!
  pod 'MediaPipeTasksVision'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    end
  end

  # Xcode 26's Swift driver is stricter about resolving vendored XCFrameworks
  # used by MediaPipeTasks*. CocoaPods emits `-lMediaPipeTasks...` for the
  # aggregate target, but the artifacts are frameworks under
  # XCFrameworkIntermediates. Keep the generated app link flags framework-based
  # so importing MediaPipeTasksVision remains stable in the app target.
  Dir.glob(File.join(installer.sandbox.root, 'Target Support Files', 'Pods-VirtualTrainer', 'Pods-VirtualTrainer.*.xcconfig')).each do |path|
    config = File.read(path)
    config.gsub!('-l"MediaPipeTasksCommon" -l"MediaPipeTasksVision"', '-framework "MediaPipeTasksCommon" -framework "MediaPipeTasksVision"')
    config.gsub!(
      'FRAMEWORK_SEARCH_PATHS = $(inherited) "${PODS_ROOT}/MediaPipeTasksCommon/frameworks" "${PODS_ROOT}/MediaPipeTasksVision/frameworks"',
      'FRAMEWORK_SEARCH_PATHS = $(inherited) "${PODS_ROOT}/MediaPipeTasksCommon/frameworks" "${PODS_ROOT}/MediaPipeTasksVision/frameworks" "${PODS_XCFRAMEWORKS_BUILD_DIR}/MediaPipeTasksCommon" "${PODS_XCFRAMEWORKS_BUILD_DIR}/MediaPipeTasksVision"'
    )
    File.write(path, config)
  end
end
