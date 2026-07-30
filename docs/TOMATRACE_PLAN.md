# TomaTrace 产品与工程路线图

> 状态：M1–M9 的个人本机版范围已完成；CloudKit 和公开公证分发因无付费
> Apple Developer Program 账号而不纳入当前交付。
>
> 更新规则：需求、架构或阶段状态发生变化时，必须在对应代码提交中同步更新本文。

## 目标与首版边界

TomaTrace 将在 TomatoBar 的菜单栏番茄钟基础上，提供与 Pomist 同类的个人专注工作流：

1. 从 Todoist 同步项目和未完成任务；
2. 选择 Todoist 任务或“无任务”后开始专注；
3. 记录每次专注的实际时间、番茄数、暂停和备注；
4. 专注结束后可将关联任务标记为完成，并把本次及累计番茄数写入 Todoist；
5. 按天、周、月、任务和项目查看时间与番茄统计；
6. 保留可靠的离线记录，并在网络恢复后重试 Todoist 操作。

首版是 macOS 14+ 的个人应用。保留菜单栏交互、通知、声音、快捷键、登录启动及 `en`、`zh-Hans`、`ko` 本地化。保留 MIT License 和原作者归属。暂不支持团队账号、跨平台客户端、协作统计或自建后端。

## 已确定的产品行为

### 计时

- 工作、短休息和长休息时长可配置；支持开始、暂停、继续、停止、跳过和自动进入下一阶段。
- 可以关联一项 Todoist 任务，也可以无任务专注；不新增独立的本地任务系统。
- 暂停时间不计入专注时间。无论是否完成完整番茄，都保存实际专注时长。
- 不完整番茄按当前工作时长的五分之一向下量化。例如 25 分钟配置下，1–4 分钟为 `0`，5–9 分钟为 `0.2`，20–24 分钟为 `0.8`，完整工作周期为 `1.0`。
- 工作阶段结束时弹出可选的“本次做了什么”备注；休息计时不等待填写即可开始。

### Todoist

- 首版使用用户手动输入的个人 API Token；Token 仅保存到 macOS Keychain。网络层保留认证抽象，以便未来切换 OAuth。
- 默认显示今天和已逾期任务，并支持按项目筛选及搜索全部未完成任务。启动、打开菜单、Todoist 写入成功后和手动刷新时同步；计时过程中不轮询。
- 缓存项目和任务供离线选择。同步失败不得阻止本地计时或 session 落盘。
- 每个关联 session 添加一条评论：`🍅 本次专注：0.4 个番茄`，其后可附用户备注。
- 每项任务维护一条独立汇总评论：`🍅 累计专注：3.2 个番茄`。编辑或删除本地历史后重新计算汇总。
- 完成 Todoist 任务始终由用户点击；成功后提供撤销入口。
- 离线写操作进入 outbox。每条 Sync API command 使用持久化 UUID，重试时复用同一 UUID，避免重复评论或完成操作。

### 记录与统计

- 菜单栏负责快速操作，独立窗口承载统计和历史。
- 统计包含：今天/本周/本月专注时间与番茄数、每日趋势、日历热力图、任务排行、项目排行。
- 历史列表展示 session 时间、实际时长、番茄数、任务、项目、备注和同步状态。
- 用户可以修改历史记录关联的任务或删除记录；统计立即重算，远端评论通过 outbox 最终一致更新。

## 技术方案

应用继续使用 SwiftUI。计时器从当前状态机中拆出可测试的纯 Swift 领域逻辑；迁移完成后移除 `SwiftState`。本地数据使用 SwiftData，图表使用 Swift Charts，最低系统版本调整为 macOS 14。

核心类型及职责：

- `TimerEngine`：阶段、倒计时、暂停和状态转换；不直接访问 UI、网络或数据库。
- `FocusSession`：开始/结束时间、有效秒数、番茄数、备注、关联任务快照和同步状态。
- `FocusSegment`：一次 session 中的运行与暂停区段，为有效时长计算提供可审计依据。
- `TodoistProjectCache` / `TodoistTaskCache`：可离线读取的 Todoist 快照及同步游标。
- `PendingTodoistCommand`：命令 UUID、类型、负载、重试次数、最近错误和状态。
- `TodoistTaskSummary`：任务累计番茄数及远端汇总评论 ID。
- `CredentialStore`：Keychain 的保存、读取和删除接口。
- `TodoistClient`：任务读取、增量同步、评论、完成与撤销完成接口。
- `SessionRepository`：session 的保存、编辑、删除和统计查询接口。

数据流遵循“本地记录优先”：计时结束先原子保存 session，再创建远端命令；网络成功后更新同步状态，失败则保留待重试状态。界面不得因为 Todoist 不可用而丢失 session。

## 实施阶段

### M1：工程安全网（已完成）

- [x] 添加 XCTest Target 和计时核心的特征测试，锁定现有开始、停止、工作/休息切换行为。
- [x] 建立 Debug、Release 命令行构建和测试基线，记录 Xcode 初学者的验证路径。
- [x] 在 Xcode 中完成菜单栏启动、弹窗、开始/停止、工作/休息切换的手工回归。
- 验收：Debug/Release 构建成功，测试能从 Xcode 和命令行运行，现有菜单栏行为无回归。

2026-07-30 自动验证记录：

- Xcode 26.6，macOS arm64，Debug 无签名构建通过；
- Xcode 26.6，macOS arm64，Release 无签名构建通过；
- `TBTimerStateMachineTests` 共 7 项全部通过；
- `.env` 已被 Git 忽略，检查过程未输出或提交 Token；
- 2026-07-30 用户在 Xcode 中确认菜单栏图标、弹窗和开始/停止均正常。

### M2：可测试的计时核心（已完成）

- [x] 引入 `TimerEngine`，替代 UI 与 SwiftState 状态机之间的直接耦合。
- [x] 完成暂停/继续、停止、跳过、自动开始配置和五分之一番茄量化测试。
- [x] 移除 `SwiftState` 依赖，保留菜单栏、通知、声音、快捷键和 URL Scheme 接线。
- 验收：计时状态转换测试通过，应用表现与原版一致，`SwiftState` 可安全移除。

2026-07-30 自动验证记录：

- `TimerEngineTests` 共 11 项通过，测试使用显式时间参数，不需要真实等待；
- 覆盖暂停时间排除、短/长休息、自动开始开关、休息后停止、跳过休息和提前完成保护；
- 25 分钟配置下的五分之一边界及自定义完整周期 `1.0` 番茄均通过；
- Swift Package 依赖图只保留 `LaunchAtLogin` 和 `KeyboardShortcuts`；
- Debug、Release 和运行时启动检查通过。

### M3：本地 session（已完成）

- [x] 引入 SwiftData `FocusSession`、`FocusSegment`、repository 和持久化容器。
- [x] 每次工作阶段停止或完成时先保存 session，再显示可选备注。
- [x] 暂停区段独立记录且不计入有效专注时长；系统严重超时的工作不误记。
- [x] 增加本地历史窗口、备注保存和 session 删除。
- 验收：重启应用后记录仍存在，暂停不计时，短 session 的时长和番茄数正确。

2026-07-30 自动验证记录：

- `SessionRepositoryTests` 5 项通过，包括关闭并重新打开磁盘容器后记录仍存在；
- `FocusSessionTrackerTests` 4 项通过，包括暂停区段、迟到 tick 裁剪和手动开始等待；
- 加上 `TimerEngineTests` 后总计 20 项测试通过；
- session 在结束时先原子保存，备注为空也不会丢失记录；
- Debug、Release、三种本地化及 Debug 应用启动检查通过。

### M4：Todoist 连接（已完成）

- [x] 增加设置界面、Keychain Token 存储、连接测试和清除凭据。
- [x] 增加网络错误分类和脱敏错误，并开启 App Sandbox 出站网络能力。
- 验收：有效 Token 显示账号连接成功；无效或断网时给出可理解提示；Git 和日志中无 Token。

2026-07-30 自动验证记录：

- Todoist API 使用当前 `https://api.todoist.com/api/v1/user` 接口；仓库
  `.env` 中的真实 Token 得到 HTTP 200 和合法用户结构，验证过程未输出
  Token、姓名或邮箱；
- `TodoistClientTests` 6 项通过，覆盖认证请求、两种用户 ID、401、429、
  非法响应和断网分类；错误消息不包含请求或响应正文；
- `TodoistConnectionViewModelTests` 4 项通过，覆盖成功后才保存 Token、
  失败不保存、已存 Token 不回显和断开连接；
- `CredentialStoreTests` 2 项通过，真实完成 Keychain 新增、读取、更新和
  删除；完整测试集共 32 项通过；
- Debug 临时签名包确认包含 App Sandbox 与
  `com.apple.security.network.client`，应用实际启动检查通过；
- Debug 测试、Release 构建及三种本地化文件检查通过，`.env` 仍被 Git
  忽略。

### M5：任务同步与选择（已完成）

- [x] 实现项目、任务和增量游标缓存；增加默认列表、搜索、项目筛选和手动刷新。
- [x] 计时开始时保存任务及项目快照，防止远端改名破坏历史。
- 验收：在线数据正确更新，离线可选缓存任务，无任务模式始终可用。

2026-07-30 自动验证记录：

- 使用 Todoist Sync API v1 完成真实全量与增量同步：全量响应包含合法项目、
  任务和游标，复用游标后得到增量响应；验证仅输出数量和结构，不输出 Token
  或任务内容；
- 项目、任务、同步游标和最后同步时间写入 SwiftData；过期游标遇到 HTTP
  400 时自动回退一次全量同步，失败时继续展示离线缓存；
- 默认列表只显示今天及已逾期任务，搜索覆盖全部未完成任务，并支持项目筛选；
- 开始专注时冻结任务与项目名称快照，后续远端改名不改变历史；
- `TodoistCacheRepositoryTests` 4 项、`TodoistTaskListViewModelTests` 5 项及
  扩展后的网络、session 测试全部通过，完整测试集共 44 项；
- Debug、Release、三种本地化、沙盒网络权限和实际应用启动检查通过。

### M6：双向写回（已完成）

- [x] 实现 session 评论、累计评论、完成/撤销和持久化 outbox。
- [x] 编辑、删除历史后重新计算任务累计番茄，并以幂等命令更新远端。
- 验收：断网重启后命令仍可重试；重复重试不会产生重复评论；手动完成和撤销正确。

2026-07-30 自动验证记录：

- session 和两类 Todoist 评论命令在同一个 SwiftData 事务中保存；备注保存前
  更新尚未发送的 session 评论，应用意外退出后也保留无备注版本等待下次重试；
- 每条 Sync API command 使用持久化 UUID，网络失败和应用重启后原样复用；
  只有服务器返回对应 `sync_status` 后才删除，新增评论缺少远端 ID 映射时继续保留；
- 同一任务只有一条累计评论；新增、编辑或删除本地历史会重算番茄总数并合并
  待发送更新，已同步 session 删除时同时排队删除其独立评论；
- 支持 `item_close` 完成任务及 `item_uncomplete` 撤销；未发送完成操作可直接
  取消，成功完成后移除缓存并触发增量同步；
- 专注结束提示提供“保存并完成 Todoist 任务”一键操作，Todoist 页展示
  待发送/失败数量、撤销和人工重试入口；
- `TodoistOutboxRepositoryTests` 8 项、`TodoistOutboxProcessorTests` 3 项，
  完整测试集共 63 项；覆盖断网磁盘重开、幂等 UUID、命令级错误、远端 ID
  映射、历史编辑/删除和完成/撤销；
- Todoist 写接口遵循当前官方 Sync API v1 的 `note_add`、`note_update`、
  `note_delete`、`item_close`、`item_uncomplete` 协议。为避免污染用户真实
  任务，写入验收使用脱敏 transport fixture；真实 Token 仍只用于只读同步；
- Debug、Release、三种本地化和新增 SwiftData schema 的实际启动检查通过。

### M7：统计分析（已完成）

- [x] 增加独立统计窗口、汇总卡片、趋势、热力图、任务/项目排行及历史管理。
- [x] 所有统计以本地 session 为准，不依赖实时网络。
- 验收：跨日、跨周、跨月边界正确；编辑和删除后所有统计同步变化。

2026-07-30 自动验证记录：

- `StatisticsEngine` 按日拆分跨午夜的有效专注区间，并按本地日历计算今天、
  本周、本月、14 日趋势和 12 周热力图；
- 任务与项目排行使用所有本地 session 的实际时长和番茄数；无网络时结果
  不变；
- 历史窗口支持修改备注、重新关联缓存 Todoist 任务或改为“无任务”，删除
  和改绑会通过既有 outbox 重算远端累计评论；
- 4 项统计边界测试和 2 项历史改绑测试通过。

### M8：Pomist 增强体验（个人版已完成）

- [x] 增加默认关闭的悬浮计时器和全屏休息提示开关，不改变菜单栏默认体验。
- [x] 多窗口显示条件抽成纯策略并覆盖自动测试。
- [ ] iCloud/CloudKit 跨设备同步：需要付费 Apple Developer Program Team、
  CloudKit Container 和 Remote Notifications；用户选择当前不启用，界面不
  暴露无效开关。
- 验收：悬浮窗口仅在计时活动时显示；全屏提示仅在活动休息阶段显示；本地
  session 仍由 SwiftData 可靠保存。

2026-07-30 自动验证记录：

- 3 项窗口策略测试通过，覆盖默认关闭、工作/休息悬浮显示和全屏休息条件；
- Release 应用在隔离的数据目录中实际启动并保持运行，SwiftData store 成功
  建立；结束验证后已停止该测试进程；
- iCloud 被明确列为未来账号条件，而不是用本地开关冒充跨设备同步。

### M9：品牌与个人分发（已完成）

- [x] 应用最终命名为 TomaTrace，Bundle Identifier 为
  `com.linyangfeng.tomatrace`。
- [x] 更新图标、应用名、URL Scheme、版权说明、版本和发布文档。
- [x] 生成可在本机继续通过 Xcode 导出的 Archive。
- [ ] Developer ID 签名和 Apple 公证：需要付费 Apple Developer Program
  账号，仅在将来公开发给其他用户时执行。
- 验收：Debug/Release 可构建，个人 Archive 包含正确身份的双架构
  `TomaTrace.app`；公开分发验收不属于当前个人版范围。

2026-07-30 自动验证记录：

- 新图标源文件为 `Icons/TomaTrace.png`，完整 AppIcon 尺寸已生成并检查；
- `tomatrace://startStop` 品牌 URL 解析测试通过，旧 URL 和未知命令会拒绝；
- 完整测试集 74 项全部通过；Release 无签名构建通过；
- `/tmp/TomaTrace.xcarchive` 生成成功，内含 arm64 与 x86_64 双架构
  `TomaTrace.app` 1.0.0（Build 1），Bundle Identifier、可执行文件和
  `LSUIElement` 均已核对；
- 无付费账号时 Archive 的签名身份和 Team 为空，符合本次个人源码交付边界；
  GitHub Actions 同样仅生成未签名构建检查产物，不宣称可公开分发。

## 测试与交付标准

每个阶段拆成一次只完成一个可验证目标的小步骤。每一步交付都必须写明：

1. 这一步用通俗语言解决什么问题；
2. 修改了哪些文件及关键代码；
3. 在 Xcode 中点击哪里、如何运行；
4. 自动测试和手工验证结果。

自动测试至少覆盖计时状态转换、番茄量化、session 持久化、统计日期边界、Todoist 解码、幂等 outbox 和 Keychain 接口替身。网络测试使用脱敏 fixture 和 mock transport，绝不使用真实 Token。涉及菜单栏、通知、声音、窗口、登录启动或签名的变更还必须在真实应用中手工验证。

完成标准是代码可编译、相关测试全部通过、手工验收通过且本文状态已同步；仅写完代码不算完成。
