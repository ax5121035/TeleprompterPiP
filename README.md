# 悬浮提词器（iOS）

一款运行在 iPhone 上的本地提词器，利用系统画中画（PiP）能力，把滚动文案悬浮在相机或任意 App 之上。专为房产测评口播工作流设计。

**零成本方案**：免费 Apple ID 签名 + AltStore 自动续签，不需要 Mac，不需要付费开发者账号。

---

## 一、它能做什么

- 悬浮提词：点「启动悬浮提词」后切到相机 App，提词窗浮在取景画面上
- 悬浮窗内控制：播放 / 暂停 / 快进（系统 PiP 控制条）
- App 内实时调整：字号、滚动速度、行距、镜像、文字颜色、背景颜色——改完悬浮窗立即更新
- 测评模板：户型 / 采光 / 噪音 / 交付 / 配套 五套口播模板，一键套用
- 稿件库：本地保存常用口播稿
- 智能断句：按句末标点自动分行

## 二、能不能用——先看设备

| 条件 | 要求 |
|---|---|
| 系统 | iOS 15.0 及以上 |
| 设备 | iPhone（真机，模拟器不支持 PiP） |
| Mac | 不需要（编译走 GitHub 云） |
| 开发者账号 | 不需要（免费 Apple ID 即可） |

---

## 三、从源码到装进手机的完整流程

### 第 1 步：把代码传到 GitHub

1. 注册 / 登录 GitHub（https://github.com）
2. 新建一个**私有仓库**（ repositories → New → 填名字如 `teleprompter`，选 Private → Create）
3. 把本项目整个 `TeleprompterPiP` 文件夹里的文件上传到仓库（网页端 Add file → Upload files，全选拖进去 → Commit）
   - 注意：`.github` 是隐藏文件夹，网页上传时要确保它也被传上去（可用 GitHub Desktop 或命令行更稳妥）

### 第 2 步：云编译生成安装包

1. 打开仓库，点顶部 **Actions** 标签
2. 左侧选 **Build Unsigned IPA**，点右侧 **Run workflow** → 绿色按钮 **Run workflow**
3. 等待约 3–8 分钟（首次会慢些），跑完后点进这次任务，往下拉到 **Artifacts**
4. 下载 `TeleprompterPiP-unsigned`（是个 zip），解压得到 `TeleprompterPiP.ipa`
5. 把这个 ipa 传到你的 iPhone（AirDrop / 微信文件传输助手 / 网盘都行，存到「文件」App 里）

### 第 3 步：电脑装 AltStore（Windows 可用）

1. Windows 电脑安装 **iTunes**（必须是微软商店版或 Apple 官网版，不要装第三方修改版）
2. 去 AltStore 官网 https://altstore.io 下载 **AltServer**（Windows 版）
3. 安装并运行 AltServer，它会出现在任务栏托盘图标里
4. 用数据线把 iPhone 连到电脑，解锁手机，点「信任此电脑」
5. 点托盘里的 AltServer 图标 → **Install AltStore** → 选你的 iPhone
6. 弹出输入框，填你的 **Apple ID 和密码**（就是平时登 App Store 的账号；建议专门注册一个新号，开启两步验证的话要生成「应用专用密码」）
7. 等几秒，手机主屏幕出现 AltStore，安装完成

### 第 4 步：用 AltStore 安装提词器

1. 手机打开 AltStore → 底部 **My Apps** → 左上角 **+**
2. 选择第 2 步传到手机的 `TeleprompterPiP.ipa`
3. 输入 Apple ID 密码，开始签名安装
4. 装好后首次打开：iOS 会提示「不受信任的企业级开发者」
   → 去 **设置 → 通用 → VPN 与设备管理** → 点你的 Apple ID → **信任**

---

## 四、7 天续签——一劳永逸的设置

免费 Apple ID 签名的 App **7 天后会过期打不开**，必须重签。AltStore 能自动做这件事，但要满足两个条件：

1. **电脑开着 AltServer**
2. **手机和电脑在同一个 WiFi**，且最好连着数据线（最稳）

满足后：AltStore 会在后台自动在你连上 WiFi 时刷新签名，你几乎无感。

手动续签方法：打开 AltStore → My Apps → 点「Refresh All」，几秒完成。

> 关于「7 天重签」的真相：这就是免费方案的固定成本。如果哪天你觉得烦了，唯一的根治办法是花 $99/年开开发者账号走 TestFlight（那时再来找我，我给你改配置）。

---

## 五、使用流程（录视频时）

1. 打开提词器 App，粘贴或选一个测评模板
2. 调好字号、速度（建议先点「启动」前用预览卡看一眼）
3. 点 **启动悬浮提词**
4. 回到主屏幕，打开 **相机** App，切到视频模式
5. 提词窗浮在取景画面上，拖动可调整位置
6. 开始录制
7. 需要暂停/继续：直接点悬浮窗上的系统控制条
8. 需要改字号/速度：切回提词器 App 调整，悬浮窗实时更新，再切回相机继续录

---

## 六、已知限制（先讲清楚，免得踩坑）

| 限制 | 说明 |
|---|---|
| 悬浮窗是视频小窗 | 苹果只允许 PiP 形式悬浮，是半透明小窗口，不能做成完全透明的文字叠加层 |
| 后台推帧 | 切到相机后靠后台计时器推帧；部分机型系统对后台限制严格时，滚动可能变慢。若遇到，保持数据线连接或降低速度 |
| 宿主 App 不能杀掉 | 切到相机时提词器 App 在后台运行，不要从后台列表划掉它，否则悬浮窗消失 |
| 控制粒度 | 悬浮窗内只有系统提供的播放/暂停/快进；逐句跳转和参数调整要切回 App |
| 未上架 App Store | 通过 AltStore 侧载安装，仅个人使用 |

---

## 七、出问题怎么办

- **点启动没反应**：确认是真机、iOS 15+、文案非空；先看预览卡有没有显示出文字
- **悬浮窗启动失败**：检查「设置 → 通用 → 后台 App 刷新」是否允许本 App；重新装一次
- **7 天后打不开**：AltStore → My Apps → Refresh All
- **编译失败**：去 Actions 任务页看红色 X 的日志，把报错文字发给我

---

## 八、给维护者的技术备忘

- 编译：`xcodegen generate` → `xcodebuild -sdk iphoneos CODE_SIGNING_ALLOWED=NO`
- 输出 unsigned ipa 供 AltStore 重签名，这是零成本方案的关键
- PiP 核心：`AVPictureInPictureController` + `AVSampleBufferDisplayLayer`，文字用 CoreGraphics 绘制进 CVPixelBuffer
- **必须 `UIGraphicsPushContext(ctx)`**：`NSString.draw` 依赖当前 UIKit 图形上下文，不 push 会在后台推帧时画出黑屏
- **时间戳每帧 1/fps（1/30 秒）**：用 `CMTime(value:1, timescale:fps)`；早期误用 1/600 会让时间流速失真、PiP 自动收起
- **时间轴用 `.positiveInfinity`**：`CMTime` 没有 `.infinity` 这个属性（Apple 只提供 positiveInfinity/negativeInfinity），写 `.infinity` 会编译失败；提词是连续流，有限区间走到头 PiP 会退出
- `skipByInterval` 只实现 completion 版`@escaping () -> Void`，**不要加 `@Sendable`**（Swift 5.9 + iOS 15 下签名不匹配），也不要实现 iOS 16 的 async 版，否则 availability 冲突
- 后台推帧用 `Timer` + `.common` RunLoop mode，配 0.5s 心跳防止 PiP 被系统判为结束
- 启动前必须先 enqueue 至少一帧，否则 PiP 静默拒绝启动
- Bundle ID：`com.feige.teleprompter.pip`
