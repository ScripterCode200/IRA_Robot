# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Google ML Kit & MediaPipe
-keep class com.google.mlkit.** { *; }
-keep class com.google.mediapipe.** { *; }

# Keep protobuf classes used by MediaPipe
-keep class com.google.protobuf.** { *; }
-keep class com.google.mediapipe.proto.** { *; }
-keep class com.google.mediapipe.framework.** { *; }

# Workaround for the missing classes error
-dontwarn com.google.mediapipe.**
-dontwarn com.google.protobuf.**

# Ignore missing Play Core / Split App classes in Flutter deferred components
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
-dontwarn io.flutter.embedding.android.FlutterPlayStoreSplitApplication