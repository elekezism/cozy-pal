# cactus_native

Local Flutter plugin that ships the prebuilt Cactus engine with the app.

- Android: `android/src/main/jniLibs/arm64-v8a/libcactus_engine.so`
- iOS: `ios/cactus-ios.xcframework`

Both are produced by building https://github.com/cactus-compute/cactus
(`bash android/build.sh` with the Android NDK, `bash apple/build.sh` on a Mac)
and copied here by `dart run tool/setup_platforms.dart --cactus <path-to-cactus-repo>`.
