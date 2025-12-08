@echo off
REM Preview deployment script Windows-ra
REM Feltölt egy preview channel-re, NEM írja felül az éles verziót
REM Használat: deploy-preview.bat [channel-name]

echo.
echo ========================================
echo   Lomedu Web App - Preview Deployment
echo   (Nem írja felül az éles verziót!)
echo ========================================
echo.

REM Channel név beállítása
set CHANNEL_NAME=%1
if "%CHANNEL_NAME%"=="" (
    set CHANNEL_NAME=preview
)

REM Verzió frissítés ellenőrzése
echo [1/4] Updating version.json...
dart tools\update_version.dart
if %errorlevel% neq 0 (
    echo ❌ Error: Version update failed
    pause
    exit /b %errorlevel%
)
echo ✅ Version updated successfully
echo.

REM Build
echo [2/4] Building web app...
call flutter build web --release
if %errorlevel% neq 0 (
    echo ❌ Error: Build failed
    pause
    exit /b %errorlevel%
)
echo ✅ Build completed successfully
echo.

REM Version.json másolása
echo [3/4] Verifying version.json in build...
if exist build\web\version.json (
    echo ✅ version.json found in build\web
) else (
    echo ⚠️  Warning: version.json not found, copying...
    copy web\version.json build\web\version.json
)
echo.

REM Firebase deploy to preview channel
echo [4/4] Deploying to Firebase Hosting Preview Channel: %CHANNEL_NAME%...
echo ⚠️  NOTE: This will NOT overwrite the production version!
echo.
call firebase hosting:channel:deploy %CHANNEL_NAME% --expires 30d
if %errorlevel% neq 0 (
    echo ❌ Error: Deployment failed
    pause
    exit /b %errorlevel%
)
echo.
echo ========================================
echo   ✅ Preview deployment completed!
echo   The production version was NOT changed.
echo ========================================
echo.
pause



















