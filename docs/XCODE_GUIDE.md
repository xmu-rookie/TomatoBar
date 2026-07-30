# Xcode 开发、调试与发布指南

这份文档面向第一次使用 Xcode 的贡献者。TomatoBar 是一个 macOS 菜单栏应用：运行后不会出现在 Dock 中，入口是屏幕右上角的番茄图标。

## 先理解几个概念

- **Project**：`TomatoBar.xcodeproj`，保存源文件、依赖和构建设置。
- **Target**：要构建的产品。当前有 `TomatoBar` 应用 Target 和 `TomatoBarTests` 单元测试 Target。
- **Scheme**：告诉 Xcode 构建哪个 Target、使用哪种配置。
- **Debug / Release**：Debug 用于开发调试；Release 用于最终交付。
- **Bundle Identifier**：macOS 识别应用的唯一 ID，当前是 `com.github.ivoronin.TomatoBar`。
- **`.app`**：并不是单个可执行文件，而是包含程序、图标和资源的应用包。

## 日常运行与调试

1. 双击 `TomatoBar.xcodeproj`。
2. 等待 Xcode 完成 `Resolving Package Graph`。
3. 顶部选择 `TomatoBar > My Mac`。
4. 按 `Cmd-B` 编译；成功时显示 `Build Succeeded`。
5. 按 `Cmd-R` 启动 Debug 版本。
6. 在右上角菜单栏找到番茄图标并验证功能。
7. 按 `Cmd-.` 或点击 Xcode 左上角停止按钮结束调试。

运行自动测试：

1. 确认顶部 Scheme 是 `TomatoBar`，运行设备是 `My Mac`。
2. 按 `Cmd-U`，Xcode 会构建应用并运行 `TomatoBarTests`。
3. 左侧打开 `Test Navigator`（菱形图标）。所有测试右侧显示绿色对勾即为通过。
4. 单个测试失败时，点击红色叉号查看完整错误；修复后点击测试名称旁的运行按钮重试。

当前基线包含 7 个计时状态测试，覆盖启动、取消、工作结束、休息结束、停止于休息后和跳过休息。

常用调试方法：

- 在 Swift 文件左侧行号栏单击，添加蓝色断点；程序执行到该行会暂停。
- 暂停后，下方变量区可以查看当前值；鼠标悬停变量也能查看。
- 用 `View > Debug Area > Activate Console` 打开控制台，查看 `print(...)` 输出和错误。
- 左侧 `Issue Navigator`（警告三角形图标）集中显示编译错误；先处理第一个红色错误。
- 修改代码后直接再次按 `Cmd-R`。菜单栏应用不适合依赖 SwiftUI Preview，实际运行验证更可靠。

手工回归至少检查：弹窗打开、开始/停止、工作/休息切换、通知、声音、快捷键和退出。事件日志位于：

```text
~/Library/Containers/<Bundle Identifier>/Data/Library/Caches/TomatoBar.log
```

### 常见问题

- 看到两个番茄图标：退出已安装版本和 Xcode 启动的 Debug 版本，再重新运行。
- Swift Package 下载异常：使用 `File > Packages > Reset Package Caches`，然后 `Resolve Package Versions`。
- 构建缓存异常：使用 `Product > Clean Build Folder`，再按 `Cmd-B`。
- 终端提示 active developer directory 是 `CommandLineTools`：打开 `Xcode > Settings > Locations`，把 `Command Line Tools` 选择为当前 Xcode。
- 报错仍未解决：保留从第一个错误开始的完整信息，不要只截最后一行。

## “变成我的 App”需要改什么

在功能稳定后统一改名，避免开发过程中制造无关差异。

1. 在左侧选择蓝色项目图标，再选择 `TARGETS > TomatoBar`。
2. 在 `General > Identity` 修改：
   - Display Name，例如 `Taskmato`
   - Bundle Identifier，例如 `com.yourname.taskmato`
   - Version，例如 `1.0.0`
   - Build，例如 `1`
3. 在 `Build Settings` 搜索 `Product Name`，把 Debug 和 Release 都改为 `Taskmato`。这决定 Finder 中的 `Taskmato.app` 文件名。Target 和 Scheme 可以暂时继续叫 `TomatoBar`。
4. 打开 `Assets.xcassets > AppIcon`，用自己的图标替换现有尺寸。
5. 更新项目设置中的 copyright，但保留根目录 `LICENSE` 和原作者版权声明；本项目使用 MIT License。
6. 如需修改 `tomatobar://startStop`，同步更新 `Info.plist` 中的 URL Scheme、`Timer.swift` 的处理逻辑和 README。

修改 Bundle Identifier 后，macOS 会把它当成一个全新的应用；原版的设置和日志不会自动迁移。

## 只安装到自己的 Mac

应用在 Xcode 运行时就已经生成了，只是位于构建目录中。个人本机安装不需要上架 App Store：

1. 顶部选择 `TomatoBar > My Mac`。
2. 使用 `Product > Archive`。
3. Archive 完成后会打开 Organizer；也可以从 `Window > Organizer > Archives` 打开。
4. 选择最新 Archive，点击 `Distribute App`。
5. 选择 `Copy App`，导出 `.app`。
6. 退出 Xcode 中运行的 Debug 版本，把导出的 `.app` 拖入 `/Applications`。
7. 从“应用程序”启动并完成一次完整计时验证；确认路径固定后再启用“登录时启动”。

这个版本适合自己的电脑，不适合直接发给其他人。更新时先退出旧版本，再用新 `.app` 替换。

## 发给其他 Mac 用户

正式分发需要加入付费的 Apple Developer Program，并使用 **Developer ID** 签名和 Apple 公证，否则 Gatekeeper 可能阻止其他用户打开。

发布前需要：

1. 在 `Xcode > Settings > Accounts` 登录开发者账号。
2. 在 `Signing & Capabilities` 选择 Team，配置自动签名。
3. 为 App 和嵌入的登录启动 Helper 使用有效签名，并启用 Hardened Runtime。
4. 使用 `Product > Archive`。
5. 在 Organizer 中选择 `Distribute App > Developer ID > Upload`。
6. 等待状态变为 `Ready to distribute`，再选择 `Export Notarized App`。
7. 在另一台 Mac 上测试下载、首次启动、通知、登录启动和网络功能。

当前项目为 CI 使用了 ad-hoc 签名设置。准备公开发布时，需要一起调整 Release 签名和 CI 工作流，不能只在 Xcode 中临时选择证书。

Apple 官方参考：

- [创建 Archive](https://help.apple.com/xcode/mac/current/en.lproj/devf37a1db04.html)
- [在 Mac App Store 之外分发](https://help.apple.com/xcode/mac/current/en.lproj/dev033e997ca.html)
- [上传并公证 macOS App](https://help.apple.com/xcode/mac/current/en.lproj/dev88332a81e.html)

## Todoist 与敏感信息

Todoist Token 只能输入应用界面并保存到 macOS Keychain。不要把 Token 写入 Swift 源码、`.plist`、日志、截图或 Git 提交。接入网络时还需要在 App Sandbox 中启用 `Outgoing Connections (Client)`。
