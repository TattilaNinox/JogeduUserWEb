@echo off
REM Automatikus deployment script Windows-ra
REM Használat: deploy.bat

echo.
echo ========================================
echo   Lomedu Web App - Deployment Script
echo ========================================
echo.

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

REM Version.json másolása (már megtörtént a dart script által)
echo [3/4] Verifying version.json in build...
if exist build\web\version.json (
    echo ✅ version.json found in build\web
) else (
    echo ⚠️  Warning: version.json not found, copying...
    copy web\version.json build\web\version.json
)
echo.

REM Firebase deploy
echo [4/4] Deploying to Firebase Hosting...
call firebase deploy --only hosting
if %errorlevel% neq 0 (
    echo ❌ Error: Deployment failed
    pause
    exit /b %errorlevel%
)
echo.

echo ========================================
echo   ✅ Deployment completed successfully!
echo ========================================
echo.
pause

