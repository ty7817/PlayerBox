# Build report

时间：Fri Nov 13 11:55:37 UTC 2026

## pod install
```
186:Downloading dependencies
188:-> Installing MobileVLCKit (3.7.5)
202:  - Installing files into Pods project
208:  - Installing Pod Targets
209:    - Installing target `MobileVLCKit` iOS 9.0
210:  - Installing Aggregate Targets
211:    - Installing target `Pods-PlayerBox` iOS 17.0
239:POD_EXIT_CODE=0
```

## xcodebuild
```
650:/Users/runner/work/PlayerBox/PlayerBox/PlayerBox/Download.swift:116:60: warning: capture of 'item' with non-Sendable type 'DownloadItem' in a '@Sendable' closure
720:2026-11-13 11:55:36.925 appintentsmetadataprocessor[3794:14967] warning: Metadata extraction skipped. No AppIntents.framework dependency found.
746:** BUILD SUCCEEDED **
748:EXIT_CODE=0
```

## 日志尾部
```
total size is 103976425  speedup is 1.00
Stripped /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app/Frameworks/MobileVLCKit.framework/MobileVLCKit of architectures: armv7 armv7s

GenerateDSYMFile /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app.dSYM /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app/PlayerBox (in target 'PlayerBox' from project 'PlayerBox')
    cd /Users/runner/work/PlayerBox/PlayerBox
    /Applications/Xcode_26.6.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/dsymutil /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app/PlayerBox -o /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app.dSYM

ExtractAppIntentsMetadata (in target 'PlayerBox' from project 'PlayerBox')
    cd /Users/runner/work/PlayerBox/PlayerBox
    /Applications/Xcode_26.6.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/appintentsmetadataprocessor --toolchain-dir /var/run/com.apple.security.cryptexd/mnt/com.apple.MobileAsset.MetalToolchain-v17.6.109.0.HNSY5W/Metal.xctoolchain --module-name PlayerBox --sdk-root /Applications/Xcode_26.6.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk --xcode-version 17F113 --platform-family iOS --deployment-target 17.0 --bundle-identifier com.ty7817.playerbox --output /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app --target-triple arm64-apple-ios17.0 --binary-file /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app/PlayerBox --dependency-file /Users/runner/work/PlayerBox/PlayerBox/build/Build/Intermediates.noindex/PlayerBox.build/Release-iphoneos/PlayerBox.build/Objects-normal/arm64/PlayerBox_dependency_info.dat --stringsdata-file /Users/runner/work/PlayerBox/PlayerBox/build/Build/Intermediates.noindex/PlayerBox.build/Release-iphoneos/PlayerBox.build/Objects-normal/arm64/ExtractedAppShortcutsMetadata.stringsdata --source-file-list /Users/runner/work/PlayerBox/PlayerBox/build/Build/Intermediates.noindex/PlayerBox.build/Release-iphoneos/PlayerBox.build/Objects-normal/arm64/PlayerBox.SwiftFileList --metadata-file-list /Users/runner/work/PlayerBox/PlayerBox/build/Build/Intermediates.noindex/PlayerBox.build/Release-iphoneos/PlayerBox.build/PlayerBox.DependencyMetadataFileList --static-metadata-file-list /Users/runner/work/PlayerBox/PlayerBox/build/Build/Intermediates.noindex/PlayerBox.build/Release-iphoneos/PlayerBox.build/PlayerBox.DependencyStaticMetadataFileList --swift-const-vals-list /Users/runner/work/PlayerBox/PlayerBox/build/Build/Intermediates.noindex/PlayerBox.build/Release-iphoneos/PlayerBox.build/Objects-normal/arm64/PlayerBox.SwiftConstValuesFileList --compile-time-extraction --deployment-aware-processing --validate-assistant-intents --no-app-shortcuts-localization
2026-11-13 11:55:36.906 appintentsmetadataprocessor[3794:14967] Starting appintentsmetadataprocessor export
2026-11-13 11:55:36.925 appintentsmetadataprocessor[3794:14967] warning: Metadata extraction skipped. No AppIntents.framework dependency found.

CopySwiftLibs /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app (in target 'PlayerBox' from project 'PlayerBox')
    cd /Users/runner/work/PlayerBox/PlayerBox
    builtin-swiftStdLibTool --copy --verbose --scan-executable /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app/PlayerBox --scan-folder /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app/Frameworks --scan-folder /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app/PlugIns --scan-folder /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app/SystemExtensions --scan-folder /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app/Extensions --scan-folder /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/Pods_PlayerBox.framework --platform iphoneos --toolchain /var/run/com.apple.security.cryptexd/mnt/com.apple.MobileAsset.MetalToolchain-v17.6.109.0.HNSY5W/Metal.xctoolchain --toolchain /Applications/Xcode_26.6.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain --destination /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app/Frameworks --strip-bitcode --strip-bitcode-tool /Applications/Xcode_26.6.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/bitcode_strip --emit-dependency-info /Users/runner/work/PlayerBox/PlayerBox/build/Build/Intermediates.noindex/PlayerBox.build/Release-iphoneos/PlayerBox.build/SwiftStdLibToolInputDependencies.dep --filter-for-swift-os --back-deploy-swift-span
Ignoring --strip-bitcode because --sign was not passed

AppIntentsSSUTraining (in target 'PlayerBox' from project 'PlayerBox')
    cd /Users/runner/work/PlayerBox/PlayerBox
    /Applications/Xcode_26.6.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/appintentsnltrainingprocessor --infoplist-path /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app/Info.plist --temp-dir-path /Users/runner/work/PlayerBox/PlayerBox/build/Build/Intermediates.noindex/PlayerBox.build/Release-iphoneos/PlayerBox.build/ssu --bundle-id com.ty7817.playerbox --product-path /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app --extracted-metadata-path /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app/Metadata.appintents --metadata-file-list /Users/runner/work/PlayerBox/PlayerBox/build/Build/Intermediates.noindex/PlayerBox.build/Release-iphoneos/PlayerBox.build/PlayerBox.DependencyMetadataFileList --source-file /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app/Info.plist --archive-ssu-assets
2026-11-13 11:55:36.983 appintentsnltrainingprocessor[3798:14975] Parsing options for appintentsnltrainingprocessor
2026-11-13 11:55:36.983 appintentsnltrainingprocessor[3798:14975] Starting AppIntents SSU YAML Generation
2026-11-13 11:55:36.987 appintentsnltrainingprocessor[3798:14975] No AppShortcuts found - Skipping.

RegisterExecutionPolicyException /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app (in target 'PlayerBox' from project 'PlayerBox')
    cd /Users/runner/work/PlayerBox/PlayerBox
    builtin-RegisterExecutionPolicyException /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app

Validate /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app (in target 'PlayerBox' from project 'PlayerBox')
    cd /Users/runner/work/PlayerBox/PlayerBox
    builtin-validationUtility /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app -shallow-bundle -infoplist-subpath Info.plist

Touch /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app (in target 'PlayerBox' from project 'PlayerBox')
    cd /Users/runner/work/PlayerBox/PlayerBox
    /usr/bin/touch -c /Users/runner/work/PlayerBox/PlayerBox/build/Build/Products/Release-iphoneos/PlayerBox.app

** BUILD SUCCEEDED **

EXIT_CODE=0
```
