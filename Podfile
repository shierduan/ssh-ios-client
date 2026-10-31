platform :ios, '17.0'
use_frameworks!

target 'SSHClient' do
  # NMSSH 封装 libssh2,提供 SSH 会话/通道/SFTP/端口转发的成熟高层 API
  pod 'NMSSH', '~> 2.4'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      # NMSSH 为 Objective-C,关闭严格并发检查以避免与 Swift 6 冲突
      config.build_settings['SWIFT_STRICT_CONCURRENCY'] = 'minimal'
    end
  end
end
