@echo off
setlocal enabledelayedexpansion
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
    echo [ERROR] Version update failed
    pause
    exit /b %errorlevel%
)
echo [OK] Version updated successfully
echo.

REM Build
echo [2/4] Building web app...
call flutter build web --release
if %errorlevel% neq 0 (
    echo [ERROR] Build failed
    pause
    exit /b %errorlevel%
)
echo [OK] Build completed successfully
echo.

REM Version.json másolása
echo [3/4] Verifying version.json in build...
if exist build\web\version.json (
    echo [OK] version.json found in build\web
) else (
    echo [WARNING] version.json not found, copying...
    copy web\version.json build\web\version.json
)
echo.

REM Firebase deploy to preview channel
echo [4/4] Deploying to Firebase Hosting Preview Channel: %CHANNEL_NAME%...
echo [NOTE] This will NOT overwrite the production version!
echo.

REM Deploy és output mentése temp fájlba
call firebase hosting:channel:deploy %CHANNEL_NAME% --expires 30d > temp_deploy_output.txt 2>&1
set DEPLOY_EXIT_CODE=%errorlevel%

REM Output megjelenítése
type temp_deploy_output.txt

if %DEPLOY_EXIT_CODE% neq 0 (
    del temp_deploy_output.txt
    echo.
    echo [ERROR] Deployment failed
    pause
    exit /b %DEPLOY_EXIT_CODE%
)

REM Preview URL kinyerése az output-ból PowerShell-lel
REM Keresünk egy URL-t ami tartalmazza a "--" részt (preview channel jelző)
set "PREVIEW_URL="
for /f "delims=" %%a in ('powershell -Command "$content = Get-Content temp_deploy_output.txt -Raw; if ($content -match ''Channel URL[^:]*:\s*(https://[^\s\]]+)'') { $matches[1] }"') do (
    set "PREVIEW_URL=%%a"
)

REM Temp fájl törlése
del temp_deploy_output.txt

echo.
echo ========================================
echo   [OK] Preview deployment completed!
echo   The production version was NOT changed.
echo ========================================
echo.

if defined PREVIEW_URL (
    echo Preview URL:
    echo %PREVIEW_URL%
    echo.
    echo Copy this URL and share it with testers.
    echo This preview will expire in 30 days.
) else (
    echo [WARNING] Preview URL not found in output.
    echo    Check Firebase Console for the preview URL.
)

echo ========================================
echo.
pause



















