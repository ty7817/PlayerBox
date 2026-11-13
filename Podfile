platform :ios, '17.0'

# 开源 VLC 内核（MobileVLCKit，LGPL），提供 MKV / AVI / FLV / WMV / RMVB / WEBM 等全格式硬解
# 注意：静态链接，不往 app 里嵌 dylib
target 'PlayerBox' do
  use_frameworks! :linkage => :static
  pod 'MobileVLCKit', '3.7.5'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      config.build_settings['ENABLE_BITCODE'] = 'NO'
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
      config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
    end
  end
end
