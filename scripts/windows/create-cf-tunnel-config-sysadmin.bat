@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0create-cf-tunnel-config-sysadmin.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"
endlocal & exit /b %EXIT_CODE%
