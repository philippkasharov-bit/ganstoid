# Downloads the latest Ganstoid from the private GitHub repo, then starts the city demo.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$godot = 'D:\PCash\Claude\Godot\Godot_v4.3-stable_win64.exe'
$repo = 'philippkasharov-bit/ganstoid'
$tokenFile = Join-Path $root 'github_token.txt'
try {
    if (-not (Test-Path $tokenFile)) {
        $typed = Read-Host 'Paste your GitHub token (read-only, repo ganstoid) and press Enter'
        [IO.File]::WriteAllText($tokenFile, $typed.Trim(), [Text.Encoding]::ASCII)
    }
    $token = ([IO.File]::ReadAllText($tokenFile) -replace '[^\x21-\x7E]', '')   # keep printable ASCII only
    Write-Host 'Downloading the latest Ganstoid...'
    $zip = Join-Path $root '_update.zip'
    $tmp = Join-Path $root '_update'
    $headers = @{ Authorization = "Bearer $token"; 'User-Agent' = 'ganstoid-updater' }
    Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri "https://api.github.com/repos/$repo/zipball/main" -OutFile $zip
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Archive -Force $zip $tmp
    $inner = Get-ChildItem $tmp | Select-Object -First 1
    Copy-Item -Path (Join-Path $inner.FullName '*') -Destination $root -Recurse -Force
    Remove-Item $tmp -Recurse -Force
    Remove-Item $zip -Force
    Write-Host 'Preparing...'
    & $godot --headless --path $root --import 2>&1 | Out-Null
    Write-Host "Starting Ganstoid."
    & $godot --path $root res://scenes/main.tscn
}
catch {
    Write-Host ''
    Write-Host "Update failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'If it says 401, delete github_token.txt and run again to enter a new token.'
    Read-Host 'Press Enter to close'
}
