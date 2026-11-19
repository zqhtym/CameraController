# 相机控制程序 · Windows 10/11 版使用说明

把本程序（CameraController，基于 gphoto2 的网页相机控制程序）在 Windows 上一键安装、一键运行。
适用相机：佳能 EOS 5D Mark II，以及 [libgphoto2 支持](http://www.gphoto.org/proj/libgphoto2/support.php) 的其他相机。

> 原理：gphoto2 不支持 Windows，所以安装程序会自动在 Windows 里装一个专用的小型 Linux（WSL2 + Ubuntu 22.04），
> 再用 usbipd-win 把相机的 USB 转给它。程序代码不变，你只需要双击 exe。

## 文件

| 文件 | 作用 |
|---|---|
| `CameraController-Setup.exe` | **安装**（只需运行一次；可重复运行用于修复/更新程序） |
| `CameraController-Start.exe` | **启动**（日常使用；安装后桌面也有“相机控制”快捷方式） |
| `CameraController-Uninstall.exe` | 卸载 |
| `scripts\`、`linux\` | exe 调用的脚本，**必须和 exe 放在一起** |
| `offline\`（可选，自己建） | 放离线安装包，无网或网慢时使用，见下文 |

整个 `CameraController-master` 文件夹复制到目标电脑（本地磁盘，不要放网络盘），`windows` 文件夹保持在里面。

## 系统要求

- Windows 10 版本 2004（内部版本 19041）或更高，64 位；建议先装完所有 Windows 更新
- BIOS/UEFI 中已开启 CPU 虚拟化（Intel VT-x / AMD-V）
- 管理员账户；首次安装需联网（约 400 MB）并重启一次

## 安装

1. 双击 `CameraController-Setup.exe`，在弹出的权限提示中点“是”
2. 选择是否使用国内镜像（国内网络建议选 Y）
3. 如提示重启，选 Y。重启后**登录同一账户**，安装会自动继续
4. 等待 6 个步骤完成（首次 10–20 分钟）

安装程序会做的事：启用 WSL 功能 → 安装 WSL → 安装 usbipd-win → 导入专用 Ubuntu 22.04（名为 `CameraCtrl`）→
在其中安装 gphoto2、Python 依赖、初始化数据库 → 创建桌面快捷方式。
为安全起见，还会把“失败 N 次自动重启系统”改为 0（原程序默认失败 2 次就执行 `sudo reboot`），并关闭 ykush 硬复位。

数据位置：`C:\CameraController\`（`Photos\` 照片，`logs\` 日志，`wsl\` Linux 磁盘文件）。

## 使用

1. 相机设置：模式转盘放 **M/Av/Tv**；菜单中**启用实时显示拍摄**；**自动关机设为关闭**；长时间延时摄影建议用电源适配器
2. USB 线连接电脑，打开相机电源，关闭 EOS Utility 等占用相机的软件
3. 双击桌面 **“相机控制”** → 权限提示点“是” → 自动打开浏览器 `http://localhost:5000/`
4. 登录：账号 `Admin`，密码 `admin`（地址 `http://localhost:5000/accounts/login/`）
5. 用完后**关闭黑色窗口**（或按 Ctrl+C），相机会自动交还给 Windows

运行期间相机被转给 Linux 使用，Windows 中的 EOS Utility、资源管理器等暂时看不到相机。
运行中重新插拔相机或关机再开机，会自动重新转接；如网页中相机消失，在首页点击 **Autodetect cameras**。

### 5D Mark II 使用建议

- 画质只选 **RAW** 或只选 **JPEG**，不要选 RAW+JPEG（程序每次只下载一个文件）
- 延时摄影把镜头切到 **MF**，否则对焦失败会导致该张拍摄失败
- 默认 `capturetarget = Internal RAM`：照片只传到电脑、不存卡；想同时存卡可在设置页改为 `Memory card`
- 延时摄影默认文件名含 `{camera_id}`（如 `usb:001,005`），冒号在 Windows 文件名中会显示为特殊字符，
  建议把文件名格式改为 `5D2_{capture_index}` 或 `{timelapse_name}_{capture_index}`；不要用 `{camera_serial_nb}`
- 定时任务的时间按 **Windows 当前时区**（启动器会自动传给程序）

## 离线 / 网络慢

把下列文件放进 `windows\offline\`，安装程序会优先使用：

| 文件 | 下载地址 |
|---|---|
| `ubuntu-jammy-wsl-amd64-ubuntu22.04lts.rootfs.tar.gz` | https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cloud-images/wsl/jammy/current/ （或 https://cloud-images.ubuntu.com/wsl/jammy/current/ ） |
| `usbipd-win_*_x64.msi` | https://github.com/dorssel/usbipd-win/releases |
| `wsl.*.x64.msi`（仅在 WSL 自动安装失败时需要） | https://github.com/microsoft/WSL/releases |

注意：Python 和 Ubuntu 软件包（约 60 MB）仍需联网下载。

## 常见问题

| 现象 | 处理 |
|---|---|
| 第 4 步“导入 Linux 失败” | BIOS 开启 CPU 虚拟化；或重启电脑后重新运行安装程序 |
| 第 5 步失败 | 多为网络问题，直接重新运行安装程序即可；日志 `C:\CameraController\logs\provision.log` |
| 启动时一直“未检测到佳能相机” | 换 USB 口/线；确认相机已开机；关闭 EOS Utility；在“设备管理器”中应能看到 Canon EOS 5D Mark II |
| 网页能打开但没有相机 | 首页点 **Autodetect cameras**；查看 `C:\CameraController\logs\usbipd-attach-*.log`；第三方防火墙需放行 usbipd（TCP 3240） |
| 想从其他电脑访问网页 | 默认仅本机可访问（WSL 网络限制） |
| 更新程序代码 | 修改项目文件后重新运行 `CameraController-Setup.exe`（数据库和设置会保留） |

## 卸载

运行 `CameraController-Uninstall.exe`：删除专用 Linux 环境（含程序设置和定时任务）、快捷方式；照片默认保留；可选卸载 usbipd-win。

## 重新编译 exe（一般不需要）

`powershell -ExecutionPolicy Bypass -File windows\launcher\build.ps1`（使用 Windows 自带的 .NET Framework 编译器）
