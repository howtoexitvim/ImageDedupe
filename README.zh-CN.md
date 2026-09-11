<div align="center">

# Image Dedupe

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

![Platform](https://img.shields.io/badge/platform-macOS-111827?logo=apple&logoColor=white)
![Type](https://img.shields.io/badge/type-Photo%20Dedupe-2563eb)
![Local First](https://img.shields.io/badge/architecture-local--first-059669)

</div>

Image Dedupe 是一个 Mac 原生应用，用于浏览已连接 iPhone 上的媒体文件、下载你选中的文件、找出保守的重复候选项，并在你明确确认后删除已审阅的设备文件。

它基于 Apple 的 ImageCaptureCore 框架构建。没有账号、没有云端后端、没有分析统计、不上传目录、也没有网络客户端——一切都留在你的 Mac 上。

任何文件都不会被自动删除。应用只负责提出建议，决定权在你。

原名 iPhone Dedupe。改名后原有的操作历史与偏好设置会自动延续；只有在标识符必须保持稳定的地方才保留了旧名称。

## 安装

从 [releases 页面](https://github.com/howtoexitvim/ImageDedupe/releases)下载 DMG——当前版本为 `ImageDedupe-v1.0`（版本号 1.0.0）——将应用拖入「应用程序」文件夹，然后清除下载隔离标记：

```sh
xattr -dr com.apple.quarantine "/Applications/Image Dedupe.app"
```

该构建为 ad-hoc 签名，**未经** Apple 公证，因此在执行上述命令之前 Gatekeeper 会拦截它。仅支持 macOS 14 或更高版本、Apple 芯片（arm64）。如果你不愿意运行未公证的二进制文件，可以从源码构建——见下文。

扫描之前，请先解锁 iPhone 并信任这台 Mac，同时退出「图像捕捉」、「照片」以及其他可能独占设备会话的应用。

## 安全性

安全性是这个项目的出发点，而不是它的某个附加功能。

- 重复检测刻意保持保守：它只产出供你审阅的*候选项*，绝不自动删除。
- 设备删除始终需要在应用内明确确认，会写入持久化的审计记录，并在删除后自动重新扫描；重试仅做校验。
- 自动化流程或开发用测试工具执行的删除，还必须获得新的用户批准，并明确列出具体的测试文件名。旧的批准永远不可复用。
- 下载先暂存到私有位置，再以相对描述符、不覆盖的方式提交，因此已有文件绝不会被悄悄替换。
- 没有账号、没有云端、没有分析统计、没有网络客户端。
- 本地构建关卡强制启用 Hardened Runtime，应用附带无追踪的隐私清单（privacy manifest）。

## 功能

- 原生 List 与 Grid 两种浏览视图，共享焦点，使用明确的复选框选择；
- 文件名搜索，并支持 `name:`、`kind:`、`size:`、`duration:` 过滤条件；
- List 列可排序且状态持久保存；
- 渐进式静态 Inspector 预览，上限 2048 像素，内存缓存有明确上界；
- 保守的重复候选项——绝不自动删除；
- 下载进度、当前文件状态、取消、目标位置预检与冲突拦截；
- 明确的设备删除确认、持久化审计、自动重新扫描，以及仅做校验的重试；
- 持久保存的部分失败与取消的 Results 历史记录；
- 主流程支持完全键盘控制（Full Keyboard Access）与 VoiceOver 语义。

## 环境要求

- macOS 14 或更高版本，Apple 芯片（arm64）；
- Swift 6.2 工具链（用于构建）；
- 一台已解锁、已信任的 iPhone，通过支持数据传输的数据线连接；
- 扫描期间关闭「图像捕捉」、「照片」以及其他可能独占设备会话的应用。

## 构建与运行

构建常规的本地 Debug 应用包：

```sh
./scripts/build-debug-app.sh
open "$(swift build --show-bin-path)/Image Dedupe.app"
```

UI 与无障碍测试请使用 `.app` 包。直接运行 SwiftPM 可执行文件会绕过 macOS 正常的应用注册流程，不是验收路径。

运行完整测试套件：

```sh
swift test
swift test -c release
```

最新验证基线为 650 个 XCTest 测试加 22 个 Swift Testing 测试，Debug 与 Release 配置下均通过。

当目标应用正在运行时，打包脚本会拒绝替换或重新签名它。重新构建之前请先退出应用；这可以避免 macOS 以 `Code Signature Invalid` 终止一个正在运行的进程。

## 发布候选版本

构建明确仅限本地、不可分发的 ad-hoc Hardened Runtime 候选版本：

```sh
IMAGE_DEDUPE_ALLOW_ADHOC=1 ./scripts/build-release-candidate.sh
```

如需可分发的候选版本，请提供调用者自己拥有的 Developer ID Application 身份：

```sh
IMAGE_DEDUPE_SIGNING_IDENTITY="Developer ID Application: …" \
  ./scripts/build-release-candidate.sh
```

在配置好调用者自己的 `notarytool` 钥匙串配置后：

```sh
IMAGE_DEDUPE_SIGNING_IDENTITY="Developer ID Application: …" \
IMAGE_DEDUPE_NOTARY_PROFILE="profile-name" \
  ./scripts/notarize-release.sh "/path/to/Image Dedupe.app"
```

当必需的签名或公证输入缺失时，发布脚本会直接失败退出。本仓库不存储任何凭据。

## 磁盘映像

`scripts/package-dmg.sh` 会将一个已构建好的候选版本打包为 `dist/Image-Dedupe-<version>.dmg`，采用常见的拖拽到「应用程序」的布局。它刻意不执行构建：它打包的是 `build-release-candidate.sh` 产出的那个包，因此最终分发的产物就是通过验证的那一个，而不是另一次「看起来一样」的构建。

```sh
IMAGE_DEDUPE_ALLOW_ADHOC=1 ./scripts/package-dmg.sh
```

打包前它会对该包重新运行 `verify-release.sh`，并且除非显式设置 `IMAGE_DEDUPE_ALLOW_ADHOC=1`，否则拒绝 ad-hoc 签名——磁盘映像正是未验证的应用包从「本地失误」变成「他人下载物」的那条界线。若设置了 `IMAGE_DEDUPE_SIGNING_IDENTITY`，映像本身也会被签名；由于 stapling 作用于应用包，请先对 `.app` 完成公证再打包。

`dist/` 已被忽略，永不提交。

## 项目结构

- `Sources/DeduperCore`：纯模型、搜索/排序、重复判定策略、展示逻辑与重试策略；
- `Sources/DeviceMediaKit`：串行化的 ImageCaptureCore 网关与安全的文件系统边界；
- `Sources/ImageDedupeApp`：SwiftUI/AppKit 应用、状态、持久化与视图；
- `Sources/ImageDedupeVerifier`：仅供开发使用的真机测试工具；
- `Tests`：单元、集成、渲染、操作、持久化与安全回归测试；
- `Packaging`：应用 Info.plist 与隐私清单；
- `scripts`：Debug/Release 打包、验证与公证工具。

## 现状

应用已在连接真实 iPhone 的情况下运行验证，加载了 3,961 / 3,961 个媒体项目。源码与本地 Hardened Runtime 构建关卡均已完成。

还有一些工作坦率地说仍未完成：Developer ID 签名、Apple 公证与 stapling、干净 Mac 上的 Gatekeeper 验证、通用（universal）构建，以及是否启用 App Sandbox 的决定。在这些完成之前，分发的 DMG 仍需要上文的隔离标记清除步骤。

## 许可证

[MIT](LICENSE)
