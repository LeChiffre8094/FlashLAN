# FlashLAN 开发与维护指南 (AGENTS.md)

## 项目基础
- 本项目是 iOS 16+ 原生 SwiftUI App，显示名称为“闪传 LAN”，Bundle Identifier 为 `com.flashlan.transfer`。
- 采用双核自适应网络传输架构：前台 Turbo 模式（`URLSessionConfiguration.default`）跑满 Wi-Fi 50–60+ MB/s，锁屏/后台模式（`URLSessionConfiguration.background`）保活 25–30 MB/s 续传。
- 维护以现有源码和用户需求为准，保留用户已有改动，做针对性增量修改。

## 代码位置
- `iOS/FlashLAN/ContentView.swift`：卡片化传输仪表盘、文件列表、OLED Zen 挂机模式视图、服务器管理。
- `iOS/FlashLAN/DownloadEngine.swift`：双会话协同调度、速度计算、断点续传、文件持久化与重名处理。
- `iOS/FlashLAN/DirectoryBrowser.swift`：Caddy 原生 JSON / HTML 解析与防路径穿越校验。
- `iOS/FlashLAN/Models.swift`：文件分类徽章与颜色定义、下载记录、服务器数据持久化。
- `iOS/FlashLAN/FlashLANApp.swift`：App 入口与 AppDelegate 后台事件桥接。
- `project.yml`：XcodeGen 规范描述文件；`.github/workflows/build.yml`：未签名 IPA 构建流水线。
- `Tests/FlashLANTests.swift`：XCTest 针对性单元测试套件。
- `windows/Start-FlashLAN.bat`：电脑端高性能直连共享脚本。

## 核心架构约束
- **前后台切换安全**：前后台切换必须通过 `cancel(byProducingResumeData:)` 同步抓取断点信息，保证文件不被重置或损坏。
- **OLED Zen 模式**：必须保持背景全黑（`Color.black.ignoresSafeArea()`），`UIApplication.shared.isIdleTimerDisabled` 必须与挂机状态严格同步；界面文字需保持微位移避免烧屏。
- **电脑端高性能直连**：必须保持 Caddy 原生 `file_server` 直连，不得擅自加回本地套娃反向代理。
- **文件保存规范**：同名冲突时依次采用 `name-1.ext` 编号，不覆盖旧文件；移除记录不得删除实际下载文件。
