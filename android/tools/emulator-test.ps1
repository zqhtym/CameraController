# 在 Android 模拟器上自动测试 CameraController-PoC.apk（无需相机）
# 用法：powershell -ExecutionPolicy Bypass -File android\tools\emulator-test.ps1 [-Show] [-KeepRunning]
#   -Show         显示模拟器窗口（默认无窗口运行）
#   -KeepRunning  测试结束后不关闭模拟器
# 结果：android\emulator-test-results\（截图、界面文本、logcat、report.txt）
param([switch]$Show, [switch]$KeepRunning, [string]$Avd = 'cc_api35')

$ErrorActionPreference = 'Continue'
$sdk = 'C:\AndroidDev\sdk'
$adb = Join-Path $sdk 'platform-tools\adb.exe'
$emu = Join-Path $sdk 'emulator\emulator.exe'
$apk = Join-Path (Split-Path -Parent $PSScriptRoot) 'CameraController-PoC.apk'
$out = Join-Path (Split-Path -Parent $PSScriptRoot) 'emulator-test-results'
$pkg = 'org.cameracontroller.poc'
New-Item -ItemType Directory -Force -Path $out | Out-Null
Get-ChildItem $out -File -ErrorAction SilentlyContinue | Remove-Item -Force

$results = New-Object System.Collections.Generic.List[string]
function Add-Result([string]$name, [bool]$ok, [string]$detail) {
    $line = ('[{0}] {1}  {2}' -f ($(if ($ok) { 'PASS' } else { 'FAIL' })), $name, $detail)
    $results.Add($line)
    Write-Host $line -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
}
function Invoke-Adb([string[]]$a) { $o = & $adb @a 2>&1 | ForEach-Object { "$_" }; return ($o -join "`n") }
function Save-Screenshot([string]$name) {
    Invoke-Adb @('shell', 'screencap', '-p', '/sdcard/cc.png') | Out-Null
    Invoke-Adb @('pull', '/sdcard/cc.png', (Join-Path $out "$name.png")) | Out-Null
}
function Get-UiText([string]$name) {
    Invoke-Adb @('shell', 'uiautomator', 'dump', '/sdcard/cc-ui.xml') | Out-Null
    $xml = Join-Path $out "$name-ui.xml"
    Invoke-Adb @('pull', '/sdcard/cc-ui.xml', $xml) | Out-Null
    if (-not (Test-Path $xml)) { return '' }
    $raw = Get-Content -Raw -Encoding UTF8 $xml
    $texts = [regex]::Matches($raw, 'text="([^"]*)"') | ForEach-Object { [System.Net.WebUtility]::HtmlDecode($_.Groups[1].Value) } | Where-Object { $_ }
    $joined = ($texts -join "`n")
    Set-Content -Path (Join-Path $out "$name-ui.txt") -Value $joined -Encoding UTF8
    return $joined
}
function Invoke-TapText([string]$name, [string]$text) {
    $xml = Join-Path $out "$name-ui.xml"
    $raw = Get-Content -Raw -Encoding UTF8 $xml
    $m = [regex]::Match($raw, 'text="' + [regex]::Escape($text) + '"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
    if (-not $m.Success) { return $false }
    $x = ([int]$m.Groups[1].Value + [int]$m.Groups[3].Value) / 2
    $y = ([int]$m.Groups[2].Value + [int]$m.Groups[4].Value) / 2
    Invoke-Adb @('shell', 'input', 'tap', [string][int]$x, [string][int]$y) | Out-Null
    return $true
}
function Test-AppAlive { return [bool]((Invoke-Adb @('shell', 'pidof', $pkg)).Trim()) }

# ------------------------------------------------------------------ 0/1. 已连接设备（真机或模拟器）则直接用，否则启动模拟器
$devices = Invoke-Adb @('devices')
if ($devices -notmatch "`tdevice") {
    Write-Host '==> 未连接设备，检查模拟器硬件加速'
    $accel = (& $emu -accel-check 2>&1 | ForEach-Object { "$_" }) -join ' '
    if ($accel -notmatch 'usable') {
        Write-Host "模拟器无法使用硬件加速：$accel" -ForegroundColor Red
        Write-Host '请以管理员身份运行：C:\AndroidDev\sdk\extras\google\Android_Emulator_Hypervisor_Driver\silent_install.bat'
        Write-Host '或者用 USB / 无线调试连接一台安卓手机后再运行本脚本。'
        exit 2
    }
    Write-Host "    $accel"
    Write-Host "==> 启动模拟器 $Avd"
    $emuArgs = @('-avd', $Avd, '-no-snapshot', '-no-audio', '-no-boot-anim', '-gpu', 'swiftshader_indirect')
    if (-not $Show) { $emuArgs += '-no-window' }
    Start-Process -FilePath $emu -ArgumentList $emuArgs -WindowStyle Minimized | Out-Null
}
Invoke-Adb @('wait-for-device') | Out-Null
$booted = $false
for ($i = 0; $i -lt 150; $i++) {
    if ((Invoke-Adb @('shell', 'getprop', 'sys.boot_completed')).Trim() -eq '1') { $booted = $true; break }
    Start-Sleep -Seconds 2
}
Add-Result '模拟器启动' $booted ((Invoke-Adb @('shell', 'getprop', 'ro.build.version.release')).Trim() + ' / ' + (Invoke-Adb @('shell', 'getprop', 'ro.product.cpu.abi')).Trim())
if (-not $booted) { exit 1 }
Invoke-Adb @('shell', 'input', 'keyevent', '82') | Out-Null   # 解锁屏幕
Invoke-Adb @('shell', 'settings', 'put', 'global', 'window_animation_scale', '0') | Out-Null

# ------------------------------------------------------------------ 2. 安装
$inst = Invoke-Adb @('install', '-r', '-g', $apk)
Add-Result '安装 APK' ($inst -match 'Success') ($inst -split "`n" | Select-Object -Last 1)

# ------------------------------------------------------------------ 3. 启动 + 驱动自检
Invoke-Adb @('logcat', '-c') | Out-Null
Invoke-Adb @('logcat', '-b', 'crash', '-c') | Out-Null
Invoke-Adb @('shell', 'am', 'start', '-W', '-n', "$pkg/.MainActivity") | Out-Null
Start-Sleep -Seconds 6
Save-Screenshot '01-launch'
$ui = Get-UiText '01-launch'
Add-Result '应用启动且未崩溃' (Test-AppAlive) ''
Add-Result '原生库加载（显示 libgphoto2 版本）' ($ui -match 'libgphoto2 2\.5\.34') (($ui -split "`n" | Where-Object { $_ -match 'libgphoto2 2' }) -join ' ')
$selfLine = ($ui -split "`n" | Where-Object { $_ -match 'driver self-test|5D Mark II' }) -join ' / '
Add-Result '驱动自检：相机型号表 + 5D Mark II' ($ui -match 'Canon EOS 5D Mark II: driver ptp2, USB 04a9:3199') $selfLine

# ------------------------------------------------------------------ 4. 无相机时点“连接相机”
if (Invoke-TapText '01-launch' '连接相机') {
    Start-Sleep -Seconds 2
    Save-Screenshot '02-connect-no-camera'
    $ui2 = Get-UiText '02-connect-no-camera'
    Add-Result '无相机时点“连接相机”给出提示' (($ui2 -match '没有检测到任何 USB 设备') -and (Test-AppAlive)) (($ui2 -split "`n" | Where-Object { $_ -match 'USB' }) -join ' ' )
} else {
    Add-Result '无相机时点“连接相机”给出提示' $false '界面上找不到“连接相机”按钮'
}

# ------------------------------------------------------------------ 5. 错误路径自检（伪造的 USB 句柄 / 切换句柄 / fd -1）
Invoke-Adb @('shell', 'am', 'start', '-n', "$pkg/.MainActivity", '--es', 'cc_selftest', 'errorpaths') | Out-Null
$report = ''
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 2
    $report = Invoke-Adb @('logcat', '-d', '-s', 'CCSelfTest:I')
    if ($report -match 'ERRORPATH_SELFTEST_(PASS|FAIL)') { break }
}
Save-Screenshot '03-errorpaths'
Get-UiText '03-errorpaths' | Out-Null
Set-Content -Path (Join-Path $out 'errorpaths.txt') -Value $report -Encoding UTF8
Add-Result '错误路径：无效句柄不崩溃、换句柄可重试' (($report -match 'ERRORPATH_SELFTEST_PASS') -and (Test-AppAlive)) (($report -split "`n" | Where-Object { $_ -match 'result' }) -join ' || ')

# ------------------------------------------------------------------ 6. 崩溃日志
$crash = Invoke-Adb @('logcat', '-d', '-b', 'crash')
Set-Content -Path (Join-Path $out 'logcat-crash.txt') -Value $crash -Encoding UTF8
Invoke-Adb @('logcat', '-d') | Set-Content -Path (Join-Path $out 'logcat-all.txt') -Encoding UTF8
$hasCrash = ($crash -match $pkg) -or ($crash -match 'Fatal signal')
Add-Result '全程无崩溃（crash 日志）' (-not $hasCrash) $(if ($hasCrash) { '见 logcat-crash.txt' } else { '' })

# ------------------------------------------------------------------ 汇总
$pass = ($results | Where-Object { $_ -like '`[PASS`]*' }).Count
$summary = "通过 $pass / $($results.Count)"
$results.Add($summary)
Set-Content -Path (Join-Path $out 'report.txt') -Value $results -Encoding UTF8
Write-Host ''
Write-Host $summary -ForegroundColor Cyan
Write-Host "结果目录：$out"
if (-not $KeepRunning) { Invoke-Adb @('emu', 'kill') | Out-Null }
if ($pass -eq $results.Count - 1) { exit 0 } else { exit 1 }
