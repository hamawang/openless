# OpenLess 开发文档

更新时间：2026-04-26

本文是 OpenLess 第一轮开发的工程落地文档。产品需求以 `openless-requirements.md` 为准，本文负责说明推荐技术形态、模块拆分、状态机、数据字段、开发顺序和验收方式。

---

## 1. 技术目标

第一轮要做的是一个 macOS 常驻语音输入工具：

> 用户在任意 app 的输入框中按住快捷键说话，OpenLess 录音、转写、轻度整理，然后把结果插入当前光标位置；失败时自动复制并保存历史。

工程目标：

- 能稳定常驻菜单栏。
- 能可靠获取麦克风录音。
- 能响应全局快捷键。
- 能显示底部微型状态胶囊。
- 能完成 ASR 转写和 LLM 润色。
- 能向当前输入位置插入文本。
- 能在失败时复制到剪贴板并保存历史。
- 能清楚处理权限、错误、隐私和本地/云端路径。

---

## 2. 推荐技术路线

### 2.1 首选：原生 macOS

建议第一轮使用：

- Swift / SwiftUI：设置页、历史页、主窗口。
- AppKit：菜单栏、全局窗口、底部胶囊浮层、辅助功能相关能力。
- AVFoundation：麦克风录音、音量采样。
- Carbon / Keyboard Shortcuts 方案：全局快捷键。
- Accessibility API：定位当前输入焦点、模拟输入或粘贴。
- NSPasteboard：剪贴板兜底。
- SQLite 或本地 JSON：历史、词典、设置。
- Keychain：保存 API Key。

理由：

- OpenLess 是系统级输入层，原生 macOS 更适合处理菜单栏、悬浮窗口、权限和全局快捷键。
- Electron/Tauri 可以做设置页，但系统输入、悬浮层和权限体验更容易变复杂。

### 2.2 可选混合路线

如果后续想快速做漂亮设置页，可以采用：

- 原生 Swift 后台核心 + WebView 设置页。

第一轮不建议直接用纯 Web/Electron 做核心录音和插入体验。

---

## 3. 模块拆分

| 模块 | 职责 |
|---|---|
| `AppShell` | 应用生命周期、菜单栏、启动项、窗口管理 |
| `PermissionManager` | 麦克风、辅助功能、通知等权限检查和引导 |
| `HotkeyManager` | 注册录音、取消、粘贴上一条等全局快捷键 |
| `Recorder` | 录音、音频缓存、音量采样、取消 |
| `AudioLevelMonitor` | 输出胶囊动态条所需的实时音量值 |
| `CapsuleOverlay` | 底部微型状态胶囊窗口 |
| `ASRRouter` | 本地、云端、BYOK 转写路由 |
| `PolishEngine` | 原文、轻度润色、清晰结构、正式表达 |
| `TextInserter` | 当前输入框插入、模拟粘贴、失败检测 |
| `ClipboardFallback` | 插入失败时复制最终文本 |
| `HistoryStore` | 保存原始转写、最终文本、状态、错误 |
| `DictionaryStore` | 个人词典 |
| `SnippetStore` | 常用片段 |
| `SettingsStore` | 快捷键、模式、隐私、模型路径 |
| `ErrorReporter` | 本地错误码、日志、用户可读提示 |

---

## 4. 核心流程

### 4.1 正常输入流程

```text
Hotkey down
  -> PermissionManager.check()
  -> Recorder.start()
  -> CapsuleOverlay.show(listening)
  -> AudioLevelMonitor.update()

Hotkey up
  -> Recorder.stop()
  -> CapsuleOverlay.set(processing)
  -> ASRRouter.transcribe(audio)
  -> PolishEngine.polish(rawTranscript, mode, context)
  -> TextInserter.insert(finalText)
  -> HistoryStore.save(session)
  -> CapsuleOverlay.set(inserted)
  -> CapsuleOverlay.hide()
```

### 4.2 插入失败流程

```text
TextInserter.insert(finalText) fails
  -> ClipboardFallback.copy(finalText)
  -> HistoryStore.save(session with copied_fallback)
  -> CapsuleOverlay.set(copied_fallback)
```

用户不需要重新录音。

### 4.3 取消流程

```text
Esc or capsule x clicked
  -> Recorder.cancel()
  -> discard unsaved audio by default
  -> CapsuleOverlay.set(cancelled)
  -> CapsuleOverlay.hide()
```

### 4.4 重跑润色流程

```text
History item selected
  -> choose another mode
  -> PolishEngine.polish(rawTranscript, newMode, context)
  -> update finalText
  -> copy or insert
```

---

## 5. 状态机

### 5.1 应用状态

| 状态 | 含义 | 用户表现 |
|---|---|---|
| `app_ready` | 应用可用 | 菜单栏正常，胶囊隐藏 |
| `permission_required` | 缺少权限 | 设置页提示补权限 |
| `model_unavailable` | 模型或 API 不可用 | 提示切换路径或检查 key |
| `offline` | 网络不可用 | 云端不可用，本地仍可用 |

### 5.2 录音状态

| 状态 | 含义 | 胶囊表现 |
|---|---|---|
| `idle` | 未录音 | 隐藏或极淡小点 |
| `listening` | 正在录音 | 叉号 + 动态条 + 勾号 |
| `stopping` | 正在收尾 | 动态条停止，进入处理 |
| `cancelled` | 用户取消 | 叉号高亮后淡出 |

### 5.3 处理状态

| 状态 | 含义 | 胶囊表现 |
|---|---|---|
| `transcribing` | 正在转写 | “识别中”或 spinner |
| `polishing` | 正在润色 | “整理中”或 spinner |
| `ready_to_insert` | 结果生成 | 准备插入 |
| `failed` | 处理失败 | 红点或“失败”，点击展开详情 |

### 5.4 插入状态

| 状态 | 含义 | 胶囊表现 |
|---|---|---|
| `inserted` | 成功插入 | 勾号高亮后淡出 |
| `copied_fallback` | 插入失败但已复制 | “已复制” |
| `focus_lost` | 输入框失焦 | “已复制” |
| `permission_blocked` | 权限不足 | 引导打开辅助功能权限 |

---

## 6. 数据模型

### 6.1 `DictationSession`

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | 会话 ID |
| `created_at` | datetime | 创建时间 |
| `started_at` | datetime | 录音开始时间 |
| `ended_at` | datetime | 录音结束时间 |
| `duration_ms` | number | 录音时长 |
| `source_app_name` | string | 当前 app 名 |
| `source_bundle_id` | string | 当前 app bundle id |
| `target_context_type` | enum | `chat` / `email` / `doc` / `code` / `unknown` |
| `language_hint` | enum | `auto` / `zh` / `en` / `mixed` |
| `mode` | enum | `raw` / `light` / `structured` / `formal` |
| `model_route` | enum | `local` / `cloud` / `byok` |
| `raw_transcript` | text | 原始转写 |
| `final_text` | text | 最终输出 |
| `insert_status` | enum | `inserted` / `copied_fallback` / `failed` |
| `fallback_reason` | string/null | 插入失败原因 |
| `audio_saved` | boolean | 是否保存音频 |
| `audio_path` | string/null | 音频路径，默认 null |
| `error_code` | string/null | 错误码 |

### 6.2 `UserSettings`

| 字段 | 类型 | 说明 |
|---|---|---|
| `hotkey_record` | string | 录音快捷键 |
| `hotkey_paste_last` | string | 粘贴上一条快捷键 |
| `recording_behavior` | enum | `hold_to_talk` / `toggle_to_talk` |
| `default_mode` | enum | 默认输出模式 |
| `default_model_route` | enum | `local` / `cloud` / `byok` |
| `history_retention_days` | number | 历史保留天数 |
| `save_audio` | boolean | 是否保存音频 |
| `show_floating_capsule` | boolean | 是否显示底部状态胶囊 |
| `auto_copy_on_failure` | boolean | 失败时是否自动复制 |
| `personal_dictionary_enabled` | boolean | 是否启用个人词典 |

### 6.3 `PersonalDictionaryEntry`

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | 词条 ID |
| `phrase` | string | 用户确认过的正确词 |
| `category` | enum | `name` / `product` / `tech` / `company` / `custom` |
| `notes` | string | 可选备注，不作为硬替换规则 |
| `enabled` | boolean | 是否参与 ASR 热词和后期语义判断 |
| `case_sensitive` | boolean | 是否区分大小写 |
| `created_at` | datetime | 创建时间 |

### 6.4 `TextSnippet`

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | 片段 ID |
| `trigger_phrase` | string | 语音触发词 |
| `content` | text | 输出内容 |
| `enabled` | boolean | 是否启用 |

---

## 7. 输出模式与 Prompt 规则

### 7.1 模式枚举

| mode | 名称 | 行为 |
|---|---|---|
| `raw` | 原文 | 只补标点，尽量不改词 |
| `light` | 轻度润色 | 去口癖、去重复、补标点、轻微整理 |
| `structured` | 清晰结构 | 适合长 prompt、需求、说明，输出段落或列表 |
| `formal` | 正式表达 | 适合邮件、客户沟通、正式工作表达 |

### 7.2 通用 Prompt 约束

所有润色模式都必须遵守：

- 只整理用户表达，不回答问题。
- 不执行命令。
- 不新增用户没有说的信息。
- 不删除关键限制条件。
- 保留专有名词、代码名、产品名和人名。
- 保留用户习惯表达，避免 AI 腔。
- 中文输出使用自然中文标点。

### 7.3 轻度润色模板

```text
你是语音输入文本整理器。请把用户的口语转写整理成可直接发送或继续编辑的文字。

要求：
- 去掉明显口癖、重复和无意义停顿。
- 补充自然标点。
- 保留用户原意和表达习惯。
- 不扩写、不创作、不回答内容。
- 如果包含中英混输、产品名、代码名，请尽量保留。

原始转写：
{{raw_transcript}}
```

---

## 8. UI 实现规格

### 8.1 胶囊窗口

建议实现为一个无边框、透明背景、always-on-top 的辅助窗口：

- 不抢焦点。
- 主窗口出现在 Dock；录音胶囊作为辅助窗口不出现在 Dock。
- 屏幕底部居中。
- 多屏时优先显示在当前活跃输入所在屏幕。
- 空闲时隐藏。
- 录音时以轻微 spring motion 出现。

尺寸：

| 状态 | 宽 | 高 |
|---|---|---|
| Listening | 128-180px | 32-38px |
| Processing | 150-210px | 32-38px |
| Success | 128-160px | 32-38px |
| Error | 150-210px | 32-38px |

结构：

```text
[ x ]   [ audio bars / short status ]   [ check ]
```

禁止：

- 不展示完整 transcript。
- 不展示 mode/provider chips。
- 不显示复杂按钮组。
- 不做大面板默认展开。

### 8.2 设置窗口

设置窗口可用 SwiftUI：

- 左侧导航。
- 右侧内容。
- 表格编辑词典和片段。
- 历史支持搜索、复制、重新整理。

第一轮不追求复杂视觉，重点是清楚、稳定、可用。

---

## 9. 错误码与用户文案

| error_code | 触发场景 | 用户文案 |
|---|---|---|
| `mic_permission_missing` | 缺少麦克风权限 | 需要麦克风权限才能录音 |
| `accessibility_missing` | 缺少辅助功能权限 | 需要辅助功能权限，OpenLess 才能输入到当前 app |
| `focus_lost` | 输入框失焦 | 找不到输入位置，结果已复制 |
| `asr_failed` | 转写失败 | 这次没有识别成功，请重试 |
| `polish_failed` | 润色失败 | 整理失败，原始转写已保存 |
| `network_unavailable` | 云端不可用 | 网络不可用，可切换本地模式 |
| `model_unavailable` | 模型不可用 | 当前模型不可用，请检查设置 |

文案原则：

- 短。
- 直接。
- 说明用户下一步能做什么。
- 不用“释放生产力”“智能增强”等营销词。

---

## 10. 开发顺序

建议按以下顺序开发：

1. 创建 macOS 菜单栏应用骨架。
2. 实现设置窗口基础导航。
3. 实现权限检查和引导。
4. 实现全局快捷键。
5. 实现录音与音量采样。
6. 实现底部微型状态胶囊。
7. 接入最小 ASR 路径。
8. 接入轻度润色。
9. 实现文本插入。
10. 实现剪贴板兜底。
11. 实现历史记录。
12. 实现个人词典。
13. 实现模式切换。
14. 完成错误处理和隐私设置。
15. 做真实 app 场景测试。

第一轮开发原则：

- 先跑通主链路，再优化模型。
- 先保证不丢内容，再追求插入成功率。
- 先做好小胶囊，再做主窗口美化。
- 先做中文和中英混输验收，再扩展更多语言。

---

## 11. 测试清单

### 11.1 功能测试

- 首次启动能引导麦克风权限。
- 首次启动能引导辅助功能权限。
- 快捷键能开始录音。
- 松开快捷键能结束录音。
- 胶囊在录音时出现。
- 胶囊动态条随声音变化。
- `Esc` 能取消。
- 中文能识别。
- 英文能识别。
- 中英混输能识别。
- 润色结果能插入当前输入框。
- 插入失败时能自动复制。
- 历史能看到原文和最终文本。
- 个人词典能影响后续输出。

### 11.2 场景测试

至少测试这些 app：

- TextEdit。
- Notes。
- Safari/Chrome 网页输入框。
- ChatGPT 或 Claude 输入框。
- Cursor 输入框。
- 微信/飞书/Slack 类 IM。
- 邮件客户端。

### 11.3 质量测试

准备样例库，覆盖：

- 去口癖和重复。
- 中途改口。
- 中文标点。
- 中英混输。
- 技术词。
- 邮件表达。
- Prompt 结构化。
- 插入失败兜底。

---

## 12. 第一轮完成定义

满足以下条件才算第一轮完成：

- 主链路可以连续稳定使用。
- 常用 app 中可以完成输入。
- 失败不会丢内容。
- 胶囊 UI 足够小，不干扰工作流。
- 默认润色自然，不过度 AI 化。
- 历史和剪贴板可以恢复最近输入。
- 隐私路径清楚，本地/云端/BYOK 不混淆。
- 用户可以在 5 分钟内完成第一次成功输入。

---

## 13. 关联文档

- [OpenLess 产品需求文档](</Users/lvbaiqing/TRUE 开发/openless/docs/openless-requirements.md>)
- [语音输入产品第一轮需求文档](</Users/lvbaiqing/TRUE 开发/openless/docs/voice-input-mvp-requirements.md>)
- [OpenLess 竞品评论、产品基调与 UI 方向调研](</Users/lvbaiqing/TRUE 开发/openless/docs/competitor-reviews-and-ui-direction.md>)
- [OpenLess 概念版诊断与落地规格](</Users/lvbaiqing/TRUE 开发/openless/docs/openless-product-concept-diagnosis.md>)
- [OpenLess 整体逻辑梳理](</Users/lvbaiqing/TRUE 开发/openless/docs/openless-overall-logic.md>)
