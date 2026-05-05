# Cooper 贡献策略分析

## Finding 结果总结（2026-05-04）

### 1. 项目现状
- **主维护者 baiqing**：负责 UI、产品设计、核心架构
- **技术栈**：Tauri 2 + Rust backend + React/TS frontend
- **核心模块**：coordinator (3462行)、ASR (1164行)、polish (992行)、recorder (525行)

### 2. 技术债务与机会

#### 🔴 测试覆盖率极低（最大痛点）
- 项目只有 **1 个 test 类型提交**（vs 42 个 fix 提交）
- 15 个模块有 `#[cfg(test)]`，但测试内容很少
- `cargo test` 能跑，但覆盖率几乎为 0
- **机会**：建立测试基础设施，成为测试领域的 owner

#### 🟡 ASR 扩展性需求（高价值功能）
- **#211 本地 ASR AI 支持**（0 commits，无人认领）
  - 需求文档已明确：whisper.cpp / sherpa-onnx 选型
  - 涉及：模型下载、本地推理、流式对接
  - 技术挑战高，但有清晰的规划框架
  
- **#89 混淆词纠错层**（priority: high，0 commits）
  - ASR → polish 之间插入纠错层
  - 解决 "issue" 被识别为 "iOS" 的问题
  - 需要规则引擎 + 上下文判断

#### 🟢 安全与基础设施（高优先级但无人做）
- **#222 CI secrets 暴露风险**（priority: high）
- **#223 凭据配置状态管理**（priority: high）
- **#230 Keychain 威胁模型**
- **#226 WebView CSP 策略**

#### 🔵 Windows 平台问题（你的已有优势）
- 7 个 Windows 相关 issues（#244-247, #203-204, #207）
- 但这些都是 UI 问题，baiqing 可能不让碰

---

## 三条可选路径

### 路径 A：测试基础设施建设者（推荐 ⭐⭐⭐⭐⭐）

**为什么推荐**：
- 项目最大的技术债，无人认领
- 不涉及 UI，不会和 baiqing 冲突
- 建立后你就是测试领域的 owner
- 对所有模块都有贡献机会

**具体工作**：
1. **Phase 1**：为核心模块补单元测试
   - `recorder.rs`：音频采集、RMS 计算、watchdog
   - `asr/frame.rs`：二进制帧编解码（已有 1 个测试，可扩展）
   - `persistence.rs`：JSON 序列化、Keychain 读写
   - `types.rs`：状态机转换、错误类型

2. **Phase 2**：建立集成测试
   - 录音 → ASR → 润色 → 插入 全链路 mock 测试
   - 凭据管理流程测试
   - 热词注入测试

3. **Phase 3**：CI 自动化
   - GitHub Actions 跑测试
   - 覆盖率报告（codecov）
   - PR 门禁

**预期产出**：
- 测试覆盖率从 ~0% → 60%+
- 成为项目测试基础设施的 owner
- 提交数可能 +30-50 commits

---

### 路径 B：ASR 功能扩展专家（推荐 ⭐⭐⭐⭐）

**为什么推荐**：
- #211 本地 ASR 是高价值功能，无人认领
- #89 混淆词纠错是 priority: high
- ASR 模块相对独立，不涉及 UI
- 技术挑战高，完成后影响力大

**具体工作**：
1. **先做 #89 混淆词纠错层**（热身项目）
   - 在 `coordinator.rs:616-617` 之前插入纠错层
   - 实现规则引擎：`issue/iOS`, `PR/批阅`, `CI/西爱` 等
   - 支持用户自定义混淆词表
   - 预计 3-5 天完成

2. **再做 #211 本地 ASR**（主攻方向）
   - 先写 `docs/local-asr-plan.md` 规划文档
   - 选型：whisper.cpp vs sherpa-onnx
   - 实现 `asr/local_whisper.rs` 模块
   - 模型下载与管理
   - 预计 2-3 周完成

**预期产出**：
- 2 个高价值功能
- 成为 ASR 模块的 co-owner
- 提交数可能 +20-30 commits

---

### 路径 C：安全与基础设施专家（推荐 ⭐⭐⭐）

**为什么推荐**：
- 4 个 priority: high 的安全 issues
- 无人认领，但很重要
- 不涉及 UI 和产品设计

**具体工作**：
1. **#222 CI secrets 暴露**：pin PR-Agent action 版本
2. **#223 凭据配置状态**：修复 `get_credentials` 逻辑
3. **#230 Keychain 威胁模型**：审查 `persistence.rs` 凭据存储
4. **#226 WebView CSP**：为 Tauri WebView 添加 CSP 策略

**预期产出**：
- 解决 4 个高优先级安全问题
- 成为安全领域的 owner
- 提交数可能 +10-15 commits

---

## 我的建议

### 最优策略：A + B 组合拳

**第 1 周**：做 #89 混淆词纠错（快速产出，熟悉 ASR 链路）
**第 2-3 周**：为 ASR 模块补测试（frame.rs, volcengine.rs, whisper.rs）
**第 4-6 周**：做 #211 本地 ASR（大功能，高影响力）
**第 7 周起**：继续补其他模块测试 + 建 CI

**为什么这样组合**：
1. 混淆词纠错是小功能，快速建立信心
2. 补 ASR 测试时深入理解模块，为本地 ASR 打基础
3. 本地 ASR 是大功能，完成后你就是 ASR 领域的专家
4. 测试基础设施是长期工作，可以持续贡献

**避开的雷区**：
- ❌ Windows UI 问题（#244-247）：baiqing 的领域
- ❌ 主窗口 UI（Overview/History/Settings）：baiqing 的领域
- ❌ Capsule 视觉设计：baiqing 的领域

**你的领域**：
- ✅ 测试基础设施
- ✅ ASR 功能扩展
- ✅ 录音器稳定性（你已在做 #238）
- ✅ 安全与基础设施
- ✅ 文档与分析报告

---

## 下一步行动

**现在就可以开始**：
```bash
# 1. 先看看 #89 混淆词纠错的代码位置
gh issue view 89

# 2. 读 coordinator.rs:616-617 附近的代码
# 找到 ASR → polish 的接口

# 3. 设计纠错层的接口
# 输入：RawTranscript
# 输出：CorrectedTranscript
```

**要不要我帮你**：
- 生成 #89 的实现方案？
- 或者先帮你规划 #211 本地 ASR 的技术选型？
- 或者先帮你为 `asr/frame.rs` 补测试作为热身？
