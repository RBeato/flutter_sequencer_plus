# Build System Fixes

This document outlines fixes for build issues in the flutter_sequencer plugin.

## April 13, 2023: Fixed Android Build Issues

### Problems Fixed

1. **Kotlin Syntax Errors** - Several syntax errors in the Kotlin code were fixed:
   - Incorrect usage of `return@try` statements in the FlutterSequencerPlugin.kt file
   - These were causing compilation failures with error messages like "Label must be named", "Expecting '{' to open a block", and "Expecting 'catch' or 'finally'"

2. **C++ Include Path Issues** - Fixed issues with missing header files:
   - Header files (`Buffer.h`, `CallbackManager.h`) were not being found during compilation
   - The error messages indicated that includes using angle brackets (`<>`) failed to resolve
   - Files with quoted includes (`""`) weren't in the include path

### Solutions Implemented

1. **Kotlin Fix**:
   - Replaced all `return@try` statements with simple `return` statements
   - This ensures proper syntax in the try/catch blocks

2. **C++ Include Path Fix**:
   - Updated CMakeLists.txt to include all necessary directories:
     ```cmake
     include_directories(
         ${CMAKE_CURRENT_SOURCE_DIR}/../ios/Classes
         ${CMAKE_CURRENT_SOURCE_DIR}/../ios/Classes/CallbackManager
         ${CMAKE_CURRENT_SOURCE_DIR}/../ios/Classes/Scheduler
         ${CMAKE_CURRENT_SOURCE_DIR}/../ios/Classes/IInstrument
         ${CMAKE_CURRENT_SOURCE_DIR}/../ios/Classes/AudioUnit
         ${CMAKE_CURRENT_SOURCE_DIR}/../cpp_test/src
         ${CMAKE_CURRENT_SOURCE_DIR}/src/main/cpp
         ${CMAKE_CURRENT_SOURCE_DIR}/src/main/cpp/AndroidEngine
         ${CMAKE_CURRENT_SOURCE_DIR}/src/main/cpp/AndroidInstruments
         ${CMAKE_CURRENT_SOURCE_DIR}/src/main/cpp/Utils
     )
     ```

3. **Include Style Fix**:
   - Changed includes in BaseScheduler.h from angle brackets to quotes:
     ```cpp
     // Old:
     #include <Buffer.h>
     #include <CallbackManager.h>
     #include <SchedulerEvent.h>

     // New:
     #include "Buffer.h"
     #include "CallbackManager.h"
     #include "SchedulerEvent.h"
     ```

### Technical Details

1. **Shared Code Structure**:
   - The project uses shared C++ code between iOS and Android
   - Header files are primarily in the iOS directory, but need to be accessible to Android builds

2. **Include Path Resolution**:
   - Local header files should use quotes (`#include "header.h"`) not angle brackets (`#include <header.h>`)
   - Angle brackets are primarily for system headers and libraries
   - CMake include_directories() is used to tell the compiler where to search for headers

3. **Kotlin Syntax Note**:
   - In Kotlin, labeled returns (like `return@try`) need explicit labels
   - For simple returns from a try block, just use `return` without labels

### Future Considerations

1. **Consistent Include Style**:
   - All local headers should use quotes consistently
   - System/library headers should use angle brackets

2. **Reorganize Shared Code**:
   - Consider moving shared code to a common directory outside platform-specific folders
   - This would make include paths more intuitive and less fragile

3. **Build Script Validation**:
   - Add a validation step to the build process to catch these issues earlier
   
## April 14, 2023: Fixed Gradle Task Dependencies and Java Version

### Problems Fixed

1. **Gradle Task Dependency Issue**:
   - The `mergeDebugJniLibFolders` task was using output from `copyDebugSharedLibs` without a proper dependency
   - This caused the build error: "Task uses this output without declaring an explicit or implicit dependency"
   - The error appeared after fixing the C++ build issues and making the jniLibs directory available

2. **Java Version Warnings**:
   - Warnings about obsolete Java 8 source/target options
   - These warnings indicate that Java 8 will be removed in future Gradle versions

### Solutions Implemented

1. **Gradle Task Dependency Fix**:
   - Added explicit dependencies between the tasks:
   ```gradle
   // Make mergeJniLibFolders task also depend on the copy task
   mergeJniTask.dependsOn copyLibTask
   
   // Explicitly set the dependency using mustRunAfter to ensure correct order
   mergeJniTask.mustRunAfter copyLibTask
   ```
   - This ensures that the copy task runs before the merge task, and that Gradle knows about this dependency

2. **Java Version Update**:
   - Updated the Java compatibility to Java 11:
   ```gradle
   compileOptions {
       sourceCompatibility JavaVersion.VERSION_11
       targetCompatibility JavaVersion.VERSION_11
   }

   kotlinOptions {
       jvmTarget = '11'
   }
   ```
   - This resolves warnings and ensures compatibility with newer Android Gradle Plugin versions

### Technical Details

1. **Gradle Task Dependency Types**:
   - `dependsOn`: Establishes that one task must complete before another starts
   - `mustRunAfter`: Enforces order when tasks would otherwise run in parallel
   - Using both ensures correct build order and dependency tracking

2. **Java Version Compatibility**:
   - Java 8 is becoming obsolete for Android development
   - Java 11 is the recommended minimum for current Android development
   - Flutter 3.19.0+ works well with Java 11

## April 15, 2023: Fixed JDK Image Generation Issue

### Problem Fixed

1. **JDK Image Generation Error**:
   - After updating to Java 11, encountered an error during the build process:
   - `Failed to transform core-for-system-modules.jar to match attributes {artifactType=_internal_android_jdk_image...}`
   - This is related to how recent Gradle versions handle JDK image generation for Android builds
   - The error occurred in the `:flutter_sequencer:compileDebugJavaWithJavac` task

### Solutions Implemented

1. **Disabled JDK Image Generation**:
   - Added a system property to disable JDK image generation:
   ```gradle
   // Workaround for Gradle JDK image issue
   System.setProperty('android.natives.jdkImagePath', null)
   ```

2. **Added Gradle Properties**:
   - Updated gradle.properties with several settings to fix JDK compatibility:
   ```properties
   # Disable JDK image generation which is causing issues
   android.native.buildOutput=none
   
   # Explicitly set the Java home to use the embedded JDK
   org.gradle.java.home=
   
   # Performance options
   org.gradle.parallel=true
   org.gradle.caching=true
   ```

3. **Added Compiler Arguments**:
   - Added compiler arguments to handle warnings and ensure compatibility:
   ```gradle
   gradle.projectsEvaluated {
       tasks.withType(JavaCompile) {
           options.compilerArgs << "-Xlint:unchecked" << "-Xlint:deprecation"
       }
   }
   ```

### Technical Details

1. **JDK Image Issue**:
   - The Android Gradle Plugin uses a feature called JDK image generation to optimize build performance
   - This can cause compatibility issues when mixing different JDK versions or with certain Gradle configurations
   - Disabling this feature sacrifices some build performance but eliminates compatibility problems

2. **Gradle Properties**:
   - `android.native.buildOutput=none`: Disables native build output processing which can trigger JDK image issues
   - `org.gradle.java.home=`: Lets Gradle use the default JDK path instead of trying to override it
   - `org.gradle.parallel=true`: Enables parallel task execution for faster builds
   - `org.gradle.caching=true`: Enables build caching for faster subsequent builds

3. **Future-Proofing**:
   - These changes should ensure compatibility with the latest Android development tools
   - Aligns with best practices for modern Android development with Flutter 3.19.0+

## April 16, 2023: Fixed NullPointerException in build.gradle

### Problem Fixed

1. **NullPointerException in build.gradle**:
   - After adding the System.setProperty() workaround, encountered a NullPointerException
   - This led to a failure in project evaluation with errors about compileSdkVersion not being specified
   - Build failed with "Cannot invoke method substring() on null object"

### Solutions Implemented

1. **Removed System.setProperty Call**:
   - Removed the problematic line: `System.setProperty('android.natives.jdkImagePath', null)`
   - This was causing a NullPointerException during Gradle evaluation

2. **Reorganized build.gradle Structure**:
   - Moved compileSdkVersion to the top of the android block to ensure it's recognized early
   - Moved the gradle.projectsEvaluated block after the android block to ensure proper initialization
   - Simplified the gradle.properties file to remove potentially problematic settings

3. **Simplified gradle.properties**:
   - Removed problematic settings related to JDK image generation
   - Kept only essential Android and Gradle configuration properties
   - Organized properties into logical groups with comments

### Technical Details

1. **Build Script Evaluation Order**:
   - Gradle processes the build script in a specific order
   - Code outside configuration blocks runs during evaluation
   - System.setProperty() at script level can cause issues if it affects Gradle's own functioning

2. **Alternative Approaches to JDK Issues**:
   - Instead of using System.setProperty, rely on standard Gradle configuration mechanisms
   - Moving compiler configurations inside the proper project evaluation phase
   - Using gradle.properties for performance and feature toggles rather than direct system property manipulation

3. **Troubleshooting Build Issues**:
   - Look for "Evaluating project" errors first, as they indicate problems in the build script itself
   - Null pointer exceptions often indicate using uninitialized properties or accessing properties at the wrong time
   - "Cannot invoke method on null object" usually points to an initialization order problem 