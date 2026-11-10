# Ganstoid launcher: one window to update, start and check the game.
#   Play                 update if there is a newer version, then start
#   Play without update  start what is installed (works offline)
#   after the game closes: how long it ran and how many errors it logged
#   Open last log        the full text of the last run, to send when something is broken
# -SelfTest <png> draws the window to a picture and exits (used to check the launcher itself).
param([string]$SelfTest = '')
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$root = $PSScriptRoot
$godotVersion = '4.7.2-stable'
$godot = Join-Path (Join-Path (Split-Path $root -Parent) 'Godot') "Godot_v$($godotVersion)_win64.exe"
$versionFile = Join-Path $root 'version.txt'
$statusFile = Join-Path $root '_launcher_status.txt'
$logFile = Join-Path $root 'last_run.log'
$script:job = $null      # the updater process while it runs
$script:game = $null     # the game process while it runs
$script:gameStarted = $null
$script:playAfter = $false

$bg = [Drawing.Color]::FromArgb(24, 26, 32)
$panel = [Drawing.Color]::FromArgb(36, 39, 48)
$ink = [Drawing.Color]::FromArgb(232, 232, 236)
$dim = [Drawing.Color]::FromArgb(150, 154, 166)
$accent = [Drawing.Color]::FromArgb(46, 160, 92)
$bad = [Drawing.Color]::FromArgb(224, 96, 88)

function New-Label($text, $x, $y, $w, $h, $size, $color, $bold) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text; $l.Left = $x; $l.Top = $y; $l.Width = $w; $l.Height = $h; $l.ForeColor = $color
    $style = if ($bold) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }
    $l.Font = New-Object Drawing.Font('Segoe UI', $size, $style)
    $form.Controls.Add($l); $l
}
function New-Button($text, $x, $y, $w, $h, $back) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $text; $b.Left = $x; $b.Top = $y; $b.Width = $w; $b.Height = $h
    $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0; $b.BackColor = $back; $b.ForeColor = $ink
    $b.Font = New-Object Drawing.Font('Segoe UI', 10.5, [Drawing.FontStyle]::Bold)
    $form.Controls.Add($b); $b
}

$form = New-Object Windows.Forms.Form
$form.Text = 'Ganstoid'; $form.ClientSize = New-Object Drawing.Size(560, 372)
$form.StartPosition = 'CenterScreen'; $form.FormBorderStyle = 'FixedSingle'; $form.MaximizeBox = $false
$form.BackColor = $bg

$null = New-Label 'GANSTOID' 28 22 400 44 24 $ink $true
$null = New-Label 'development build' 32 66 300 20 9 $dim $false
$installed = New-Label '' 32 104 500 22 10 $ink $false
$latest = New-Label '' 32 128 500 22 10 $dim $false
$play = New-Button 'Play' 32 170 240 52 $accent
$playOffline = New-Button 'Play without update' 288 170 240 52 $panel
$full = New-Object Windows.Forms.CheckBox
$full.Text = 'Full screen'; $full.Left = 34; $full.Top = 232; $full.Width = 200; $full.ForeColor = $dim
$full.Font = New-Object Drawing.Font('Segoe UI', 9.5); $form.Controls.Add($full)
$bar = New-Object Windows.Forms.ProgressBar
$bar.Left = 32; $bar.Top = 266; $bar.Width = 496; $bar.Height = 8; $bar.Style = 'Marquee'; $bar.Visible = $false
$form.Controls.Add($bar)
$status = New-Label 'Ready.' 32 282 496 22 10 $ink $false
$lastRun = New-Label '' 32 306 496 22 9.5 $dim $false
$openLog = New-Button 'Open last log' 32 332 150 28 $panel
$openFolder = New-Button 'Open game folder' 192 332 150 28 $panel
foreach ($b in @($openLog, $openFolder)) { $b.Font = New-Object Drawing.Font('Segoe UI', 9) }

function Show-Installed {
    if (Test-Path $versionFile) {
        $v = Get-Content $versionFile -TotalCount 1
        $installed.Text = "Installed:  $v"
    } else { $installed.Text = 'Installed:  version unknown (press Play to update)' }
}
function Set-Busy([bool]$busy) {
    $play.Enabled = -not $busy; $playOffline.Enabled = -not $busy; $bar.Visible = $busy
}
function Set-Status($text, $color) { $status.Text = $text; $status.ForeColor = $color }

# What the last run of the game logged: used to tell at a glance whether it was clean.
function Read-LastRun {
    if (-not (Test-Path $logFile)) { $lastRun.Text = ''; return }
    $text = Get-Content $logFile -ErrorAction SilentlyContinue
    $errors = @($text | Where-Object { $_ -match '^\s*(SCRIPT ERROR|ERROR):' }).Count
    $when = (Get-Item $logFile).LastWriteTime.ToString('HH:mm')
    if ($errors -eq 0) { $lastRun.Text = "Last run ($when): no errors logged."; $lastRun.ForeColor = $dim }
    else { $lastRun.Text = "Last run ($when): $errors errors logged. Open the log and send it."; $lastRun.ForeColor = $bad }
}

function Start-Game {
    if (-not (Test-Path $godot)) { Set-Status 'Godot is not installed yet: press Play (needs internet once).' $bad; Set-Busy $false; return }
    $mode = if ($full.Checked) { '--fullscreen' } else { '--maximized' }
    $gameArgs = @('--path', "`"$root`"", $mode, '--log-file', "`"$logFile`"", 'res://scenes/main.tscn')
    $script:game = Start-Process -FilePath $godot -ArgumentList $gameArgs -PassThru
    $script:gameStarted = Get-Date
    Set-Status 'The game is running. Streets take a few seconds to load.' $ink
    Set-Busy $true; $bar.Visible = $false
}

function Start-Update([bool]$thenPlay) {
    $script:playAfter = $thenPlay
    Set-Content -Path $statusFile -Value '' -Encoding UTF8
    $updater = Join-Path $root 'update.ps1'
    $script:job = Start-Process -FilePath 'powershell' -WindowStyle Hidden -PassThru -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$updater`"", '-StatusFile', "`"$statusFile`"")
    Set-Busy $true; Set-Status 'Checking for a new version...' $ink
}

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 300
$timer.Add_Tick({
    if ($script:job) {
        $lines = @(Get-Content $statusFile -ErrorAction SilentlyContinue | Where-Object { $_ })
        if ($lines.Count -gt 0) {
            $last = $lines[-1]
            if ($last -like 'DONE*') {
                $script:job = $null; Show-Installed; $latest.Text = 'You have the latest version.'
                if ($script:playAfter) { Start-Game } else { Set-Busy $false; Set-Status 'Up to date.' $ink }
            } elseif ($last -like 'ERROR*') {
                $script:job = $null; Set-Busy $false
                Set-Status ($last.Substring(6)) $bad
                $latest.Text = 'Update failed. "Play without update" still starts the installed version.'
            } else { Set-Status $last $ink }
        } elseif ($script:job.HasExited) {
            $script:job = $null; Set-Busy $false; Set-Status 'The updater stopped without a result.' $bad
        }
    }
    if ($script:game -and $script:game.HasExited) {
        $ran = [int]((Get-Date) - $script:gameStarted).TotalSeconds
        $script:game = $null; Set-Busy $false
        Set-Status ("The game closed after {0} min {1} s." -f [int]($ran / 60), ($ran % 60)) $ink
        Read-LastRun
    }
})

$play.Add_Click({ Start-Update $true })
$playOffline.Add_Click({ Set-Busy $true; Start-Game })
$openLog.Add_Click({ if (Test-Path $logFile) { Start-Process notepad $logFile } else { Set-Status 'No log yet: the game has not been run from here.' $dim } })
$openFolder.Add_Click({ Start-Process explorer $root })

Show-Installed
Read-LastRun
if ($SelfTest) {
    $form.Show(); [Windows.Forms.Application]::DoEvents()
    $bmp = New-Object Drawing.Bitmap($form.Width, $form.Height)
    $form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
    $bmp.Save($SelfTest, [Drawing.Imaging.ImageFormat]::Png)
    $form.Close(); exit 0
}
$timer.Start()
[Windows.Forms.Application]::Run($form)
