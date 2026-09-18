@echo off
rem WD1 car splice v3.0 (append mode) - drag your data_win64 folder onto this file
setlocal EnableExtensions
set "GD=%~1"
if defined GD goto :run
echo Drag your data_win64 folder onto this file,
set /p "GD=or type the full data_win64 path and press Enter: "
if not defined GD (
  echo No path given.
  pause
  goto :eof
)
:run
set "GD=%GD:"=%"
if "%GD:~-1%"=="\" set "GD=%GD:~0,-1%"
set "TD=%~dp0"
if "%TD:~-1%"=="\" set "TD=%TD:~0,-1%"
echo data dir : "%GD%"
echo tool dir : "%TD%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TD%\Splice-CarUnlock-Append.ps1" -DataDir "%GD%" -ToolDir "%TD%"
echo.
pause
