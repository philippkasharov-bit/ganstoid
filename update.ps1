# Ganstoid updater. Brings this folder to the latest version on GitHub (and fetches
# the right Godot once). Used by launcher.ps1; can also be run on its own.
#   -StatusFile <path>  progress is written there, one line per step, for the launcher to show
#   -CheckOnly          only report whether an update exists (exit code 10 = yes, 0 = no)
# Result line is always the last one: "DONE <version>" or "ERROR <message>".
param([string]$StatusFile = '', [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is many times faster without its progress bar
$root = $PSScriptRoot
$godotVersion = '4.7.2-stable'
$godotDir = Join-Path (Split-Path $root -Parent) 'Godot'
$godot = Join-Path $godotDir "Godot_v$($godotVersion)_win64.exe"
$repo = 'philippkasharov-bit/ganstoid'
$tokenFile = Join-Path $root 'github_token.txt'
$versionFile = Join-Path $root 'version.txt'
# Folders that must match GitHub exactly: files deleted there are deleted here too.
# (Stale navmesh tiles left behind by the old copy-only updater made people walk wrong.)
$mirrored = @('core', 'data', 'debug', 'scenes', 'tools')
# Local-only folders inside those that the mirror must never delete: downloaded source
# data (LA parcels, OpenStreetMap cells) lives here and is not in the repo.
$keep = @((Join-Path $root 'tools\city\osm'))

function Say([string]$text) {
    Write-Host $text
    if ($StatusFile) { Add-Content -Path $StatusFile -Value $text -Encoding UTF8 }
}

try {
    if (-not (Test-Path $tokenFile)) { throw 'github_token.txt is missing from the game folder.' }
    $token = ([IO.File]::ReadAllText($tokenFile) -replace '[^\x21-\x7E]', '')   # keep printable ASCII only
    $headers = @{ Authorization = "Bearer $token"; 'User-Agent' = 'ganstoid-updater' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Say 'Checking for a new version...'
    $head = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$repo/commits/main"
    $latest = $head.sha.Substring(0, 7)
    $title = ($head.commit.message -split "`n")[0]
    $have = if (Test-Path $versionFile) { (Get-Content $versionFile -TotalCount 1).Split(' ')[0] } else { '' }
    $needGodot = -not (Test-Path $godot)
    if ($CheckOnly) {
        Say "LATEST $latest $title"
        if ($have -ne $latest -or $needGodot) { exit 10 } else { exit 0 }
    }

    if ($needGodot) {
        Say "Downloading Godot $godotVersion (one time, about 70 MB)..."
        $gzip = Join-Path $root '_godot.zip'
        Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/godotengine/godot/releases/download/$godotVersion/Godot_v$($godotVersion)_win64.exe.zip" -OutFile $gzip
        New-Item -ItemType Directory -Force $godotDir | Out-Null
        Expand-Archive -Force $gzip $godotDir
        Remove-Item $gzip -Force
    }

    if ($have -ne $latest) {
        Say "Downloading version $latest..."
        $zip = Join-Path $root '_update.zip'
        $tmp = Join-Path $root '_update'
        Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri "https://api.github.com/repos/$repo/zipball/main" -OutFile $zip
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        Say 'Unpacking...'
        Expand-Archive -Force $zip $tmp
        $inner = (Get-ChildItem $tmp | Select-Object -First 1).FullName
        Say 'Installing...'
        foreach ($dir in $mirrored) {
            $from = Join-Path $inner $dir
            if (Test-Path $from) {
                # /MIR = exact mirror. /XF keeps Godot's own sidecar files, which are not in the repo.
                robocopy $from (Join-Path $root $dir) /MIR /XF *.import /XD $keep /NFL /NDL /NJH /NJS /NP /R:2 /W:1 | Out-Null
                if ($LASTEXITCODE -ge 8) { throw "Could not copy the $dir folder (robocopy code $LASTEXITCODE). Is the game still running?" }
            }
        }
        Get-ChildItem $inner -File | Copy-Item -Destination $root -Force
        Remove-Item $tmp -Recurse -Force
        Remove-Item $zip -Force
        Say 'Preparing the game files (first start after an update takes a minute)...'
        $import = Start-Process -FilePath $godot -ArgumentList @('--headless', '--path', "`"$root`"", '--import') -Wait -PassThru -WindowStyle Hidden
        Set-Content -Path $versionFile -Value "$latest $title" -Encoding UTF8
    }
    Say "DONE $latest $title"
    exit 0
}
catch {
    $msg = $_.Exception.Message
    if ($msg -match '401') { $msg = 'GitHub refused the token (401). The token in github_token.txt has expired or is wrong.' }
    Say "ERROR $msg"
    exit 1
}
