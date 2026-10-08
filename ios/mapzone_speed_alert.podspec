#
# Flutter plugin for the MapZone Speed Alert SDK. The native SDK is resolved
# from the published `MapZoneSpeedAlertSDK` pod; keep its version in step with
# pubspec. Run `pod lib lint mapzone_speed_alert.podspec` to validate.
#
Pod::Spec.new do |s|
  s.name             = 'mapzone_speed_alert'
  s.version          = '1.0.0'
  s.summary          = 'Speed-limit, camera, toll and road-restriction alerts with voice.'
  s.description      = <<-DESC
Flutter plugin for the MapZone Speed Alert SDK: real-time speed-limit, camera,
toll and road-restriction alerts with voice for Android and iOS.
                       DESC
  s.homepage         = 'https://github.com/mapzone-global/mapzone-flutter-alert-view-sdk'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'MapZone' => 'https://map.zone' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'MapZoneSpeedAlertSDK', '= 2.0.5'
  # 14.0 is the floor for the SDK's EnhancedLocationManager APIs. Apps adding
  # Vietmap Navigation (Approach B) should raise their own deployment target.
  s.platform = :ios, '14.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  s.resource_bundles = { 'mapzone_speed_alert_privacy' => ['Resources/PrivacyInfo.xcprivacy'] }
end
