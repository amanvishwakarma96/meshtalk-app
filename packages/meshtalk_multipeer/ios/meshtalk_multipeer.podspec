Pod::Spec.new do |s|
  s.name             = 'meshtalk_multipeer'
  s.version          = '0.1.0'
  s.summary          = 'MeshTalk Multipeer Connectivity bridge.'
  s.description      = <<-DESC
Private Flutter plugin that bridges MeshTalk to Apple's Multipeer Connectivity framework.
                       DESC
  s.homepage         = 'https://github.com/amanvishwakarma96/meshtalk-app'
  s.license          = { :type => 'MIT' }
  s.author           = { 'MeshTalk' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
  s.static_framework = true
end
