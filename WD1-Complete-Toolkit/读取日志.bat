@echo off
title WD1KIT log finder
rem Finds WD1KIT_log.txt next to this bat or in TEMP, copies it to Desktop.
set "FOUND="
if exist "WD1KIT_log.txt" set "FOUND=%CD%\WD1KIT_log.txt"
if defined FOUND goto COPY
if exist "%TEMP%\WD1KIT_log.txt" set "FOUND=%TEMP%\WD1KIT_log.txt"
if defined FOUND goto COPY
echo [X] WD1KIT_log.txt not found in this folder or in TEMP.
echo     Put this bat into the game install folder, next to watch_dogs.exe,
echo     then run it again. Or search the game folder for: WD1KIT_log.txt
pause
exit /b
:COPY
echo Found: "%FOUND%"
copy /y "%FOUND%" "%USERPROFILE%\Desktop\WD1KIT_log.txt" >nul
echo.
echo Copied to your Desktop as WD1KIT_log.txt
echo Send that file to the assistant. Content = every plugin action this session.
pause
