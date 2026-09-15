@echo off
setlocal
chcp 65001 >nul
echo WD1 只读诊断：不联网、不上传、不修改游戏或存档。
echo 请先将整个准备包解压到游戏目录以外，再运行。
echo 本启动器不会更改 PowerShell 执行策略。
echo.
powershell.exe -NoLogo -NoProfile -File "%~dp0tools\Collect-WD1Info.ps1"
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" (
  echo.
  echo 未完成。若脚本被系统执行策略阻止，不要关闭安全软件。
  echo 可以使用 README.zh-CN.md 中的手动收集方法。
)
echo.
pause
exit /b %RESULT%
