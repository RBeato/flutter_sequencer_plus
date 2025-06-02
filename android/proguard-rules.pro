# Keep native methods for JNI
-keepclasseswithmembernames class * {
    native <methods>;
}
# Keep AssetManager usage (if any)
-keep class android.content.res.AssetManager { *; }
