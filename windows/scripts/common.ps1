# 公共变量与函数（install.ps1 / start.ps1 / uninstall.ps1 共用）
# 注意：本文件需保存为 UTF-8 with BOM，Windows PowerShell 5.1 才能正确读取中文。

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$DistroName  = 'CameraCtrl'                                   # 专用 WSL 发行版名称
$DataRoot    = Join-Path $env:SystemDrive 'CameraController'  # C:\CameraController
$DistroDir   = Join-Path $DataRoot 'wsl'
$DownloadDir = Join-Path $DataRoot 'downloads'
$LogDir      = Join-Path $DataRoot 'logs'
$PhotoDir    = Join-Path $DataRoot 'Photos'
$ConfigFile  = Join-Path $DataRoot 'config.json'
$SessionFile = Join-Path $LogDir 'session.json'
$WinDir      = Split-Path -Parent $PSScriptRoot               # ...\windows
$ProjectDir  = Split-Path -Parent $WinDir                     # 项目根目录
$OfflineDir  = Join-Path $WinDir 'offline'
$AppDirLinux = '/opt/CameraController'
$ServerPort  = 5000
$ServerUrl   = 'http://localhost:5000/'
$CanonVid    = '04A9'
$RootfsName  = 'ubuntu-jammy-wsl-amd64-ubuntu22.04lts.rootfs.tar.gz'
$ResumeTaskName = 'CameraController-Setup-Resume'

function Initialize-Console {
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
    $env:WSL_UTF8 = '1'
    foreach ($d in @($DataRoot, $DownloadDir, $LogDir, $PhotoDir)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    }
}

function Write-Step([string]$Msg) { Write-Host ''; Write-Host ('==> ' + $Msg) -ForegroundColor Cyan }
function Write-Ok([string]$Msg)   { Write-Host ('    [完成] ' + $Msg) -ForegroundColor Green }
function Write-Info([string]$Msg) { Write-Host ('    ' + $Msg) }
function Write-Warn([string]$Msg) { Write-Host ('    [注意] ' + $Msg) -ForegroundColor Yellow }
function Write-Fail([string]$Msg) { Write-Host ('    [错误] ' + $Msg) -ForegroundColor Red }

function Test-IsAdmin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Wait-Exit([int]$Code = 0) {
    try { Stop-Transcript | Out-Null } catch {}
    Write-Host ''
    Read-Host '按回车键关闭窗口' | Out-Null
    exit $Code
}

function Read-YesNo([string]$Question, [bool]$Default = $true) {
    $hint = '[y/N]'
    if ($Default) { $hint = '[Y/n]' }
    $ans = Read-Host ($Question + ' ' + $hint)
    if ([string]::IsNullOrWhiteSpace($ans)) { return $Default }
    return ($ans.Trim().ToLower() -in @('y', 'yes', '是'))
}

# ---------------------------------------------------------------- WSL

function Test-WslExe { return (Test-Path (Join-Path $env:windir 'System32\wsl.exe')) }

function Invoke-WslCapture([string[]]$WslArgs) {
    $out = & wsl.exe @WslArgs
    $code = $LASTEXITCODE
    $text = (($out | ForEach-Object { [string]$_ }) -join "`n") -replace "`0", ''
    return [pscustomobject]@{ Code = $code; Text = $text }
}

# 新版 WSL（应用商店/MSI 版）才支持 --version；旧版内置 WSL 内核太旧，usbipd 无法使用
function Test-WslModern {
    if (-not (Test-WslExe)) { return $false }
    $r = Invoke-WslCapture @('--version')
    return (($r.Code -eq 0) -and ($r.Text -match '\d+\.\d+\.\d+'))
}

function Get-WslDistros {
    if (-not (Test-WslExe)) { return @() }
    $r = Invoke-WslCapture @('-l', '-q')
    if ($r.Code -ne 0) { return @() }
    return @($r.Text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Test-DistroInstalled { return ((Get-WslDistros) -contains $DistroName) }

function Test-DistroRunning {
    $r = Invoke-WslCapture @('-l', '--running', '-q')
    if ($r.Code -ne 0) { return $false }
    return (@($r.Text -split "`n" | ForEach-Object { $_.Trim() }) -contains $DistroName)
}

function ConvertTo-WslPath([string]$WinPath) {
    $full = [System.IO.Path]::GetFullPath($WinPath)
    if ($full -notmatch '^([A-Za-z]):\\?(.*)$') { throw "不支持的路径（必须位于本地磁盘）：$full" }
    $rest = ($Matches[2] -replace '\\', '/').TrimEnd('/')
    return ('/mnt/' + $Matches[1].ToLower() + '/' + $rest).TrimEnd('/')
}

# ---------------------------------------------------------------- usbipd

function Get-UsbipdExe {
    $c = Get-Command usbipd.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $p = Join-Path $env:ProgramFiles 'usbipd-win\usbipd.exe'
    if (Test-Path $p) { return $p }
    return $null
}

# 返回所有佳能 USB 设备（VID 04A9）：是否已连接 / 已共享 / 已转接给 WSL
function Get-CanonDevices {
    $usbipd = Get-UsbipdExe
    if (-not $usbipd) { return @() }
    $json = (& $usbipd state) -join "`n"
    if ($LASTEXITCODE -ne 0 -or -not $json) { return @() }
    try { $state = $json | ConvertFrom-Json } catch { return @() }
    $list = @()
    foreach ($d in $state.Devices) {
        if ([string]$d.InstanceId -match ('VID_' + $CanonVid + '&PID_([0-9A-Fa-f]{4})')) {
            $list += [pscustomobject]@{
                BusId         = [string]$d.BusId
                Description   = [string]$d.Description
                ProductId     = $Matches[1].ToLower()
                IsConnected   = [bool]$d.BusId
                IsShared      = [bool]$d.PersistedGuid
                IsAttached    = [bool]$d.ClientIPAddress
                PersistedGuid = [string]$d.PersistedGuid
            }
        }
    }
    return $list
}

# ---------------------------------------------------------------- 下载 / 安装

function Enable-Tls12 {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {}
}

function Save-Download([string]$Url, [string]$OutFile) {
    Write-Info "下载：$Url"
    $tmp = $OutFile + '.part'
    $curl = Join-Path $env:windir 'System32\curl.exe'
    if (Test-Path $curl) {
        & $curl -L --fail --retry 3 --retry-delay 3 --connect-timeout 30 -C - -o $tmp $Url
        if ($LASTEXITCODE -eq 0) { Move-Item -Force $tmp $OutFile; return $true }
        Write-Warn "curl 下载失败（代码 $LASTEXITCODE），改用 PowerShell 重试"
        Remove-Item -Force $tmp -ErrorAction SilentlyContinue
    }
    try {
        Enable-Tls12
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $tmp
        Move-Item -Force $tmp $OutFile
        return $true
    } catch {
        Write-Warn ('下载失败：' + $_.Exception.Message)
        Remove-Item -Force $tmp -ErrorAction SilentlyContinue
        return $false
    }
}

function Get-TextFromUrl([string]$Url) {
    try {
        Enable-Tls12
        $c = (Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 30).Content
        if ($c -is [byte[]]) { $c = [System.Text.Encoding]::UTF8.GetString($c) }
        return [string]$c
    } catch { return $null }
}

function Get-GitHubAssetUrl([string]$Repo, [string]$Pattern) {
    try {
        Enable-Tls12
        $rel = Invoke-RestMethod -UseBasicParsing -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ 'User-Agent' = 'CameraController-Setup' } -TimeoutSec 30
        foreach ($a in $rel.assets) { if ($a.name -match $Pattern) { return [string]$a.browser_download_url } }
    } catch { Write-Warn ("无法查询 $Repo 的最新版本：" + $_.Exception.Message) }
    return $null
}

# 先找 windows\offline\（手动放入的离线安装包），再找 C:\CameraController\downloads\（缓存）
function Find-LocalFile([string]$Filter) {
    foreach ($d in @($OfflineDir, $DownloadDir)) {
        if (Test-Path $d) {
            $f = Get-ChildItem -Path $d -Filter $Filter -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -notlike '*.part' } |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($f) { return $f.FullName }
        }
    }
    return $null
}

function Install-Msi([string]$Msi) {
    Write-Info ('正在安装 ' + (Split-Path $Msi -Leaf) + ' ...')
    $p = Start-Process msiexec.exe -ArgumentList @('/i', ('"' + $Msi + '"'), '/qn', '/norestart') -Wait -PassThru
    if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) { return $true }
    Write-Fail ('安装失败（msiexec 返回 ' + $p.ExitCode + '）')
    return $false
}

# ---------------------------------------------------------------- 运行会话

function Test-PortOpen([int]$Port) {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $c.BeginConnect('localhost', $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(800) -and $c.Connected) { $c.EndConnect($iar); return $true }
        return $false
    } catch { return $false } finally { $c.Close() }
}

function Save-Session([int[]]$ProcIds) {
    @{ Pids = $ProcIds } | ConvertTo-Json | Set-Content -Path $SessionFile -Encoding UTF8
}

# 结束上次异常退出时遗留的后台进程（usbipd 自动转接、WSL 保活）
function Stop-PreviousSession {
    if (-not (Test-Path $SessionFile)) { return }
    $s = $null
    try { $s = Get-Content -Raw -Path $SessionFile | ConvertFrom-Json } catch {}
    if ($s -and $s.Pids) {
        foreach ($procId in $s.Pids) {
            $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
            if ($p -and ($p.ProcessName -in @('usbipd', 'wsl'))) { Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue }
        }
    }
    Remove-Item -Force $SessionFile -ErrorAction SilentlyContinue
}

function Open-Browser([string]$Url) {
    # 通过 explorer 打开，浏览器以普通权限运行（而不是管理员权限）
    Start-Process explorer.exe -ArgumentList $Url
}

# Windows 时区 -> Linux 时区名（未收录的时区按整点偏移换算为 Etc/GMT±N）
function Get-LinuxTzHint {
    $map = @{
        'China Standard Time'          = 'Asia/Shanghai'
        'Taipei Standard Time'         = 'Asia/Taipei'
        'Tokyo Standard Time'          = 'Asia/Tokyo'
        'Korea Standard Time'          = 'Asia/Seoul'
        'Singapore Standard Time'      = 'Asia/Singapore'
        'UTC'                          = 'UTC'
        'GMT Standard Time'            = 'Europe/London'
        'W. Europe Standard Time'      = 'Europe/Berlin'
        'Romance Standard Time'        = 'Europe/Paris'
        'Central Europe Standard Time' = 'Europe/Budapest'
        'Russian Standard Time'        = 'Europe/Moscow'
        'Eastern Standard Time'        = 'America/New_York'
        'Central Standard Time'        = 'America/Chicago'
        'Mountain Standard Time'       = 'America/Denver'
        'Pacific Standard Time'        = 'America/Los_Angeles'
        'AUS Eastern Standard Time'    = 'Australia/Sydney'
    }
    $tz = [TimeZoneInfo]::Local
    if ($map.ContainsKey($tz.Id)) { return $map[$tz.Id] }
    $off = $tz.GetUtcOffset([DateTime]::Now).TotalMinutes
    if (($off % 60) -ne 0) { return 'UTC' }
    $h = [int]($off / 60)
    if ($h -eq 0) { return 'UTC' }
    if ($h -gt 0) { return ('Etc/GMT-' + $h) }
    return ('Etc/GMT+' + (-$h))
}
