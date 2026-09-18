@echo off
rem WD1 archive compare - drag your data_win64 folder onto this file
setlocal EnableExtensions
set "GD=%~1"
if defined GD goto :ask
echo Drag your data_win64 folder onto this file,
set /p "GD=or type the full data_win64 path and press Enter: "
if not defined GD (
  echo No path given.
  pause
  goto :eof
)
:ask
set "GD=%GD:"=%"
if "%GD:~-1%"=="\" set "GD=%GD:~0,-1%"
echo Now paste the folder that contains the ORIGINAL NGM patch.dat / patch.fat
set /p "REF=(the ones from the NGM zip, NOT from the game) and press Enter: "
if not defined REF (
  echo No reference path given.
  pause
  goto :eof
)
set "REF=%REF:"=%"
if "%REF:~-1%"=="\" set "REF=%REF:~0,-1%"
set "TD=%~dp0"
if "%TD:~-1%"=="\" set "TD=%TD:~0,-1%"
echo game dir : "%GD%"
echo ref  dir : "%REF%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TD%\Compare-Archive.ps1" -GameDir "%GD%" -RefDir "%REF%"
echo.
pause
