@echo off
rem Publish update package (wrapper runnable from PowerShell/cmd).
rem Usage: publish_update.cmd \\192.168.170.201\public\ptest_update
rem Backslashes or forward slashes both fine - converted for Git Bash below.
rem Why this wrapper exists: .sh files do NOT run in PowerShell (handed to the
rem file association, usually nothing visible happens).
rem NOTE: keep this file ASCII-only. cmd.exe reads batch files in the system
rem codepage (GBK here); UTF-8 Chinese comments turn into garbage commands.
setlocal
if "%~1"=="" (
    echo Usage: publish_update.cmd ^<target-share-dir^>
    echo Example: publish_update.cmd \\192.168.170.201\public\ptest_update
    exit /b 1
)
set "TARGET=%~1"
set "TARGET=%TARGET:\=/%"
set "BASH=C:\Program Files\Git\bin\bash.exe"
if not exist "%BASH%" (
    echo FAIL: Git Bash not found at %BASH%
    exit /b 1
)
"%BASH%" "%~dp0publish_update.sh" "%TARGET%"
endlocal
