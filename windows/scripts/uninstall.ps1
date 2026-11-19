# 相机控制程序 (CameraController) 卸载脚本（由 CameraController-Uninstall.exe 以管理员身份调用）

. (Join-Path $PSScriptRoot 'common.ps1')
Initialize-Console
$Host.UI.RawUI.WindowTitle = '相机控制程序 - 卸载'

Write-Host '============================================================'
Write-Host '  相机控制程序 (CameraController) - 卸载'
Write-Host "  将删除：专用 Linux 环境 $DistroName（含程序设置、定时任务）、下载缓存、桌面快捷方式"
Write-Host "  默认保留：照片目录 $PhotoDir、WSL 本身"
Write-Host '============================================================'
if (-not (Test-IsAdmin)) { Write-Fail '需要管理员权限。'; Wait-Exit 1 }
if (-not (Read-YesNo '确定要卸载吗？' $false)) { exit 0 }

Stop-PreviousSession

$usbipd = Get-UsbipdExe
if ($usbipd) {
    Write-Step '把相机交还给 Windows'
    foreach ($c in Get-CanonDevices) {
        if ($c.IsAttached -and $c.BusId) { & $usbipd detach --busid $c.BusId }
        if ($c.PersistedGuid) { & $usbipd unbind --guid $c.PersistedGuid }
    }
    Write-Ok '完成'
}

Write-Step "删除 Linux 环境 $DistroName"
if ((Test-WslExe) -and (Test-DistroInstalled)) {
    & wsl.exe --terminate $DistroName | Out-Null
    & wsl.exe --unregister $DistroName
}
Remove-Item -Recurse -Force $DistroDir, $DownloadDir, $ConfigFile -ErrorAction SilentlyContinue
Write-Ok '完成'

Write-Step '删除快捷方式与计划任务'
$desktop = [Environment]::GetFolderPath('Desktop')
Remove-Item -Force (Join-Path $desktop '相机控制.lnk'), (Join-Path $desktop '相机照片.lnk') -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $ResumeTaskName -Confirm:$false -ErrorAction SilentlyContinue
Write-Ok '完成'

if (Read-YesNo "是否同时删除照片目录 $PhotoDir ？（不可恢复）" $false) {
    Remove-Item -Recurse -Force $PhotoDir -ErrorAction SilentlyContinue
    Write-Ok '照片目录已删除'
}

if ($usbipd -and (Read-YesNo '是否卸载 usbipd-win？（若其他软件也在使用请选 N）' $false)) {
    $keys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
    $entry = Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'usbipd-win*' } | Select-Object -First 1
    if ($entry) {
        $p = Start-Process msiexec.exe -ArgumentList @('/x', $entry.PSChildName, '/qn', '/norestart') -Wait -PassThru
        if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) { Write-Ok 'usbipd-win 已卸载' } else { Write-Warn ('卸载 usbipd-win 失败，代码 ' + $p.ExitCode) }
    }
}

Write-Info 'WSL 是 Windows 组件，未卸载；如需移除可在“启用或关闭 Windows 功能”中关闭。'
Write-Host ''
Write-Host '卸载完成。' -ForegroundColor Green
Wait-Exit 0
