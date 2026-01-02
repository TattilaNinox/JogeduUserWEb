@echo off
REM =========================================================
REM   JOGEDU USER APP DEPLOY SCRIPT
REM   Ez a script buildeli es deploy-olja a user app-ot
REM   az audio fajlokkal egyutt.
REM
REM   HASZNALAT: Masold ezt a fajlt a jogedu_user_web mappaba
REM              es futtasd: deploy.bat
REM =========================================================

echo.
echo =====================================================
echo   JOGEDU USER APP DEPLOY
echo =====================================================
echo.

REM 1. Flutter build
echo [1/3] Flutter build web...
call flutter build web
if errorlevel 1 (
    echo HIBA: Flutter build sikertelen!
    pause
    exit /b 1
)

REM 2. Audio mappa masolasa az admin projektbol
echo.
echo [2/3] Audio mappa masolasa...
if not exist "build\web\audio" mkdir "build\web\audio"
xcopy /E /Y /I "C:\PROJEKTEK\orlomed_admin_web\web\audio" "build\web\audio"
if errorlevel 1 (
    echo HIBA: Audio mappa masolasa sikertelen!
    pause
    exit /b 1
)

REM 3. Firebase deploy
echo.
echo [3/3] Firebase deploy...
call firebase deploy --only hosting:jogedu
if errorlevel 1 (
    echo HIBA: Firebase deploy sikertelen!
    pause
    exit /b 1
)

echo.
echo =====================================================
echo   DEPLOY KESZ!
echo   URL: https://jogedu.web.app
echo =====================================================
echo.
pause
