# Android Build Issues and Fixes

This document outlines common build issues encountered with the Flutter Sequencer plugin on Android and their solutions.

## Flutter 3.0.0+ Compatibility

### Symptoms
When using Flutter 3.0.0 or newer, you might encounter one of these errors:
```
Execution failed for task ':app:checkDebugDuplicateClasses'
```
or
```
Cannot run Project.afterEvaluate(Closure) when the project is already evaluated
```

### Cause
Flutter 3.0.0+ uses Gradle in a way that can conflict with our dependency exclusion and project evaluation approach. The Flutter embedding has specific Kotlin dependencies that might be affected by our global exclusions.

### Solution
We've made several changes to accommodate Flutter 3.0.0+ requirements:

1. **More selective exclusions**: Instead of excluding Kotlin libraries globally, we now use more targeted approaches:
   ```gradle
   // Only exclude from non-Flutter configurations
   if (!configurations.name.startsWith("flutter")) {
       exclude group: 'org.jetbrains.kotlin', module: 'kotlin-stdlib-jdk7'
       exclude group: 'org.jetbrains.kotlin', module: 'kotlin-stdlib-jdk8'
   }
   ```

2. **Using eachDependency instead of direct version forcing**:
   ```gradle
   eachDependency { details ->
       if (details.requested.group == 'org.jetbrains.kotlin' && 
           (details.requested.name == 'kotlin-stdlib-jdk7' || 
            details.requested.name == 'kotlin-stdlib-jdk8')) {
           details.useVersion kotlin_version
       }
   }
   ```

3. **Removed afterEvaluate blocks**: We now use ext properties for configuration sharing instead of afterEvaluate blocks, which can cause timing issues with Flutter 3.0.0+.

## Gradle Project Evaluation Issues

### Symptoms
```
A problem occurred evaluating root project 'android'.
> Cannot run Project.afterEvaluate(Closure) when the project is already evaluated.
```

### Cause
The `afterEvaluate` block is being called on a project that has already been evaluated by Gradle. This typically happens when the build script uses `afterEvaluate` incorrectly or when there are dependencies between projects that cause evaluation order issues.

### Solution
Instead of using `afterEvaluate`, we've switched to using a more reliable approach with `ext` properties in the root project:

1. Define common properties in the root project's `ext` block:
```gradle
// In root build.gradle
ext {
    kotlin_version = buildscript.ext.kotlin_version
    compileSdkVersion = 33
    targetSdkVersion = 33
    minSdkVersion = 21
    ndkVersion = "21.4.7075529"
}
```

2. Reference these properties in subprojects:
```gradle
// In app/build.gradle
compileSdkVersion rootProject.ext.compileSdkVersion
minSdkVersion rootProject.ext.minSdkVersion
```

This approach is more reliable because it doesn't depend on project evaluation timing.

## Kotlin Version Conflicts

### Symptoms
```
Execution failed for task ':app:checkDebugDuplicateClasses'.
> Duplicate class kotlin.collections.jdk8.CollectionsJDK8Kt found in modules...
> Duplicate class kotlin.internal.jdk7.JDK7PlatformImplementations found in modules...
```

### Cause
Different parts of the project are using different Kotlin versions, causing duplicate classes to be included in the build. This typically happens when a newer version of Kotlin is pulled in by a transitive dependency.

### Solution
For Flutter 3.0.0+ compatibility, we use a more selective approach:

```gradle
// In configurations.all
resolutionStrategy {
    force "org.jetbrains.kotlin:kotlin-stdlib:$kotlin_version"
    force "org.jetbrains.kotlin:kotlin-stdlib-common:$kotlin_version"
    
    // Handle version conflicts conditionally
    eachDependency { details ->
        if (details.requested.group == 'org.jetbrains.kotlin' && 
            (details.requested.name == 'kotlin-stdlib-jdk7' || 
             details.requested.name == 'kotlin-stdlib-jdk8')) {
            details.useVersion kotlin_version
        }
    }
}

// Use more selective exclusion
if (!configurations.name.startsWith("flutter")) {
    exclude group: 'org.jetbrains.kotlin', module: 'kotlin-stdlib-jdk7'
    exclude group: 'org.jetbrains.kotlin', module: 'kotlin-stdlib-jdk8'
}
```

In the app's dependencies, we just use the base stdlib:
```gradle
implementation "org.jetbrains.kotlin:kotlin-stdlib:${rootProject.ext.kotlin_version}"
```

## Advanced Kotlin Conflict Resolution

For more stubborn Kotlin conflicts, we've applied multiple strategies:

1. **Root-level configuration** - Setting the same Kotlin version throughout all projects:
   ```gradle
   // In root build.gradle
   buildscript {
       ext.kotlin_version = '1.7.10'
       // ...
   }
   ```

2. **Module consistency** - Using ext properties to ensure all modules use the same versions:
   ```gradle
   ext {
       kotlin_version = buildscript.ext.kotlin_version
       compileSdkVersion = 33
   }
   ```

3. **Packaging options** - For resource conflicts with newer Gradle versions:
   ```gradle
   packagingOptions {
       resources {
           excludes += ['/META-INF/{AL2.0,LGPL2.1}', 'META-INF/LICENSE.md', 'META-INF/LICENSE-notice.md']
       }
       jniLibs {
           useLegacyPackaging true
       }
   }
   ```

## Android API 34 Permission Issues

### Symptoms
```
e: Unresolved reference: FOREGROUND_SERVICE_MEDIA_PLAYBACK
```

### Cause
The code references `Manifest.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK` which was introduced in Android 14 (API 34), but the code doesn't properly handle older Android versions.

### Solution
We've improved our permission handling code to use more robust reflection with full class name resolution rather than assuming the class structure:

```kotlin
if (Build.VERSION.SDK_INT >= 34) {
    try {
        // Use string literal to avoid direct class reference that would cause compilation errors
        val permissionName = "android.Manifest$permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"
        val lastDot = permissionName.lastIndexOf('.')
        if (lastDot > 0 && lastDot < permissionName.length - 1) {
            val className = permissionName.substring(0, lastDot).replace('$', '$')
            val fieldName = permissionName.substring(lastDot + 1)
            
            try {
                val clazz = Class.forName(className)
                val field = clazz.getField(fieldName)
                val permissionValue = field.get(null) as String
                add(permissionValue)
                Log.d("Tag", "Added Android 14 permission: $permissionValue")
            } catch (e: Exception) {
                Log.w("Tag", "Could not add Android 14 permission: ${e.message}")
            }
        }
    } catch (e: Exception) {
        Log.w("Tag", "Failed to add Android 14 permissions: ${e.message}")
    }
}
```

This approach:
1. Uses string literals to avoid direct class references to newer APIs
2. Properly handles errors at multiple levels
3. Provides detailed logging about which specific step failed

## C/C++ Extension License Warning

### Symptoms
```
"The C/C++ extension may be used only with Microsoft Visual Studio, Visual Studio for Mac, Visual Studio Code..."
```

### Cause
This is just a warning displayed by the C/C++ extension about its license terms. It doesn't affect building or functionality.

### Solution
No action required. This is simply informational.

## XML Parse Warnings

### Symptoms
```
Warning: unexpected element (uri:"", local:"abis"). Expected elements are <{}vendor>...
Warning: Errors during XML parse:
```

### Cause
These warnings are related to the Android platform files and don't typically affect the build. They usually come from platform SDK descriptors.

### Solution
These warnings can typically be ignored as they don't affect functionality.

## NDK Installation Notes

### Symptoms
```
Installing NDK (Side by side) 21.4.7075529 in /Users/rbsou/Library/Android/sdk/ndk/21.4.7075529
```

### Cause
The build system is downloading and installing the NDK version specified in your `build.gradle` file.

### Solution
This is normal behavior when building for the first time or with a new NDK version. No action required.

## General Troubleshooting Tips

1. **Clean Build**: Always try a clean build when encountering issues:
   ```
   flutter clean
   cd android && ./gradlew clean
   flutter pub get
   ```

2. **Check Kotlin Versions**: Ensure all modules use the same Kotlin version:
   - In android/build.gradle
   - In example/android/build.gradle
   - In the app's dependencies

3. **NDK Version**: The project uses a specific NDK version (21.4.7075529) for native code. Make sure it's properly installed.

4. **Library Loading**: For native library loading issues, check the comprehensive guide in android-library-loading.md. 