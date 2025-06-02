@echo off

REM Create third_party directory if it doesn't exist
if not exist "third_party" mkdir third_party

REM Download and extract Oboe
if not exist "third_party\oboe" (
    echo Downloading Oboe...
    curl -L -o oboe.zip https://github.com/google/oboe/archive/refs/tags/1.7.0.zip
    powershell -Command "Expand-Archive -Path oboe.zip -DestinationPath third_party\"
    move "third_party\oboe-1.7.0" "third_party\oboe"
    del oboe.zip
)

REM Download and extract sfizz
if not exist "third_party\sfizz" (
    echo Downloading sfizz...
    REM Update this URL to point to your prebuilt sfizz Android library
    curl -L -o sfizz.zip [YOUR_PREBUILT_SFIZZ_URL]
    powershell -Command "Expand-Archive -Path sfizz.zip -DestinationPath third_party\"
    del sfizz.zip
)

echo Android dependencies prepared successfully!
