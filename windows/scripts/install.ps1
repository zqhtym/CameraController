# 相机控制程序 (CameraController) Windows 安装程序
# 由 CameraController-Setup.exe 以管理员身份调用；可重复运行（已完成的步骤会自动跳过）。

. (Join-Path $PSScriptRoot 'common.ps1')
Initialize-Console
try { Start-Transcript -Path (Join-Path $LogDir ('install-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')) | Out-Null } catch {}
$Host.UI.RawUI.WindowTitle = '相机控制程序 - 安装'

Write-Host '============================================================'
Write-Host '  相机控制程序 (CameraController) - Windows 安装程序'
Write-Host '  控制佳能 EOS 5D Mark II 等相机：实时预览 / 拍摄 / 参数 / 延时摄影'
Write-Host '============================================================'

# 若是重启后自动继续，删除自动继续任务
Unregister-ScheduledTask -TaskName $ResumeTaskName -Confirm:$false -ErrorAction SilentlyContinue

function Register-ResumeTask {
    $exe = Join-Path $WinDir 'CameraController-Setup.exe'
    if (Test-Path $exe) {
        $action = New-ScheduledTaskAction -Execute $exe -WorkingDirectory $WinDir
    } else {
        $ps = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $action = New-ScheduledTaskAction -Execute $ps -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"')
    }
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
    Register-ScheduledTask -TaskName $ResumeTaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
}

# ------------------------------------------------------------------ 检查
Write-Step '检查系统'
if (-not (Test-IsAdmin)) { Write-Fail '需要管理员权限：请右键 CameraController-Setup.exe，选择“以管理员身份运行”。'; Wait-Exit 1 }
if (-not (Test-Path (Join-Path $ProjectDir 'requirements.txt')) -or -not (Test-Path (Join-Path $ProjectDir 'src'))) {
    Write-Fail "找不到程序文件。请保持 windows 文件夹位于 CameraController 项目目录中（当前：$ProjectDir）。"; Wait-Exit 1
}
if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { Write-Fail '仅支持 64 位 x64 Windows。'; Wait-Exit 1 }
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$build = [int]$cv.CurrentBuildNumber
Write-Info ("系统：{0} {1}（内部版本 {2}.{3}）" -f $cv.ProductName, $cv.DisplayVersion, $cv.CurrentBuildNumber, $cv.UBR)
if ($build -lt 19041) { Write-Fail '需要 Windows 10 版本 2004（内部版本 19041）或更高，请先通过 Windows 更新升级系统。'; Wait-Exit 1 }
try { $ProjectLinux = ConvertTo-WslPath $ProjectDir } catch { Write-Fail $_.Exception.Message; Wait-Exit 1 }

$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$cs = Get-CimInstance Win32_ComputerSystem
if ($cs.HypervisorPresent -or $cpu.VirtualizationFirmwareEnabled) { Write-Ok 'CPU 虚拟化可用' }
else { Write-Warn 'BIOS/UEFI 中的 CPU 虚拟化（Intel VT-x / AMD-V/SVM）似乎未开启。若第 4 步失败，请进入 BIOS 开启后重新运行本程序。' }

$cfg = $null
if (Test-Path $ConfigFile) { try { $cfg = Get-Content -Raw -Path $ConfigFile | ConvertFrom-Json } catch {} }
if (-not $cfg) {
    $defaultCn = ((Get-Culture).Name -like 'zh*') -or ((Get-UICulture).Name -like 'zh*')
    $useCn = Read-YesNo '是否使用国内镜像（清华 TUNA）加速下载 Ubuntu 与 Python 软件包？' $defaultCn
    $cfg = [pscustomobject]@{ UseCnMirror = $useCn }
    $cfg | ConvertTo-Json | Set-Content -Path $ConfigFile -Encoding UTF8
}
$UseCn = [bool]$cfg.UseCnMirror

# ------------------------------------------------------------------ 1. Windows 功能
Write-Step '第 1/6 步：启用 Windows 功能（适用于 Linux 的 Windows 子系统、虚拟机平台）'
$needReboot = $false
foreach ($f in @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')) {
    $feat = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue
    $state = ''
    if ($feat) { $state = [string]$feat.State }
    if ($state -eq 'Enabled') { Write-Ok "$f 已启用"; continue }
    if ($state -eq 'EnablePending') { Write-Info "$f 已启用，等待重启生效"; $needReboot = $true; continue }
    Write-Info "正在启用 $f ..."
    try {
        $r = Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart -ErrorAction Stop
        if ($r.RestartNeeded) { $needReboot = $true }
        Write-Ok "$f 已启用"
    } catch { Write-Fail ("启用 $f 失败：" + $_.Exception.Message); Wait-Exit 1 }
}
if ($needReboot) {
    Register-ResumeTask
    Write-Warn '需要重启电脑才能继续。重启并登录同一账户后，安装程序会自动继续。'
    if (Read-YesNo '现在重启吗？' $true) {
        try { Stop-Transcript | Out-Null } catch {}
        Restart-Computer -Force
        exit 0
    }
    Write-Info '请稍后手动重启电脑。'
    Wait-Exit 0
}

# ------------------------------------------------------------------ 2. WSL
Write-Step '第 2/6 步：安装 WSL（适用于 Linux 的 Windows 子系统）'
if (Test-WslModern) {
    Write-Ok 'WSL 已安装'
} else {
    Write-Info '正在通过 wsl --update 安装/更新 WSL ...'
    & wsl.exe --update --web-download
    if (-not (Test-WslModern)) { & wsl.exe --update }
    if (-not (Test-WslModern)) {
        Write-Info '改为从 GitHub 下载 WSL 安装包 ...'
        $msi = Find-LocalFile 'wsl.*.x64.msi'
        if (-not $msi) {
            $url = Get-GitHubAssetUrl 'microsoft/WSL' '^wsl\.[\d\.]+\.x64\.msi$'
            if ($url) {
                $msi = Join-Path $DownloadDir (Split-Path $url -Leaf)
                if (-not (Save-Download $url $msi)) { $msi = $null }
            }
        }
        if ($msi) { Install-Msi $msi | Out-Null }
    }
    if (-not (Test-WslModern)) {
        Write-Fail '无法安装 WSL。请先在“设置 → 更新和安全 → Windows 更新”中安装所有更新后重试；'
        Write-Info '也可以手动下载 https://github.com/microsoft/WSL/releases 中的 wsl.*.x64.msi 放到 windows\offline\ 文件夹。'
        Wait-Exit 1
    }
    Write-Ok 'WSL 安装完成'
}
& wsl.exe --set-default-version 2 | Out-Null

# ------------------------------------------------------------------ 3. usbipd-win
Write-Step '第 3/6 步：安装 usbipd-win（把 USB 相机转接给 Linux）'
if (Get-UsbipdExe) {
    Write-Ok 'usbipd-win 已安装'
} else {
    $msi = Find-LocalFile 'usbipd-win_*x64.msi'
    if (-not $msi) {
        $url = Get-GitHubAssetUrl 'dorssel/usbipd-win' '^usbipd-win_[\d\.]+_x64\.msi$'
        if (-not $url) { $url = 'https://github.com/dorssel/usbipd-win/releases/download/v5.3.0/usbipd-win_5.3.0_x64.msi' }
        $msi = Join-Path $DownloadDir (Split-Path $url -Leaf)
        if (-not (Save-Download $url $msi)) {
            Write-Fail '下载 usbipd-win 失败。可手动下载 https://github.com/dorssel/usbipd-win/releases 中的 x64 .msi 放到 windows\offline\ 文件夹后重试。'
            Wait-Exit 1
        }
    }
    if (-not (Install-Msi $msi) -or -not (Get-UsbipdExe)) { Wait-Exit 1 }
    Write-Ok 'usbipd-win 安装完成'
}

# ------------------------------------------------------------------ 4. Ubuntu 22.04
Write-Step "第 4/6 步：创建专用 Linux 环境（Ubuntu 22.04，名称 $DistroName）"

function Get-UbuntuRootfs {
    $offline = Join-Path $OfflineDir $RootfsName
    if (Test-Path $offline) { Write-Info "使用离线镜像：$offline"; return $offline }

    $cached = Join-Path $DownloadDir $RootfsName
    $sidecar = $cached + '.sha256'
    if ((Test-Path $cached) -and (Test-Path $sidecar)) {
        $want = (Get-Content -Raw $sidecar).Trim()
        if ((Get-FileHash -Algorithm SHA256 $cached).Hash -eq $want) { Write-Info '使用已下载的镜像'; return $cached }
    }

    $tuna = 'https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cloud-images/wsl/jammy/current'
    $official = 'https://cloud-images.ubuntu.com/wsl/jammy/current'
    $bases = @($official, $tuna)
    if ($UseCn) { $bases = @($tuna, $official) }
    foreach ($b in $bases) {
        $sums = Get-TextFromUrl "$b/SHA256SUMS"
        $want = $null
        if ($sums -and ($sums -match ('(?m)^([0-9a-fA-F]{64})\s+\*?' + [regex]::Escape($RootfsName) + '\s*$'))) { $want = $Matches[1].ToUpper() }
        if (-not $want) { Write-Warn "无法从 $b 获取校验值，换下一个源"; continue }
        if (-not (Save-Download "$b/$RootfsName" $cached)) { continue }
        Write-Info '校验文件 ...'
        if ((Get-FileHash -Algorithm SHA256 $cached).Hash -eq $want) {
            Set-Content -Path $sidecar -Value $want -Encoding ASCII
            return $cached
        }
        Write-Warn '校验失败，文件可能不完整，换下一个源重新下载'
        Remove-Item -Force $cached -ErrorAction SilentlyContinue
    }
    return $null
}

if (Test-DistroInstalled) {
    Write-Ok "$DistroName 已存在"
} else {
    $rootfs = Get-UbuntuRootfs
    if (-not $rootfs) {
        Write-Fail "无法下载 Ubuntu 镜像。可手动下载 https://cloud-images.ubuntu.com/wsl/jammy/current/$RootfsName 放到 windows\offline\ 文件夹后重试。"
        Wait-Exit 1
    }
    $target = Join-Path $DistroDir $DistroName
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Write-Info '正在导入（约 1 分钟）...'
    & wsl.exe --import $DistroName $target $rootfs --version 2
    if ($LASTEXITCODE -ne 0 -or -not (Test-DistroInstalled)) {
        Write-Fail '导入 Linux 失败。常见原因：BIOS 中未开启 CPU 虚拟化，或 WSL 更新尚未生效（请重启电脑后重新运行本程序）。'
        Wait-Exit 1
    }
    Write-Ok '导入完成'
}

# ------------------------------------------------------------------ 5. 部署程序
Write-Step '第 5/6 步：在 Linux 中安装程序及依赖（首次约 5-15 分钟，取决于网速）'
$mirror = 'default'
if ($UseCn) { $mirror = 'cn' }
& wsl.exe -d $DistroName -u root -e bash "$ProjectLinux/windows/linux/provision.sh" $ProjectLinux (ConvertTo-WslPath $PhotoDir) $mirror (ConvertTo-WslPath $LogDir)
$code = $LASTEXITCODE
& wsl.exe --terminate $DistroName | Out-Null
if ($code -ne 0) {
    Write-Fail ("部署失败（代码 $code）。详细日志：" + (Join-Path $LogDir 'provision.log'))
    Write-Info '网络问题导致的失败可直接重新运行安装程序。'
    Wait-Exit 1
}
Write-Ok '程序部署完成'

# ------------------------------------------------------------------ 6. 快捷方式
Write-Step '第 6/6 步：创建桌面快捷方式'
function New-Shortcut([string]$Path, [string]$Target, [string]$WorkDir, [string]$Desc) {
    $sh = New-Object -ComObject WScript.Shell
    $lnk = $sh.CreateShortcut($Path)
    $lnk.TargetPath = $Target
    if ($WorkDir) { $lnk.WorkingDirectory = $WorkDir }
    $lnk.Description = $Desc
    $lnk.Save()
}
$desktop = [Environment]::GetFolderPath('Desktop')
$startExe = Join-Path $WinDir 'CameraController-Start.exe'
try {
    New-Shortcut (Join-Path $desktop '相机控制.lnk') $startExe $WinDir '启动相机控制程序'
    New-Shortcut (Join-Path $desktop '相机照片.lnk') $PhotoDir $null '延时摄影照片'
    Write-Ok '已创建桌面快捷方式：“相机控制”、“相机照片”'
} catch { Write-Warn ('创建快捷方式失败：' + $_.Exception.Message) }

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host '  安装完成！' -ForegroundColor Green
Write-Host '  使用：连接相机并开机 → 双击桌面“相机控制”'
Write-Host "  网页：$ServerUrl   登录：Admin / admin"
Write-Host "  照片：$PhotoDir"
Write-Host '============================================================' -ForegroundColor Green
if ((Test-Path $startExe) -and (Read-YesNo '现在启动吗？' $true)) {
    try { Stop-Transcript | Out-Null } catch {}
    Start-Process $startExe -WorkingDirectory $WinDir
    exit 0
}
Wait-Exit 0
