# 相机控制 PoC（安卓验证样例 v0.1）

目标：验证 **安卓手机通过 USB OTG + libgphoto2 直接控制佳能 EOS 5D Mark II**，无需 root。
跑通后再决定是否把原程序（网页控制、定时任务、延时摄影等）完整移植到安卓。

安装包：`CameraController-PoC.apk`（约 4 MB，支持 arm64-v8a / armeabi-v7a / x86_64，Android 7.0+）

## 一、测试步骤

**需要准备**
- 支持 USB OTG（主机模式）的安卓手机
- 数据线：手机口（USB-C 或 Micro-USB）→ **Mini-USB**（5D2 的接口）。可用“OTG 转接头 + 原装 Mini-USB 线”或一根 USB-C 转 Mini-B 线
- 5D2：电池充足；模式转盘放 **M / Av / Tv**；菜单中**启用实时显示拍摄**；自动关机设为关闭；画质建议先设为 **JPEG**（RAW 手机无法直接预览）

**操作**
1. 把 apk 发到手机安装（需允许“安装未知来源应用”）
2. 打开“相机控制 PoC”，下方信息区应出现：
   `driver self-test: N camera models, ... Canon EOS 5D Mark II: driver ptp2, USB 04a9:3199 ...`
   ——说明驱动在手机上加载正常（此步不需要相机）
3. 接上相机并开机。系统可能弹出“打开相机控制 PoC？”→ 确定（并可勾选“默认”）
4. 点 **连接相机** → 允许 USB 权限 → 应显示“已连接：Canon EOS 5D Mark II”，下方出现相机信息
5. 依次测试：**实时预览**（看帧率）、**拍照**（照片显示在屏幕上并存入相册 `Pictures/CameraController`）、修改 **ISO / 快门 / 光圈**

**请回报**
- 每一步的结果（截图即可）
- 不管成功与否，点 **导出诊断日志** 发给我（微信/邮件均可）。日志含手机型号、Android 版本、gphoto2 通信记录，不含照片

## 二、功能（本样例）

| 功能 | 说明 |
|---|---|
| 驱动自检 | 启动时加载相机型号表与 USB 端口驱动，确认 5D2 在支持列表中 |
| 连接 | 通过 Android UsbManager 获取 USB 权限和文件描述符，交给 libgphoto2（`gp_port_usb_set_sys_device`） |
| 相机信息 | 型号、序列号、固件、存储等（`gp_camera_get_summary`） |
| 实时预览 | 连续获取 LiveView JPEG 帧并显示帧率 |
| 拍照 | 拍摄并下载到手机；RAW+JPEG 时两张都会下载；相机拍摄目标为 Internal RAM 时下载后自动清除相机缓存 |
| 参数 | ISO、快门、光圈下拉选择（读写相机实际可选值） |
| 断开 | 拔线 / 相机关机自动断开，重新连接即可 |

未包含（若验证成功再做）：延时摄影/定时任务、后台常驻、多机、网页界面、全部参数。

## 三、技术说明

```
android/
├─ CameraController-PoC.apk          构建好的安装包
├─ app/src/main/java/.../MainActivity.java   界面 + USB 权限 + 调用顺序（单线程）
├─ app/src/main/java/.../GPhoto.java         JNI 接口
└─ app/src/main/cpp/
   ├─ CMakeLists.txt                 libusb + libgphoto2(core/port/libusb1/ptp2) + JNI → libgphoto2bridge.so
   ├─ gp_jni.c                       JNI 桥：open/summary/preview/capture/getChoices/setConfig/selfTest
   ├─ ltdl-shim/                     代替 libltdl：ptp2 相机驱动、libusb1 端口驱动静态链接为“内置模块”
   ├─ config/                        手写的 Android 版 config.h、gphoto2-endian.h（代替 configure 生成）
   └─ third_party/                   libgphoto2 2.5.34、libusb 1.0.30 源码（仅所需部分）
```

对上游源码的改动只有一处文件：`third_party/libgphoto2-2.5.34/libgphoto2_port/libusb1/libusb1.c`（搜索 `ANDROID PATCH`）：
1. 换了新的文件描述符（相机重插/重新开机）或设为 -1 时，丢弃缓存的 USB 句柄并重新包装
2. 包装失败时返回错误而不是对空指针调用 `libusb_get_device()` 崩溃；libusb 上下文只创建一次

### 重新构建

需要 JDK 17、Android SDK 35、NDK 28.2.13676358、CMake 3.31.6（本机已装在 `C:\AndroidDev`，安装脚本 `C:\AndroidDev\setup-toolchain.sh`）。

```powershell
$env:JAVA_HOME = 'C:\AndroidDev\jdk17'
cd android
.\gradlew.bat assembleRelease      # 输出 app\build\outputs\apk\release\app-release.apk
```
`local.properties` 中的 `sdk.dir` 需指向本机 SDK。也可直接用 Android Studio 打开 `android` 目录。

## 四、许可

libgphoto2 与 libusb 为 LGPL-2.1+（见 third_party 下 COPYING），本样例以源码形式一并提供。
