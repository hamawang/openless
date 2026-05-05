# [EPIC] ASR 功能扩展与优化

## 🎯 目标

扩展 ASR 模块功能，提升语音识别准确性和用户体验，支持本地 ASR 和混淆词纠错。

## 📊 现状分析

### 当前架构
```
Recorder (16kHz mono Int16 PCM)
    ↓
AudioConsumer trait
    ↓
ASR Provider (Volcengine WebSocket / Whisper HTTP)
    ↓
RawTranscript
    ↓
Polish (OpenAI-compatible)
    ↓
Insertion
```

### 现有 ASR Providers
- **Volcengine Streaming ASR** (`asr/volcengine.rs`, 749 行)
  - WebSocket 流式识别
  - 支持热词偏置
  - 需要云端凭据
  
- **Whisper Batch ASR** (`asr/whisper.rs`, 128 行)
  - HTTP 批量识别
  - OpenAI 兼容接口
  - 需要 API key

### 痛点
1. **依赖云端服务**：离线场景、隐私敏感场景无法使用
2. **混淆词问题**：同音词、近音词识别错误（issue → iOS, PR → 批阅）
3. **无本地 fallback**：网络故障时完全不可用
4. **扩展性受限**：添加新 provider 需要大量重复代码

## 🗺️ 总体规划

### Phase 1: 混淆词纠错层（Week 1，快速产出）
在 ASR → Polish 之间插入纠错层，解决高频混淆词问题。

**优先级**：🔴 High（对应 #89）

### Phase 2: 本地 ASR 支持（Week 2-4，核心功能）
集成 whisper.cpp 或 sherpa-onnx，支持完全离线识别。

**优先级**：🟡 Medium（对应 #211）

### Phase 3: ASR Provider 架构优化（Week 5-6，长期改进）
重构 ASR 模块，提升扩展性和可维护性。

**优先级**：🟢 Low

## 📋 子任务清单

### 🔍 Finding 阶段（进行中）

#### F1: 混淆词纠错层调研
- [ ] **F1.1** 收集真实 ASR 错词样本（至少 50 个）
- [ ] **F1.2** 分析错词模式（同音、近音、跨语言、缩写）
- [ ] **F1.3** 调研现有纠错方案（规则引擎、LLM、混合）
- [ ] **F1.4** 设计纠错层接口和数据结构
- [ ] **F1.5** 确定上下文判断策略（避免误纠）

#### F2: 本地 ASR 技术选型
- [ ] **F2.1** 对比 whisper.cpp vs sherpa-onnx vs faster-whisper
- [ ] **F2.2** 评估集成方式（Rust crate / 子进程 / HTTP）
- [ ] **F2.3** 测试首字延迟和流式支持
- [ ] **F2.4** 评估跨平台兼容性（macOS/Windows/Linux）
- [ ] **F2.5** 确认 License 合规性（代码 + 模型权重）
- [ ] **F2.6** 设计模型下载与管理方案
- [ ] **F2.7** 编写 `docs/local-asr-plan.md` 技术方案

#### F3: ASR 架构分析
- [ ] **F3.1** 绘制当前 ASR 模块依赖图
- [ ] **F3.2** 识别重复代码和抽象机会
- [ ] **F3.3** 分析 AudioConsumer trait 的局限性
- [ ] **F3.4** 设计统一的 ASR Provider trait

### 🛠️ Phase 1: 混淆词纠错层

#### 设计与实现
- [ ] **T1.1** 创建 `asr/correction.rs` 模块
- [ ] **T1.2** 定义 `CorrectionRule` 数据结构
  ```rust
  struct CorrectionRule {
      pattern: String,        // 错误模式（支持正则）
      replacement: String,    // 正确词汇
      context: Option<Vec<String>>,  // 上下文关键词
      enabled: bool,
  }
  ```
- [ ] **T1.3** 实现规则引擎 `CorrectionEngine`
- [ ] **T1.4** 内置高频混淆词表
  - issue / iOS
  - PR / 批阅
  - CI / 西爱
  - commit / 靠米特
  - merge / 摸鸡
  - release / 瑞丽丝
  - workflow / 我可否楼
  - repository / 瑞泼贼特瑞
- [ ] **T1.5** 支持用户自定义混淆词表（存储在 `dictionary.json`）
- [ ] **T1.6** 在 `coordinator.rs:616-617` 集成纠错层
- [ ] **T1.7** 添加纠错日志（记录纠正前后对比）

#### 测试
- [ ] **T1.8** 单元测试：规则匹配逻辑
- [ ] **T1.9** 单元测试：上下文判断
- [ ] **T1.10** 集成测试：ASR → 纠错 → Polish 全链路
- [ ] **T1.11** 回归测试：覆盖 #89 中的所有案例

#### 文档
- [ ] **T1.12** 编写 `docs/asr-correction.md` 使用文档
- [ ] **T1.13** 更新 CLAUDE.md 说明纠错层位置

### 🚀 Phase 2: 本地 ASR 支持

#### 技术方案（先完成 Finding F2）
- [ ] **T2.1** 完成 `docs/local-asr-plan.md` 并 review
- [ ] **T2.2** 选定技术栈（whisper.cpp / sherpa-onnx）
- [ ] **T2.3** 选定集成方式（Rust crate / 子进程 / HTTP）
- [ ] **T2.4** 选定默认模型（tiny / base / small）

#### 模型管理
- [ ] **T2.5** 设计模型存储路径
  - macOS: `~/Library/Application Support/OpenLess/models/`
  - Windows: `%APPDATA%\OpenLess\models\`
  - Linux: `$XDG_DATA_HOME/OpenLess/models/`
- [ ] **T2.6** 实现模型下载器（支持断点续传）
- [ ] **T2.7** 实现模型校验（sha256）
- [ ] **T2.8** 实现模型版本管理
- [ ] **T2.9** 添加模型下载进度 UI（前端）

#### 核心实现
- [ ] **T2.10** 创建 `asr/local_whisper.rs` 或 `asr/local_sherpa.rs`
- [ ] **T2.11** 实现 `AudioConsumer` trait
- [ ] **T2.12** 实现流式识别（如果支持）或批量识别
- [ ] **T2.13** 实现热词支持（如果底层支持）
- [ ] **T2.14** 实现错误处理和降级策略
  - 模型缺失 → 提示用户下载
  - 推理失败 → 返回空结果（不丢用户的话）
- [ ] **T2.15** 在 `coordinator.rs` 集成本地 ASR provider
- [ ] **T2.16** 添加 ASR provider 切换逻辑（Settings UI）

#### 性能优化
- [ ] **T2.17** 测试首字延迟（目标 < 500ms）
- [ ] **T2.18** 测试内存占用（目标 < 500MB）
- [ ] **T2.19** 测试 CPU 占用（目标 < 50%）
- [ ] **T2.20** 添加硬件加速支持
  - macOS: Metal / CoreML
  - Windows: CUDA / DirectML
  - Linux: CUDA

#### 测试
- [ ] **T2.21** 单元测试：模型下载和校验
- [ ] **T2.22** 单元测试：本地推理
- [ ] **T2.23** 集成测试：录音 → 本地 ASR → 插入
- [ ] **T2.24** 性能测试：延迟、内存、CPU
- [ ] **T2.25** 跨平台测试（macOS/Windows/Linux）

#### 文档
- [ ] **T2.26** 更新 `docs/openless-development.md` 说明本地 ASR
- [ ] **T2.27** 编写用户文档：如何启用本地 ASR
- [ ] **T2.28** 编写开发者文档：如何添加新的本地 ASR provider
- [ ] **T2.29** 更新 CLAUDE.md 说明本地 ASR 架构

### 🏗️ Phase 3: ASR 架构优化

#### 重构目标
- [ ] **T3.1** 定义统一的 `ASRProvider` trait
  ```rust
  #[async_trait]
  pub trait ASRProvider: Send + Sync {
      async fn open_session(&self, hotwords: Vec<DictionaryHotword>) -> Result<()>;
      fn get_audio_consumer(&self) -> Arc<dyn AudioConsumer>;
      async fn close_session(&self) -> Result<RawTranscript>;
      async fn cancel_session(&self);
  }
  ```
- [ ] **T3.2** 重构 Volcengine ASR 实现 `ASRProvider`
- [ ] **T3.3** 重构 Whisper ASR 实现 `ASRProvider`
- [ ] **T3.4** 重构本地 ASR 实现 `ASRProvider`
- [ ] **T3.5** 在 `coordinator.rs` 使用统一接口
- [ ] **T3.6** 添加 ASR provider 注册机制（便于扩展）

#### 可观测性
- [ ] **T3.7** 添加 ASR 性能指标（延迟、准确率）
- [ ] **T3.8** 添加 ASR 错误日志和分类
- [ ] **T3.9** 添加 ASR 使用统计（各 provider 使用次数）

#### 文档
- [ ] **T3.10** 编写 `docs/asr-architecture.md` 架构文档
- [ ] **T3.11** 编写 `docs/add-asr-provider.md` 扩展指南

## 📐 技术约束

### 性能要求
- **首字延迟**：< 500ms（用户感知流畅）
- **内存占用**：< 500MB（不影响其他应用）
- **CPU 占用**：< 50%（避免风扇狂转）

### 兼容性要求
- **平台**：macOS 12+, Windows 10+, Linux（主流发行版）
- **架构**：x86_64, aarch64（Apple Silicon）
- **离线可用**：本地 ASR 必须完全离线工作

### 安全要求
- **隐私**：本地 ASR 不得上传音频数据
- **凭据**：云端 ASR 凭据存储在 Keychain
- **License**：所有依赖必须 License 合规

## 📈 成功指标

### Phase 1: 混淆词纠错
- [ ] 纠错规则覆盖 20+ 高频混淆词
- [ ] 纠错准确率 > 95%（不误纠）
- [ ] 用户可自定义混淆词表
- [ ] 解决 #89 中的所有案例

### Phase 2: 本地 ASR
- [ ] 支持至少 1 种本地 ASR 引擎
- [ ] 首字延迟 < 500ms
- [ ] 识别准确率 > 90%（与云端 ASR 对比）
- [ ] 模型下载成功率 > 99%
- [ ] 跨平台一致性（macOS/Windows/Linux）

### Phase 3: 架构优化
- [ ] 统一 ASR Provider 接口
- [ ] 添加新 provider 只需实现 1 个 trait
- [ ] ASR 模块代码减少 20%+（消除重复）
- [ ] 完善的架构文档

## 🔗 相关 Issues

- #89 [asr] 增加 LLM 前置混淆词纠错层（priority: high）
- #211 feat(ASR): 增加对本地 ASR AI 的支持
- #223 fix(providers): get_credentials 按 active ASR provider 返回配置状态（priority: high）

## 🔗 相关资源

### 本地 ASR 引擎
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) - C++ Whisper 实现
- [whisper-rs](https://github.com/tazz4843/whisper-rs) - Rust binding
- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) - ONNX 多模型支持
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper) - CTranslate2 加速

### 混淆词纠错
- [SymSpell](https://github.com/wolfgarbe/SymSpell) - 拼写纠错算法
- [Homophone Disambiguation](https://en.wikipedia.org/wiki/Homophone) - 同音词消歧

## 📝 进度追踪

**创建时间**：2026-05-04  
**负责人**：Cooper  
**当前阶段**：Finding  
**完成度**：0% (0/71 tasks)

---

**下一步行动**：
1. 开始 F1.1：收集真实 ASR 错词样本
2. 开始 F2.1：对比本地 ASR 技术栈
