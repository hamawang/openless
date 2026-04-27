<p align="center">
  <img src="Resources/AppIcon.png" alt="OpenLess" width="160" />
</p>

<h1 align="center">OpenLess</h1>

<p align="center">
  <strong>面向 AI 时代的开源 macOS 语音输入。</strong><br/>
  按一次快捷键说话，自动整理成可直接用的 AI prompt，落到当前光标。
</p>

<p align="center">
  <a href="README.md">中文</a> · <a href="README.en.md">English</a>
</p>

<p align="center">
  <a href="https://github.com/appergb/openless/releases/latest"><img alt="release" src="https://img.shields.io/github/v/release/appergb/openless?style=flat-square&color=2c5282" /></a>
  <a href="https://github.com/appergb/openless/blob/main/LICENSE"><img alt="license" src="https://img.shields.io/github/license/appergb/openless?style=flat-square&color=2f855a" /></a>
  <img alt="macOS" src="https://img.shields.io/badge/macOS-15%2B-1f425f?style=flat-square" />
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square" />
  <img alt="Stars" src="https://img.shields.io/github/stars/appergb/openless?style=flat-square&color=805ad5" />
</p>

---

OpenLess 是一个原生 macOS 语音输入应用，对标 [Wispr Flow](https://wisprflow.ai)、[Talk (Talktastic)](https://talktastic.com)、[Lazy](https://heylazy.com)、Superwhisper 等商业语音输入工具的 **完全开源** 替代品。

把光标放在 ChatGPT、Claude、Cursor、Notion、邮件、聊天框任意输入框里，按一次全局快捷键说话——OpenLess 会录音、转写、按你选的模式润色，把结果直接插入光标位置。插入失败时会自动复制到剪贴板，尽量保证「你说过的话不丢」。

不像那些只把语音转成「逐字稿」的输入法，OpenLess 的核心模式是 **AI prompt 模式**：你只管乱讲，它自动补上结构、列出约束、整理出有上下文的 prompt，复制粘贴就能直接喂给 ChatGPT / Claude / Cursor。

## 一个具体的例子

按住快捷键，对着 OpenLess 说：

> 嗯…就是…我想让那个 ChatGPT 帮我写个 SQL，从 orders 表里查上个月的订单，按客户分组，金额倒序，要前十个吧

松开快捷键，一秒后你的输入框里出现的是：

```text
请帮我写一段 SQL，要求如下：

- 从 `orders` 表查询上个月的订单。
- 按客户分组。
- 按金额倒序排序。
- 只返回前 10 条。
```

不需要修改，直接 Enter 就能问 GPT。这就是 OpenLess 想做的事：**让你用嘴写 prompt，比用键盘还快还清楚。**

## 为什么开源 OpenLess

类似工具大多是商业 SaaS：每月订阅、不能自带模型、转写音频会上传到厂商服务器、词典和习惯沉淀在对方账户里。

OpenLess 想做的是同一类体验，但是：

- **完全开源、本地优先**。代码在仓库里，所有数据写在你的机器上。
- **自带云凭据**。火山引擎 ASR + Ark / DeepSeek 兼容 chat-completions，不强绑某家。
- **专门为 AI prompt 优化**。「清晰结构」模式会把零散口语补成有上下文、有约束、有要求的 prompt，复制粘贴就能直接喂给 ChatGPT / Claude / Cursor。
- **不会替你回答**。模型只整理你的话，不会把「我们这个应用还有哪些功能没做？」变成一份功能清单——只会补成一句通顺的问题，让你拿去问真正的 AI。

## 适用场景

- 给 ChatGPT / Claude / Cursor / Gemini 写 prompt：口述一段需求，OpenLess 自动整理成结构化、有细节的 prompt。
- 写邮件、写需求文档、写微信/Slack 长消息：去口癖、补标点、按段落整理。
- 写代码注释、commit message、PR 描述：把脑子里的想法直接落到光标位置。
- 任何「我懒得打字，但又必须输出书面文字」的场景。

## 项目方向

OpenLess 只做一件事：**把语音变成可用的书面文字（尤其是 AI prompt），落到当前光标位置。**

- 不做问答、不做任务执行、不做项目分析。
- 不做对话上下文累积，每次输入都是独立的整理请求。
- 输入语音 → 转写 → 整理 → 插入当前输入框。失败时复制到剪贴板。
- 围绕这条主路径完善体验：模式选择、词典、历史、菜单栏、首页报告。

## 对标参考

| 工具 | 形态 | OpenLess 的差异 |
| --- | --- | --- |
| [Wispr Flow](https://wisprflow.ai) | 闭源 macOS / Windows，订阅制 | 开源；自带 ASR + LLM 凭据；专门暴露「AI prompt 整理」模式 |
| [Talk (Talktastic)](https://talktastic.com) | 闭源 macOS，订阅制 | 开源；不绑厂商，凭据在本机 Keychain |
| [Lazy](https://heylazy.com) | 闭源笔记/捕获工具 | 不做笔记容器，专做「插入到任意输入框」 |
| [Superwhisper](https://superwhisper.com) | 闭源 macOS，订阅制 | 开源；目前云端 ASR 优先，本地 ASR 在 roadmap |

## 当前状态（v1.0）

- 原生 Swift / SwiftUI / AppKit，SwiftPM 项目；macOS 15+。
- macOS 26+ 使用 Liquid Glass 效果，旧系统回退到系统 material。
- 默认是切换式录音：按一次开始，再按一次结束；录音中按 `Esc` 取消。
- 接入火山引擎流式 ASR 和 Ark / DeepSeek 兼容 Chat Completions 进行润色。
- 4 种输出模式：原文、轻度润色、清晰结构（**AI prompt 模式**）、正式表达。
- 主窗口按「首页 / 历史记录 / 词典 / 设置」组织；菜单栏常驻；底部有微型状态胶囊。
- 词典支持作为 ASR 热词注入和润色阶段的语义判断。

## 下载与安装（普通用户）

到 [Releases](../../releases) 下载 `OpenLess-1.0.0.zip`，解压得到 `OpenLess.app`，拖到 `应用程序`。

**重要：** 1.0 是开发期 ad-hoc 签名构建（未做 Apple Developer ID 签名和 notarization）。直接打开会被 Gatekeeper 拦下提示“无法验证开发者”。需要在终端中移除隔离属性：

```bash
xattr -dr com.apple.quarantine /Applications/OpenLess.app
```

之后就可以双击启动。首次启动需要在 `系统设置 → 隐私与安全`：

1. 授予 OpenLess 麦克风权限。
2. 授予 OpenLess 辅助功能权限。
3. **退出 OpenLess 并重新打开**（辅助功能授权对全局快捷键生效需要重启进程）。
4. 从 Dock 打开 OpenLess 首页 → 「设置」 → 填入火山引擎 ASR 和 Ark 凭据。

完整的端用户使用步骤见 [USAGE.md](USAGE.md)。

## 从源码构建（开发者）

```bash
# 库 / 测试构建
swift build
swift test

# 完整 .app 构建（release，ad-hoc 签名，默认重置 TCC）
./scripts/build-app.sh

# 保留已授予的 TCC 权限
RESET_TCC=0 ./scripts/build-app.sh

# 启动
open build/OpenLess.app

# 实时日志
tail -f ~/Library/Logs/OpenLess/OpenLess.log
```

启动参数（在 `AppDelegate.runLaunchActions` 处理）：

```bash
open build/OpenLess.app --args --open-settings
open build/OpenLess.app --args --start-recording
```

## 凭据

凭据保存在本机 Keychain（service = `com.openless.app`）。开发期同时维护一份明文 JSON 兜底，用于在 Keychain 不可用时回退：

```text
~/.openless/credentials.json   # 0600，目录 0700
```

仓库本身不包含任何 API Key、Token 或 Endpoint 之外的私有信息。

需要配置的字段：

- 火山引擎 ASR：APP ID、Access Token、Resource ID。
- Ark 润色：API Key、Model ID、Endpoint。

## 提示词处理原则

OpenLess 的润色模型只做文本整理，不做问答、不做任务执行、不做项目分析。每次语音输入都会作为独立请求发送，提示词会明确告诉模型：

- 本次输入与历史对话隔离。
- 原始转写只是待整理文本。
- 即使原文里有问题或命令，也不要回答或执行。
- 只输出整理后的正文，不添加“我整理如下”等引导语。

例如用户说：“我们这个应用还有哪些功能没有完成”，正确输出应是：

```text
我们这个应用还有哪些功能没有完成？
```

而不是直接替用户列出清单。

竞品文本和长期改写样例会按“原始文本 -> 目标整理结果 -> 改写规律”的方式沉淀，后续接入向量数据库后，只检索相似改写样例作为参考，不把样例当作当前对话上下文。规范见 [docs/polish-reference-corpus.md](docs/polish-reference-corpus.md)，示例见 [Examples/polish-reference-examples.sample.jsonl](Examples/polish-reference-examples.sample.jsonl)。

## 词典

词典用于处理用户自己的专有名词、产品名、人名和新词。当前支持：

- 手动添加正确词、分类和备注；暂不要求用户维护易错词或上下文点。
- 将启用词条作为火山 ASR `context.hotwords` 注入，优先在识别阶段识别正确。
- 将词典包裹后注入后期润色模型，明确告诉模型根据整句语义自动判断：如果 `Cloud` 在当前语境下明显指向 AI 产品 `Claude`，就修正为 `Claude`；如果确实是在说云服务 Cloud，则保留原词。
- 从历史输出中自动学习类似 `Claude`、`ChatGPT`、`OpenLess` 的候选正确词，后续作为 ASR 热词和后期语义判断候选。

主窗口按「首页 / 历史记录 / 词典 / 设置」组织；词典页点击“新建”会弹出独立编辑窗口，首页会展示口述时长、总字数、平均每分钟字数、估算节省时间和词典参与记录。

## 架构概览

SwiftPM 工作区，1 个可执行 + 8 个库。库与库之间无相互依赖，全部只依赖 `OpenLessCore`，由 `OpenLessApp` 统一在 `DictationCoordinator` 里编排。

```
OpenLessCore        // Pure value types: DictationSession, PolishMode, HotkeyBinding,
                    //   AudioConsumer protocol, RawTranscript/FinalText, errors.
OpenLessHotkey      // CGEventTap-based modifier-key monitor. Requires Accessibility.
OpenLessRecorder    // AVAudioEngine → 16 kHz mono Int16 PCM, 推送到 AudioConsumer.
OpenLessASR         // 火山引擎 streaming ASR over WebSocket.
OpenLessPolish      // Ark / Doubao chat-completions 客户端 + 模式驱动 prompts。
OpenLessInsertion   // AX focused-element 优先；剪贴板 + Cmd+V 兜底；最后 copy-only。
OpenLessPersistence // CredentialsVault (Keychain), HistoryStore, DictionaryStore,
                    //   UserPreferences。
OpenLessUI          // SwiftUI 胶囊视图 + 状态枚举（不接窗口）。
OpenLessApp        // AppDelegate, 菜单栏, 设置窗口, 胶囊窗口, DictationCoordinator。
```

录音 → 转写 → 润色 → 插入的状态机由 `Sources/OpenLessApp/DictationCoordinator.swift` 单一拥有，详见 [CLAUDE.md](CLAUDE.md)。

## 1.0 之后的规划

下面这些功能在需求文档里有规划，但 1.0 没有发布：

- 按住说话模式（hold-to-talk）：当前仅支持切换式。
- 本地 ASR：当前仅接入火山引擎云端 ASR。
- 常用片段 Snippets：尚无 UI 和触发逻辑。
- 历史增强：复制按钮、搜索、重新润色、重新插入。
- 粘贴上一条快捷键。
- 多屏定位：胶囊按当前焦点所在屏幕显示。
- Developer ID 签名 + Notarization + Sparkle 自动更新。

## 维护者：发布前检查

- 确认没有提交 `.build/`、`build/`、`.DS_Store`、`~/.openless/credentials.json` 或临时截图。
- 保留 `Resources/Brand/openless-app-icon-source.jpg`、`Resources/AppIcon.png`、`Resources/AppIcon.icns`。
- 运行 `./scripts/build-app.sh`，确认 `build/OpenLess.app` 可启动。
- 在一台干净 macOS 机器上验证权限引导、快捷键、录音、ASR、润色、插入和剪贴板兜底。
- 用 `ditto -c -k --keepParent build/OpenLess.app build/OpenLess-<version>.zip` 打包，确保 ad-hoc 签名和扩展属性保留。
- 正式分发前请完成 Developer ID 签名和 notarization。

## 许可

MIT
