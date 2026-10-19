# 文件共享 · FileShare

一个用 Flutter 构建的 macOS 原生**局域网文件共享**应用。一键启动 HTTP 服务，把本机文件或文件夹共享给同一局域网内的手机、平板、其他电脑，对方通过浏览器链接即可浏览和下载。

## 功能

- **一键启动 / 停止 HTTP 服务**，端口可配置（默认 8080）
- **选择文件或文件夹**加入共享列表（支持多选文件）
- 界面实时显示**可访问的 HTTP 链接**（自动枚举本机所有局域网 IP），支持一键复制
- 每个共享项有独立的下载链接（`/f/<id>`），支持**二维码扫码打开**
- 文件夹支持**在线浏览**子目录并逐层下载
- 浏览器直接打开文件支持 `?inline=1` 参数（inline 模式）
- 服务端自带**路径穿越防护**、404/403 处理
- 显示累计请求次数，可随时移除共享项
- **窗口最小尺寸 900×640**（默认 1000×720，居中打开），防止内容显示不下

## 项目结构

```
http_service/
├── pubspec.yaml                 # 依赖配置
├── lib/
│   ├── main.dart                # 应用入口
│   ├── models/
│   │   └── share_item.dart      # 共享项模型（文件/文件夹）
│   ├── server/
│   │   └── share_server.dart    # HTTP 共享服务器核心（dart:io）
│   └── ui/
│       └── home_page.dart       # 主界面
├── test/
│   └── widget_test.dart         # 服务器功能测试（下载/浏览/安全/404）
└── macos/
    └── Runner/
        ├── DebugProfile.entitlements  # 调试权限（沙盒 + 网络服务 + 文件访问）
        └── Release.entitlements      # 发布权限（沙盒 + 网络服务 + 文件访问）
```

## 在 Mac 上初始化并运行

### 前置要求

- Flutter SDK 3.3 以上
- Xcode 14 以上
- macOS 12 以上

### 步骤

1. **把项目拷到 Mac 上**，然后在项目根目录执行：

```bash
# 拉取依赖
flutter pub get

# 如果 macos/ 目录不完整，重新生成平台代码（不会覆盖 lib/）
flutter create . --platforms=macos
```

2. **确认沙盒权限已配置**

`macos/Runner/DebugProfile.entitlements` 和 `Release.entitlements` 已包含以下关键权限，**不要删掉**：

| Entitlement | 用途 |
|---|---|
| `com.apple.security.network.server` | 允许应用接受入站连接（HTTP 服务必需） |
| `com.apple.security.network.client` | 允许应用发起网络请求 |
| `com.apple.security.files.user-selected.read-only` | 允许读取用户在文件选择器中选中的文件/文件夹 |

3. **运行**：

```bash
flutter run -d macos
```

4. **打包发布版**：

```bash
flutter build macos
```

产物在 `build/macos/Build/Products/Release/文件共享.app`。

## 使用说明

1. 启动应用，点击「**一键启动**」
2. 点击「**添加文件**」或「**添加文件夹**」选择要共享的内容
3. 界面「其他设备访问地址」区域会显示 `http://<局域网IP>:<端口>/` 链接
   - 手机等设备用**相机扫码**即可打开
   - 或把链接复制到手机/其他电脑的浏览器
4. 页面上可以看到所有共享项及各自的下载链接；文件夹点进去可以逐层浏览

> 注意：手机和其他设备需要与 Mac 处于**同一个局域网**（同一 Wi-Fi / 同一路由器）。

## 关键依赖

| 包 | 用途 |
|---|---|
| `file_picker` | macOS 原生文件/文件夹选择 |
| `mime` | 按扩展名识别 Content-Type |
| `qr_flutter` | 访问地址二维码 |
| `window_manager` | 窗口管理（默认尺寸、最小尺寸、标题） |
| `flutter_lints` | 代码规范 |

## 测试

```bash
flutter test
```

覆盖：服务启动与随机端口、索引页、文件下载内容与 Content-Disposition、inline 访问、文件夹浏览与子文件下载、未知 id 的 404、路径穿越防护（原始 Socket 未规范化请求）。

## 常见问题

**Q: 启动失败提示端口被占用？**
A: 换一个端口（如 8081、9000），或先结束占用该端口的进程。

**Q: 手机打不开链接？**
A: 确认手机和 Mac 在同一局域网；确认 macOS「系统设置 → 网络」中防火墙没有阻止本应用接受连接（首次启动时允许接入）。

**Q: 沙盒错误 / 文件读取失败？**
A: 检查 entitlements 中 `network.server` 和 `files.user-selected.read-only` 是否还在。

**Q: 窗口最小尺寸如何调整？**
A: 在 `lib/main.dart` 顶部修改 `_kMinWindowSize` 常量（默认 900×640），默认尺寸为 `_kDefaultWindowSize`。

**Q: 中文文件名下载后乱码？**
A: 不会，服务端按 RFC 5987 发送 UTF-8 编码的文件名。
