# OpenLess

OpenLess 是一个原生 macOS 语音输入应用：把光标放在任意输入框，按下全局快捷键说话，OpenLess 会录音、转写、轻度整理，并把结果插入当前输入位置。插入失败时会自动复制到剪贴板，尽量保证“用户说过的话不丢”。

## 当前状态

- 原生 Swift / SwiftUI / AppKit，SwiftPM 项目。
- 支持 macOS 15+；macOS 26+ 使用 Liquid Glass 效果，旧系统回退到系统 material。
- 默认是切换式录音：按一次开始，再按一次结束；录音中按 `Esc` 取消。
- 支持火山引擎流式 ASR 和 Ark / DeepSeek 兼容 Chat Completions 润色。
- 支持 4 种输出模式：原文、轻度润色、清晰结构、正式表达。
- 支持 Dock 主窗口、菜单栏控制、底部微型状态胶囊、首页报告、历史记录、词典、设置和剪贴板兜底。

## 运行方式

```bash
./scripts/build-app.sh
open build/OpenLess.app
```

开发期使用 ad-hoc 签名。每次重新构建后，脚本默认会重置辅助功能、麦克风、AppleEvents 和 ListenEvent 权限，确保 macOS 不继续引用旧二进制授权。

首次启动后：

1. 在系统设置中授予 OpenLess 辅助功能权限和麦克风权限。
2. 退出 OpenLess。
3. 重新打开 `build/OpenLess.app`。
4. 从 Dock 打开 OpenLess 首页，在「设置」里填写火山引擎 ASR 和 Ark 凭据。

实时日志：

```bash
tail -f ~/Library/Logs/OpenLess/OpenLess.log
```

## 凭据

开发期凭据保存在本机：

```text
~/.openless/credentials.json
```

文件权限会设置为 `0600`，目录权限为 `0700`。当前没有把 API Key 写入仓库、日志或公开配置。正式发布前建议切换到稳定开发者签名 + Keychain。

需要配置：

- 火山引擎 ASR：APP ID、Access Token、Resource ID。
- Ark 润色：API Key、Model ID、Endpoint。

## 图标

图标源文件放在：

```text
Resources/Brand/openless-app-icon-source.jpg
```

生成脚本：

```bash
swift scripts/generate-app-icon.swift
```

脚本会输出：

```text
Resources/AppIcon.png
Resources/AppIcon.icns
Resources/Brand/openless-standard-image.png
```

`Resources/Brand/openless-standard-image.png` 是 1024×1024 的标准品牌图；`scripts/build-app.sh` 会自动生成图标并把 `AppIcon.icns` 写入 `.app` bundle。

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

## 尚未完成的功能

- 按住说话模式：当前是切换式录音，尚未实现真正的 hold-to-talk。
- 本地 ASR：当前主要接入火山引擎云端 ASR，本地模型路由还没有实现。
- 常用片段 Snippets：需求中有规划，当前没有 UI 和触发逻辑。
- 历史增强：当前能查看和清空历史，尚未支持复制按钮、搜索、重新润色、重新插入。
- 粘贴上一条快捷键：需求中有规划，当前没有独立快捷键。
- 多屏定位：胶囊目前优先显示在主屏底部，尚未按当前输入焦点所在屏幕定位。
- 稳定签名与 Keychain：开发期使用 ad-hoc 签名和本机受保护文件，正式发布前需要开发者签名、notarization 和 Keychain 方案。
- 自动更新和发布流水线：尚未接入 Sparkle、GitHub Release 自动打包或 notarization 流程。
- 更完整测试环境：当前 `swift build` 可验证编译；本机 CommandLineTools 环境缺少 `XCTest`，需要完整 Xcode 环境后跑 `swift test`。

## GitHub 发布前检查

- 确认没有提交 `.build/`、`build/`、`.DS_Store`、本地凭据或临时截图。
- 保留 `Resources/Brand/openless-app-icon-source.jpg`、`Resources/AppIcon.png`、`Resources/AppIcon.icns`。
- 运行 `./scripts/build-app.sh`，确认 `build/OpenLess.app` 可启动。
- 在一台干净 macOS 机器上验证权限引导、快捷键、录音、ASR、润色、插入和剪贴板兜底。
- 正式分发前完成 Developer ID 签名和 notarization。
