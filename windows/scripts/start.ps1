# 相机控制程序 (CameraController) 启动脚本
# 由 CameraController-Start.exe 以管理员身份调用：转接相机 → 启动网页服务 → 打开浏览器。
# 关闭窗口或按 Ctrl+C 即停止，并把相机交还给 Windows。

. (Join-Path $PSScriptRoot 'common.ps1')
Initialize-Console
$Host.UI.RawUI.WindowTitle = '相机控制程序 - 运行中（关闭此窗口即停止）'

Write-Host '============================================================'
Write-Host '  相机控制程序 (CameraController)'
Write-Host '============================================================'

if (-not (Test-IsAdmin)) { Write-Fail '需要管理员权限，请通过 CameraController-Start.exe 启动。'; Wait-Exit 1 }
if (-not (Test-WslExe) -or -not (Test-DistroInstalled)) { Write-Fail '尚未安装，请先运行 CameraController-Setup.exe。'; Wait-Exit 1 }
$usbipd = Get-UsbipdExe
if (-not $usbipd) { Write-Fail '未找到 usbipd-win，请重新运行 CameraController-Setup.exe。'; Wait-Exit 1 }
$r = Invoke-WslCapture @('-d', $DistroName, '-u', 'root', '-e', 'test', '-f', "$AppDirLinux/.provisioned")
if ($r.Code -ne 0) { Write-Fail '程序尚未部署完成，请重新运行 CameraController-Setup.exe。'; Wait-Exit 1 }

Stop-PreviousSession
if (Test-PortOpen $ServerPort) {
    Write-Warn "端口 $ServerPort 已被占用：程序可能已在另一个窗口中运行。直接打开浏览器。"
    Open-Browser $ServerUrl
    Wait-Exit 0
}

# ------------------------------------------------------------------ 查找相机
Write-Step '检测佳能相机'
$cams = @()
while ($true) {
    $cams = @(Get-CanonDevices | Where-Object { $_.IsConnected })
    if ($cams.Count -gt 0) {
        foreach ($c in $cams) { Write-Ok ("找到：{0}（USB {1}，ID 04a9:{2}）" -f $c.Description, $c.BusId, $c.ProductId) }
        break
    }
    Write-Warn '未检测到佳能相机。请检查：'
    Write-Info '1) USB 线已连接电脑   2) 相机电源开关已打开   3) 已关闭 EOS Utility 等占用相机的软件'
    $ans = Read-Host '准备好后按回车重新检测；输入 S 再回车则不连接相机直接启动'
    if ($ans -and ($ans.Trim().ToUpper() -eq 'S')) { break }
}

foreach ($c in $cams) {
    if (-not $c.IsShared) {
        Write-Info "首次使用这台相机：共享 USB 设备 $($c.BusId) ..."
        & $usbipd bind --busid $c.BusId
        if ($LASTEXITCODE -ne 0) { Write-Warn '共享失败，相机可能无法在程序中使用。可尝试换一个 USB 口，或重启电脑后再试。' }
    }
    if ($c.IsAttached) { & $usbipd detach --busid $c.BusId 2>$null | Out-Null }
}

function Invoke-Session {
  $keep = $null
  $attachProcs = @()
  $server = $null
  try {
    # ------------------------------------------------------------------ 启动 Linux 并转接相机
    Write-Step '启动 Linux 环境'
    $keep = Start-Process wsl.exe -ArgumentList @('-d', $DistroName, '-u', 'root', '-e', 'sleep', 'infinity') -WindowStyle Hidden -PassThru
    $running = $false
    for ($i = 0; $i -lt 60; $i++) {
        if (Test-DistroRunning) { $running = $true; break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $running) { Write-Fail 'Linux 环境启动失败。请重启电脑后再试。'; return }
    Write-Ok 'Linux 环境已启动'

    if ($cams.Count -gt 0) {
        Write-Step '把相机转接给 Linux'
        foreach ($c in $cams) {
            $log = Join-Path $LogDir ('usbipd-attach-' + ($c.BusId -replace '[^0-9A-Za-z]', '_') + '.log')
            # --auto-attach：相机重新插拔或重新开机后自动再次转接
            $p = Start-Process $usbipd -ArgumentList @('attach', '--wsl', '--busid', $c.BusId, '--auto-attach') -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError ($log + '.err') -PassThru
            $null = $p.Handle   # 缓存句柄，否则 PowerShell 5.1 取不到 ExitCode
            $attachProcs += $p
        }
        $seen = $false
        for ($i = 0; $i -lt 30; $i++) {
            $r = Invoke-WslCapture @('-d', $DistroName, '-u', 'root', '-e', 'lsusb')
            if ($r.Text -match '(?i)ID 04a9:') { $seen = $true; break }
            Start-Sleep -Seconds 1
        }
        if ($seen) {
            Write-Ok '相机已转接（此时 Windows 中的其他软件暂时无法使用相机）'
        } else {
            Write-Warn 'Linux 中暂未看到相机。程序仍会启动，相机就绪后可在网页首页点击 “Autodetect cameras”。'
            Write-Info "usbipd 日志：$LogDir"
            foreach ($p in $attachProcs) { if ($p.HasExited) { Write-Warn ('usbipd 已退出，代码 ' + $p.ExitCode) } }
            Get-ChildItem -Path $LogDir -Filter 'usbipd-attach-*' -ErrorAction SilentlyContinue | ForEach-Object { Get-Content $_.FullName -ErrorAction SilentlyContinue | Select-Object -Last 5 | ForEach-Object { Write-Info $_ } }
        }
    }

    $ids = @($keep.Id) + @($attachProcs | ForEach-Object { $_.Id })
    Save-Session $ids

    # ------------------------------------------------------------------ 启动网页服务
    Write-Step '启动网页服务'
    $tz = Get-LinuxTzHint
    $server = Start-Process wsl.exe -ArgumentList @('-d', $DistroName, '-u', 'root', '-e', 'bash', "$AppDirLinux/windows/linux/start-server.sh", $tz) -NoNewWindow -PassThru
    $null = $server.Handle
    $up = $false
    for ($i = 0; $i -lt 120; $i++) {
        if ($server.HasExited) { break }
        if (Test-PortOpen $ServerPort) { $up = $true; break }
        Start-Sleep -Seconds 1
    }
    if ($up) {
        Write-Host ''
        Write-Host '============================================================' -ForegroundColor Green
        Write-Host "  已启动：$ServerUrl" -ForegroundColor Green
        Write-Host '  登录账号：Admin   密码：admin' -ForegroundColor Green
        Write-Host "  延时摄影照片：$PhotoDir" -ForegroundColor Green
        Write-Host '  停止：关闭本窗口，或按 Ctrl+C' -ForegroundColor Green
        Write-Host '============================================================' -ForegroundColor Green
        Write-Host ''
        Open-Browser $ServerUrl
    } elseif ($server.HasExited) {
        Write-Fail '网页服务启动失败，请查看上面的输出。'
    } else {
        Write-Warn "等待超时，请稍后手动打开 $ServerUrl"
    }
    $server.WaitForExit()
  }
  finally {
    Write-Host ''
    Write-Host '正在停止，并把相机交还给 Windows ...'
    if ($server -and -not $server.HasExited) { try { $server.Kill() } catch {} }
    foreach ($p in $attachProcs) { try { if (-not $p.HasExited) { $p.Kill() } } catch {} }
    foreach ($c in $cams) { & $usbipd detach --busid $c.BusId 2>$null | Out-Null }
    if ($keep) { try { if (-not $keep.HasExited) { $keep.Kill() } } catch {} }
    & wsl.exe --terminate $DistroName 2>$null | Out-Null
    Remove-Item -Force $SessionFile -ErrorAction SilentlyContinue
  }
}

Invoke-Session
Write-Host '已停止。'
Wait-Exit 0
