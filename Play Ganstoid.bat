@echo off
setlocal
cd /d "%~dp0"
set GODOT=D:\PCash\Claude\Godot\Godot_v4.3-stable_win64.exe
set REPO=philippkasharov-bit/ganstoid

if not exist "github_token.txt" (
  echo First run: paste your GitHub token ^(read-only, repo "ganstoid"^) and press Enter.
  set /p TOKEN=Token: 
  >"github_token.txt" echo %TOKEN%
)
set /p TOKEN=<github_token.txt

echo Downloading the latest Ganstoid...
curl.exe -sS -L -f -H "Authorization: Bearer %TOKEN%" -H "User-Agent: ganstoid-updater" -o "_update.zip" "https://api.github.com/repos/%REPO%/zipball/main"
if errorlevel 1 (
  echo.
  echo Download failed. Check your internet and the token in github_token.txt ^(delete that file to enter it again^).
  pause
  exit /b 1
)
if exist "_update" rmdir /s /q "_update"
powershell -NoProfile -Command "Expand-Archive -Force '_update.zip' '_update'"
for /d %%D in ("_update\*") do xcopy /e /y /q "%%D\*" "%~dp0" >nul
rmdir /s /q "_update"
del "_update.zip"

echo Preparing...
"%GODOT%" --headless --path "%~dp0" --import >nul 2>&1
echo Starting the demo.
"%GODOT%" --path "%~dp0" res://scenes/city_demo.tscn
endlocal
