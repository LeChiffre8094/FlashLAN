# ⚡ 闪传 · FlashLAN (iOS)

> **极速 · 纯净 · 息屏挂机的 iOS 原生局域网无损文件传输工具**  
> 专为大文件局域网直传打造，解决 iOS 后台限速与长时间亮屏烧屏痛点。

---

## ✨ 核心特色与架构升级

1. **⚡ 双核自适应传输引擎 (Dual-Engine Transfer)**
   - **前台 Turbo 极速模式**：采用原生高速会话，绕过 iOS 后台守护进程（`nsurlsessiond`）的功耗限流，局域网实测跑满 **55–60+ MB/s**。
   - **锁屏平滑降级接管**：按电源键锁屏或切到后台时，通过 HTTP Range 断点无缝交接给系统后台会话（**25–30 MB/s** 保活续传），绝不中断任务。
   - **亮屏自动回弹提速**：重新解锁进入 App 后，瞬间自动无缝切回 Turbo 极速会话，恢复 55–60 MB/s 满速。

2. **🌙 OLED 防烧屏极速挂机模式 (Zen Screen Mode)**
   - **零烧屏风险**：全屏呈现纯黑（RGB: 0, 0, 0），OLED 屏幕物理断电熄灭像素点，屏幕功耗几乎为零，发热极小。
   - **全程保持满速**：因为系统判定 App 处于前台活跃状态，网络协议栈全程不降速，整晚挂机传输大批量文件也能持续维持 **55–60 MB/s**。
   - **防烧屏像素微漂移**：界面微光时钟与速率看板每隔 25 秒轻微随机位移，彻底杜绝同位置像素老化。轻触任意位置即可瞬时唤醒。

3. **🚀 电脑端直连零拷贝 (Direct Zero-Copy)**
   - 彻底移除了旧版中 Caddy 的本地套娃反向代理（`reverse_proxy`），直接调用高性能 `file_server`。
   - 利用操作系统内核级零拷贝优化，消除了本机 TCP 回环与内存缓冲瓶颈。

4. **📱 独立共存 (Standalone & Side-by-Side)**
   - 独立的 Bundle Identifier：`com.flashlan.transfer`。
   - 显示名称：“闪传 LAN”。
   - 独立的本地数据库与沙盒存储，可与你的旧版 App **同时签名安装在同一台 iPhone 上**，无缝横向对比传输性能。

5. **🎨 全新现代美学设计**
   - 极光深空蓝紫主题，卡片化圆角设计与 SF Symbols 动效。
   - 传输页面顶部常驻**实时传输速率动态仪表盘**（实时速率、动态脉冲、剩余文件一览）。
   - 重新设计的专属 App 图标（暗夜深蓝底色 + 霓虹渐变流光闪电 + 局域网拓扑波形）。

---

## 🛠️ 快速上手

### 1. 电脑端启动（Windows）
1. 确保电脑已安装 `caddy.exe`（放在 `C:\Caddy\caddy.exe`、PATH 路径或脚本同级目录下均可）。
2. 将 `windows/Start-FlashLAN.bat` 复制到你要共享的文件夹（如 `D:\Movies`）。
3. 双击 `Start-FlashLAN.bat`，窗口会显示绿色 IP 地址与端口（如 `http://192.168.1.100:8080`）。

### 2. 手机端连接与极速传输
1. 确保 iPhone 与电脑连接同一 Wi-Fi 网段。
2. 打开【闪传 LAN】，进入【电脑端】添加电脑 IP 与端口。
3. 在【文件库】中勾选需要下载的文件，点击【开始极速传输】。
4. 在传输页面点击右上角【挂机】，手机即进入 OLED 防烧屏纯黑模式，享受全程 55–60 MB/s 满速下载。

---

## 📦 项目构建 (GitHub Actions)

本项目已配置完全独立的 GitHub Actions 工作流（`.github/workflows/build.yml`）：
- **触发方式**：手动触发（`workflow_dispatch`），避免每次代码提交浪费 CI 时长。
- **构建产物**：自动执行 28 项针对性单元测试，并打包生成未签名的 `FlashLAN-v1.0.0-build1-unsigned.ipa`。
- **安装方式**：下载 Actions 生成的未签名 IPA，使用个人免费证书（如 TrollStore、AltStore、Sideloadly 或爱思助手）签名安装即可。

---

## 📂 目录结构

```text
FlashLAN/
├── .github/workflows/build.yml     # GitHub Actions 自动化构建与测试工作流
├── project.yml                     # XcodeGen 规范配置文件
├── FlashLAN.xcodeproj/             # 预生成的 Xcode 工程文件
├── windows/
│   └── Start-FlashLAN.bat          # 电脑端高性能直连共享脚本
├── iOS/FlashLAN/
│   ├── FlashLANApp.swift           # App 入口与后台会话事件桥接
│   ├── ContentView.swift           # 现代 UI：仪表盘、文件列表、OLED 挂机视图
│   ├── DownloadEngine.swift        # 双核自适应传输引擎 (Turbo + Background)
│   ├── DirectoryBrowser.swift      # Caddy 原生 JSON / HTML 解析器
│   ├── FloatingVideoPlayer.swift   # App 内视频浮窗预览模块
│   ├── Models.swift                # 数据结构、分类颜色、服务器配置
│   ├── Info.plist                  # 权限声明与应用元数据
│   └── Assets.xcassets/            # 专属 App 图标集与 AccentColor
├── Tests/
│   └── FlashLANTests.swift         # 针对性单元测试套件 (28 项)
└── README.md                       # 项目说明文档
```

---

## 📄 许可证
本项目基础架构基于 GPL-3.0 协议开源，内含第三方多媒体组件（KSPlayer、FFmpegKit、SwiftSoup）均保留原许可协议。
