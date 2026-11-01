@echo off
rem Builds dist\Marka-Setup.exe. Files from a downloaded zip are unblocked first, as in Speedware/tandem.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -Recurse -File | Unblock-File"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1"
pause
