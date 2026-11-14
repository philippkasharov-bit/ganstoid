# Tagged launcher: one window, one button.
#   PLAY           updates if there is a newer version, then starts the game
#                  (offline or GitHub down: starts what is installed)
#   Full screen    remembered between runs
#   Log / Folder / New game / Benchmark   the small links under the button
# First run puts a "Tagged" shortcut on the desktop.
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
$prefsFile = Join-Path $root 'launcher_prefs.txt'
$userDirs = @((Join-Path $env:APPDATA 'Ganstoid'), (Join-Path $env:APPDATA 'Godot\app_userdata\Ganstoid'))   # user:// (custom dir, then the default)
$script:job = $null; $script:game = $null; $script:gameStarted = $null; $script:afterUpdate = 'play'

# --- look -------------------------------------------------------------------------------
$ink = [Drawing.Color]::FromArgb(240, 238, 232)
$dim = [Drawing.Color]::FromArgb(168, 164, 156)
$tag = [Drawing.Color]::FromArgb(245, 196, 40)       # spray-paint yellow
$tagDark = [Drawing.Color]::FromArgb(206, 160, 20)
$bad = [Drawing.Color]::FromArgb(240, 104, 92)
$night = [Drawing.Color]::FromArgb(14, 14, 18)
$fonts = New-Object Drawing.Text.PrivateFontCollection
foreach ($f in 'PermanentMarker-Regular', 'Bungee-Regular', 'SpecialElite-Regular') {
    $p = Join-Path $root "fonts\$f.ttf"
    if (Test-Path $p) { $fonts.AddFontFile($p) }
}
function Font-Of([string]$family, [float]$size) {
    $fam = $fonts.Families | Where-Object { $_.Name -eq $family } | Select-Object -First 1
    if ($fam) { New-Object Drawing.Font($fam, $size) } else { New-Object Drawing.Font('Segoe UI', $size, [Drawing.FontStyle]::Bold) }
}

$W = 960; $H = 560
$form = New-Object Windows.Forms.Form
$form.Text = 'Tagged'; $form.ClientSize = New-Object Drawing.Size($W, $H)
$form.StartPosition = 'CenterScreen'; $form.FormBorderStyle = 'FixedSingle'; $form.MaximizeBox = $false
$form.BackColor = $night
$icon = Join-Path $root 'art\launcher\icon.ico'
if (Test-Path $icon) { $form.Icon = New-Object Drawing.Icon($icon) }

# The background: a shot of the city, darkened towards the left where the text sits.
$back = New-Object Drawing.Bitmap($W, $H)
$g = [Drawing.Graphics]::FromImage($back)
$g.Clear($night)
$hero = Join-Path $root 'art\launcher\hero.jpg'
if (Test-Path $hero) {
    $img = [Drawing.Image]::FromFile($hero)
    $scale = [Math]::Max($W / $img.Width, $H / $img.Height)
    $g.DrawImage($img, [int](($W - $img.Width * $scale) / 2), [int](($H - $img.Height * $scale) / 2), [int]($img.Width * $scale), [int]($img.Height * $scale))
    $img.Dispose()
}
$fade = New-Object Drawing.Drawing2D.LinearGradientBrush((New-Object Drawing.Point(0, 0)), (New-Object Drawing.Point($W, 0)), [Drawing.Color]::FromArgb(245, 12, 12, 16), [Drawing.Color]::FromArgb(40, 12, 12, 16))
$g.FillRectangle($fade, 0, 0, $W, $H)
$foot = New-Object Drawing.Drawing2D.LinearGradientBrush((New-Object Drawing.Point(0, ($H - 120))), (New-Object Drawing.Point(0, $H)), [Drawing.Color]::FromArgb(0, 12, 12, 16), [Drawing.Color]::FromArgb(235, 12, 12, 16))
$g.FillRectangle($foot, 0, ($H - 120), $W, 120)
$g.Dispose()
$canvas = New-Object Windows.Forms.PictureBox
$canvas.Dock = 'Fill'; $canvas.Image = $back
$form.Controls.Add($canvas)

function Add-Text($text, $x, $y, $w, $h, $font, $color) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text; $l.Left = $x; $l.Top = $y; $l.Width = $w; $l.Height = $h
    $l.Font = $font; $l.ForeColor = $color; $l.BackColor = [Drawing.Color]::Transparent
    $l.UseCompatibleTextRendering = $true   # private (bundled) fonts draw only this way
    $canvas.Controls.Add($l); $l
}
function Add-Link($text, $x, $y) {
    $l = Add-Text $text $x $y 120 24 (New-Object Drawing.Font('Segoe UI', 10)) $dim
    $l.AutoSize = $true; $l.Cursor = 'Hand'
    $l.Add_MouseEnter({ $this.ForeColor = $tag }); $l.Add_MouseLeave({ $this.ForeColor = $dim })
    $l
}

$null = Add-Text 'TAGGED' 52 58 520 96 (Font-Of 'Permanent Marker' 60) $tag
$null = Add-Text 'Los Angeles, 1994.  Start with nothing.' 58 150 520 28 (Font-Of 'Special Elite' 14) $ink

$play = New-Object Windows.Forms.Button
$play.Text = 'PLAY'; $play.Left = 58; $play.Top = 214; $play.Width = 300; $play.Height = 72
$play.FlatStyle = 'Flat'; $play.FlatAppearance.BorderSize = 0
$play.BackColor = $tag; $play.ForeColor = $night; $play.Cursor = 'Hand'
$play.FlatAppearance.MouseOverBackColor = [Drawing.Color]::FromArgb(255, 214, 80)
$play.FlatAppearance.MouseDownBackColor = $tagDark
$play.Font = Font-Of 'Bungee' 26
$play.UseCompatibleTextRendering = $true
$canvas.Controls.Add($play)

$full = New-Object Windows.Forms.CheckBox
$full.Text = 'Full screen'; $full.Left = 60; $full.Top = 298; $full.Width = 200; $full.Height = 24
$full.ForeColor = $ink; $full.BackColor = [Drawing.Color]::Transparent; $full.Font = New-Object Drawing.Font('Segoe UI', 10)
$full.Cursor = 'Hand'
$canvas.Controls.Add($full)

$linkLog = Add-Link 'Last log' 60 344
$linkFolder = Add-Link 'Game folder' 140 344
$linkNew = Add-Link 'New game' 246 344
$linkBench = Add-Link 'Benchmark' 334 344

$status = Add-Text 'Ready.' 58 ($H - 74) 560 24 (New-Object Drawing.Font('Segoe UI', 10.5)) $ink
$detail = Add-Text '' 58 ($H - 48) 560 22 (New-Object Drawing.Font('Segoe UI', 9)) $dim
$version = Add-Text '' ($W - 330) ($H - 48) 300 22 (New-Object Drawing.Font('Segoe UI', 9)) $dim
$version.TextAlign = 'TopRight'
$bar = New-Object Windows.Forms.ProgressBar
$bar.Left = 58; $bar.Top = ($H - 84); $bar.Width = 300; $bar.Height = 4; $bar.Style = 'Marquee'; $bar.Visible = $false
$canvas.Controls.Add($bar)

# --- what it does -----------------------------------------------------------------------
function Set-Status($text, $color) { $status.Text = $text; $status.ForeColor = $color }
function Set-Busy([bool]$busy, [string]$label) {
    $play.Enabled = -not $busy; $bar.Visible = $busy
    $play.Text = if ($busy) { $label } else { 'PLAY' }
    $play.BackColor = if ($busy) { [Drawing.Color]::FromArgb(90, 86, 70) } else { $tag }
}
function Show-Version {
    $v = if (Test-Path $versionFile) { (Get-Content $versionFile -TotalCount 1).Split(' ')[0] } else { 'not installed' }
    $version.Text = "version $v"
}
function Save-File {
    foreach ($d in $userDirs) { $p = Join-Path $d 'ganstoid_save.txt'; if (Test-Path $p) { return $p } }
    return $null
}
function Show-LastRun {
    $parts = @()
    if (Save-File) { $parts += 'Saved game: PLAY carries on.' } else { $parts += 'No save: PLAY starts a new life.' }
    if (Test-Path $logFile) {
        $errors = @(Get-Content $logFile -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*(SCRIPT ERROR|ERROR):' }).Count
        if ($errors -gt 0) { $parts += "Last run logged $errors errors: open Last log and send it."; $detail.ForeColor = $bad }
        else { $detail.ForeColor = $dim }
    }
    $detail.Text = $parts -join '   '
}

function Start-Godot([string[]]$extra) {
    if (-not (Test-Path $godot)) { Set-Status 'Godot is not installed yet: press PLAY with internet on (one time).' $bad; Set-Busy $false ''; return $null }
    Start-Process -FilePath $godot -PassThru -ArgumentList (@('--path', "`"$root`"", '--log-file', "`"$logFile`"") + $extra)
}
function Start-Game {
    $mode = if ($full.Checked) { '--fullscreen' } else { '--maximized' }
    $script:game = Start-Godot @($mode, 'res://scenes/main.tscn')
    if ($script:game) {
        $script:gameStarted = Get-Date
        Set-Busy $true 'RUNNING'; $bar.Visible = $false
        Set-Status 'The game is running. The streets take a few seconds to load.' $ink
    }
}
function Start-Bench {
    $script:game = Start-Godot @('-s', 'debug/bench_3d.gd')
    if ($script:game) {
        $script:gameStarted = Get-Date; $script:afterUpdate = 'bench'
        Set-Busy $true 'TESTING'
        Set-Status 'Benchmark: about a minute. Leave the window alone; the results open by themselves.' $ink
    }
}
function Start-Update {
    Set-Content -Path $statusFile -Value '' -Encoding UTF8
    $script:job = Start-Process -FilePath 'powershell' -WindowStyle Hidden -PassThru -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $root 'update.ps1')`"", '-StatusFile', "`"$statusFile`"")
    Set-Busy $true 'UPDATING'; Set-Status 'Checking for a new version...' $ink
}
function Game-Closed {
    $ran = [int]((Get-Date) - $script:gameStarted).TotalSeconds
    $script:game = $null; Set-Busy $false ''
    if ($script:afterUpdate -eq 'bench') {
        $script:afterUpdate = 'play'
        $out = $userDirs | ForEach-Object { Join-Path $_ 'bench_3d.txt' } | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($out) { Start-Process notepad $out; Set-Status 'Benchmark done: the results are open in Notepad. Paste them to Claude.' $ink }
        else { Set-Status 'The benchmark did not finish. Open Last log.' $bad }
    } else { Set-Status ("The game closed after {0} min {1} s." -f [int]($ran / 60), ($ran % 60)) $ink }
    Show-LastRun
}

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 250
$timer.Add_Tick({
    if ($script:job) {
        $lines = @(Get-Content $statusFile -ErrorAction SilentlyContinue | Where-Object { $_ })
        $last = if ($lines.Count -gt 0) { $lines[-1] } else { '' }
        if ($last -like 'DONE*') { $script:job = $null; Show-Version; Start-Game }
        elseif ($last -like 'ERROR*') {
            $script:job = $null
            if (Test-Path $godot) { Start-Game; Set-Status ('Could not update (' + $last.Substring(6) + '). Started the installed version.') $bad }
            else { Set-Busy $false ''; Set-Status $last.Substring(6) $bad }
        }
        elseif ($last) { Set-Status $last $ink }
        elseif ($script:job.HasExited) { $script:job = $null; Start-Game }
    }
    if ($script:game -and $script:game.HasExited) { Game-Closed }
})

$play.Add_Click({ Start-Update })
$full.Add_CheckedChanged({ Set-Content -Path $prefsFile -Value ("fullscreen=" + $full.Checked) -Encoding UTF8 })
$linkLog.Add_Click({ if (Test-Path $logFile) { Start-Process notepad $logFile } else { Set-Status 'No log yet: the game has not been run from here.' $dim } })
$linkFolder.Add_Click({ Start-Process explorer $root })
$linkBench.Add_Click({ if (-not $script:game -and -not $script:job) { Start-Bench } })
$linkNew.Add_Click({
    $save = Save-File
    if (-not $save) { Set-Status 'No saved game: PLAY starts a new one.' $dim; return }
    $answer = [Windows.Forms.MessageBox]::Show('Delete your saved game and start a new life next time you press PLAY?', 'New game', 'YesNo', 'Warning')
    if ($answer -eq 'Yes') { Remove-Item $save -Force; Set-Status 'Saved game deleted. PLAY starts a new one.' $ink; Show-LastRun }
})
$form.Add_KeyDown({ if ($_.KeyCode -eq 'Enter' -and $play.Enabled) { Start-Update } })
$form.KeyPreview = $true
$form.AcceptButton = $play

# A desktop shortcut, once, so the game starts like any other.
function Add-Shortcut {
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Tagged.lnk'
    if (Test-Path $lnk) { return }
    $ws = New-Object -ComObject WScript.Shell
    $s = $ws.CreateShortcut($lnk)
    $s.TargetPath = 'powershell.exe'
    $s.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $root 'launcher.ps1')`""
    $s.WorkingDirectory = $root
    $s.WindowStyle = 7
    if (Test-Path $icon) { $s.IconLocation = $icon }
    $s.Save()
}

if ((Test-Path $prefsFile) -and ((Get-Content $prefsFile -TotalCount 1) -eq 'fullscreen=True')) { $full.Checked = $true }
Show-Version
Show-LastRun
if ($SelfTest) {
    $form.Show(); [Windows.Forms.Application]::DoEvents()
    $bmp = New-Object Drawing.Bitmap($form.ClientSize.Width, $form.ClientSize.Height)
    $form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $form.ClientSize.Width, $form.ClientSize.Height)))
    $bmp.Save($SelfTest, [Drawing.Imaging.ImageFormat]::Png)
    $form.Close(); exit 0
}
try { Add-Shortcut } catch { }
$timer.Start()
[Windows.Forms.Application]::Run($form)
