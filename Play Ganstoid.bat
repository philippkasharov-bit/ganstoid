@echo off
rem Opens the Ganstoid launcher window (update, play, see errors).
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0launcher.ps1"
