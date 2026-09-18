@echo off
rem WD1 append bisect v3.1 - drag your data_win64 folder onto this file
setlocal EnableExtensions
set "GD=%~1"
if defined GD goto :menu
echo Drag your data_win64 folder onto this file,
set /p "GD=or type the full data_win64 path and press Enter: "
if not defined GD (
  echo No path given.
  pause
  goto :eof
)
:menu
set "GD=%GD:"=%"
if "%GD:~-1%"=="\" set "GD=%GD:~0,-1%"
set "TD=%~dp0"
if "%TD:~-1%"=="\" set "TD=%TD:~0,-1%"
echo data dir : "%GD%"
echo Which variant?
echo   1 = NATIVE  : NGM original car DB (baseline sanity, expect NO crash)
echo   2 = SPEED08 : NGM + Speed_08 only (1 self-built record)
echo   3 = HIDDEN44: NGM + all 44 hidden-slot records
echo   4 = FULL74  : NGM + 44 + Speed_08 (same content as v2.7 / v3.0)
echo   5 = RESTORE : clean NGM original (no append at all)
echo   6 = HIDDEN 1st half (22 of the 44)
echo   7 = HIDDEN 2nd half (22 of the 44)
set /p "C=Type 1-7 and press Enter: "
if "%C%"=="1" set "V=native"
if "%C%"=="2" set "V=B_speed08"
if "%C%"=="3" set "V=C_hidden44"
if "%C%"=="4" set "V=D_full"
if "%C%"=="6" set "V=C1_h22"
if "%C%"=="7" set "V=C2_h22"
if "%C%"=="5" goto :restore
if not defined V goto :bad
echo tool dir : "%TD%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TD%\Append-Bisect.ps1" -DataDir "%GD%" -ToolDir "%TD%" -BlobPath "%TD%\blob_%V%.bin" -Tag %V%
echo.
pause
goto :eof
:restore
copy /y "%GD%\patch.dat.carbak" "%GD%\patch.dat" >nul
copy /y "%GD%\patch.fat.carbak" "%GD%\patch.fat" >nul
echo Restored clean NGM original from .carbak.
pause
goto :eof
:bad
echo Nothing selected.
pause
