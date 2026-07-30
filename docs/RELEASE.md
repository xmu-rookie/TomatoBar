# TomaTrace 发布清单

## 发布身份

- 产品名：`TomaTrace.app`
- Bundle Identifier：`com.linyangfeng.tomatrace`
- URL Scheme：`tomatrace://`
- 当前版本：`1.0.0`（Build `1`）
- 最低系统：macOS 14

Target 和 Scheme 仍叫 `TomatoBar`，不影响最终应用名。

## 发布前验证

在 Xcode 顶部选择 `TomatoBar > My Mac`：

1. 按 `Cmd-U`，确认全部测试为绿色；
2. 按 `Cmd-R`，检查菜单栏、计时、Todoist、历史、统计和可选窗口；
3. 退出 Debug 版本，执行 `Product > Archive`；
4. 在 Organizer 选择 Archive，先运行 `Validate App`。

不要把 `.env`、Todoist Token、证书或公证密码加入 Archive 或 Git。

## 只安装到自己的 Mac

在 Organizer 中选择 `Distribute App > Copy App`，导出后把
`TomaTrace.app` 拖入 `/Applications`。第一次运行后完成一次计时，并重新
连接 Todoist；新 Bundle Identifier 不会读取旧 TomatoBar 的 Keychain 和
沙盒数据。

GitHub Actions 产物不签名，只适合构建检查，不等同于公开发行签名。

2026-07-30 已通过命令行生成并检查个人版 Archive：

```text
/tmp/TomaTrace.xcarchive
```

它包含双架构 `TomaTrace.app`（Apple Silicon 与 Intel），版本、Bundle
Identifier 和可执行文件名均已验证。`/tmp` 会被系统清理；需要长期保留时，
仍应按上面的 Organizer 步骤导出到自己的文件夹。

## 发给其他用户

需要付费 Apple Developer Program 账号和 `Developer ID Application`
证书：

1. `Xcode > Settings > Accounts` 登录账号；
2. `TARGETS > TomatoBar > Signing & Capabilities` 选择 Team；
3. 保持 Hardened Runtime 和 App Sandbox；
4. `Product > Archive`；
5. `Distribute App > Developer ID > Upload`；
6. 等待公证完成，再导出 `Notarized App`；
7. 在另一台未参与开发的 Mac 上验证首次启动和 Gatekeeper。

可用以下命令检查导出的包：

```bash
codesign --verify --deep --strict --verbose=2 TomaTrace.app
spctl --assess --type execute --verbose=2 TomaTrace.app
```

## iCloud

iCloud/CloudKit 还要求 Team 管理员创建
`iCloud.com.linyangfeng.tomatrace` Container，并启用 iCloud、CloudKit 和
Remote Notifications。CloudKit schema 在开发环境验证后还要在 CloudKit
Console 提升到 Production。当前用户没有付费开发者账号，因此个人版明确不
包含 iCloud 同步；本地记录、统计和 Todoist 集成不受影响。

## 许可证

公开发行包和源码必须保留根目录 `LICENSE`、TomatoBar 原作者归属以及现有
声音素材许可说明。
