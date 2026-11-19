@echo off
REM Double-click this file to start the Rudvaya demo. It runs start-n8n.ps1
REM with the execution policy bypassed just for this one launch (does not
REM change any system-wide PowerShell setting).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-n8n.ps1"
pause
