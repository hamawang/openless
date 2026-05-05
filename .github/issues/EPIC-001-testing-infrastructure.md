# [EPIC] 测试基础设施建设

## 🎯 目标

建立完整的测试基础设施，将项目测试覆盖率从 ~0% 提升到 60%+，确保核心功能的稳定性和可维护性。

## 📊 现状分析

### 当前状态
- ✅ 项目有 15 个模块包含 `#[cfg(test)]`
- ✅ `cargo test` 可以运行
- ❌ 测试覆盖率接近 0%
- ❌ 只有 1 个 test 类型提交 vs 42 个 fix 提交
- ❌ 无 CI 自动化测试
- ❌ 无覆盖率报告

### 风险
- 重构时容易引入回归 bug
- 修复一个 bug 可能破坏另一个功能
- 新贡献者不敢大胆改代码
- 缺乏质量门禁

## 🗺️ 总体规划

### Phase 1: 核心模块单元测试（Week 1-3）
为最关键的模块补充单元测试，建立测试编写规范。

**优先级排序**：
1. **recorder.rs** (525 行) - 音频采集、watchdog、RMS 计算
2. **asr/frame.rs** (252 行) - 二进制帧编解码（已有 1 个测试）
3. **persistence.rs** (770 行) - JSON 序列化、Keychain 读写
4. **types.rs** (530 行) - 状态机转换、错误类型
5. **insertion.rs** (489 行) - 文本插入逻辑

### Phase 2: 集成测试（Week 4-5）
测试模块间协作和完整流程。

**测试场景**：
- 录音 → ASR → 润色 → 插入 全链路（mock 外部服务）
- 凭据管理流程（Keychain + JSON fallback）
- 热词注入与 ASR 偏置
- 错误恢复与降级

### Phase 3: CI 自动化（Week 6）
建立持续集成流程，自动化测试和质量门禁。

**交付物**：
- GitHub Actions workflow
- 覆盖率报告（codecov / llvm-cov）
- PR 门禁（测试必须通过）
- 测试结果徽章

## 📋 子任务清单

### 🔍 Finding 阶段（进行中）

- [ ] **F1.1** 审查所有现有测试，评估质量和覆盖范围
- [ ] **F1.2** 识别核心模块的关键测试场景
- [ ] **F1.3** 分析模块依赖关系，确定 mock 策略
- [ ] **F1.4** 调研 Rust 测试最佳实践（criterion、proptest、mockall）
- [ ] **F1.5** 建立测试编写规范文档

### 🧪 Phase 1: 单元测试

#### recorder.rs
- [ ] **T1.1** 测试音频设备枚举和选择
- [ ] **T1.2** 测试 PCM 数据采集和格式转换
- [ ] **T1.3** 测试 RMS 计算准确性
- [ ] **T1.4** 测试 watchdog 超时检测
- [ ] **T1.5** 测试录音启动/停止状态转换
- [ ] **T1.6** 测试错误处理（设备不可用、权限拒绝）

#### asr/frame.rs
- [ ] **T1.7** 扩展现有测试覆盖所有帧类型
- [ ] **T1.8** 测试帧序列化/反序列化
- [ ] **T1.9** 测试边界条件（空帧、超大帧）
- [ ] **T1.10** 测试错误帧处理

#### persistence.rs
- [ ] **T1.11** 测试 history.json 读写和容量限制（200 条）
- [ ] **T1.12** 测试 preferences.json 序列化
- [ ] **T1.13** 测试 dictionary.json 读写（注意：不能改名为 vocab.json）
- [ ] **T1.14** 测试 Keychain 凭据存储和读取
- [ ] **T1.15** 测试 credentials.json fallback 逻辑
- [ ] **T1.16** 测试跨平台路径处理（macOS/Windows/Linux）

#### types.rs
- [ ] **T1.17** 测试状态机转换（Idle → Starting → Listening → Processing）
- [ ] **T1.18** 测试错误类型序列化
- [ ] **T1.19** 测试 DictationSession 生命周期
- [ ] **T1.20** 测试 PolishMode 枚举

#### insertion.rs
- [ ] **T1.21** 测试 AX focused-element 写入逻辑
- [ ] **T1.22** 测试 clipboard + Cmd+V fallback
- [ ] **T1.23** 测试 copy-only fallback
- [ ] **T1.24** 测试跨平台修饰键映射（Cmd/Ctrl）

### 🔗 Phase 2: 集成测试

- [ ] **T2.1** 全链路 mock 测试（recorder → ASR → polish → insertion）
- [ ] **T2.2** 凭据管理流程测试
- [ ] **T2.3** 热词注入测试
- [ ] **T2.4** 错误恢复测试（ASR 失败、polish 失败、insertion 失败）
- [ ] **T2.5** 并发场景测试（快速连续触发）

### 🤖 Phase 3: CI 自动化

- [ ] **T3.1** 创建 `.github/workflows/test.yml`
- [ ] **T3.2** 配置 macOS / Windows / Linux 测试矩阵
- [ ] **T3.3** 集成覆盖率工具（cargo-llvm-cov）
- [ ] **T3.4** 上传覆盖率到 codecov.io
- [ ] **T3.5** 添加 PR 门禁规则
- [ ] **T3.6** 添加 README 徽章

## 📐 测试编写规范

### 命名约定
```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_<module>_<scenario>_<expected_behavior>() {
        // Arrange
        // Act
        // Assert
    }
}
```

### Mock 策略
- 外部服务（Volcengine ASR、OpenAI polish）：使用 `mockall` 或手写 mock
- 系统调用（Keychain、clipboard）：使用 trait abstraction
- 时间相关：使用可注入的时钟

### 覆盖率目标
- **核心模块**（coordinator, recorder, ASR）：80%+
- **工具模块**（persistence, types）：70%+
- **平台特定代码**（hotkey, insertion）：60%+
- **整体项目**：60%+

## 📈 成功指标

- [ ] 测试覆盖率达到 60%+
- [ ] CI 自动化测试运行时间 < 5 分钟
- [ ] 所有 PR 必须通过测试
- [ ] 测试文档完善，新贡献者可以轻松添加测试
- [ ] 至少 1 次通过测试发现的回归 bug

## 🔗 相关资源

- [Rust 测试最佳实践](https://doc.rust-lang.org/book/ch11-00-testing.html)
- [cargo-llvm-cov](https://github.com/taiki-e/cargo-llvm-cov)
- [mockall](https://docs.rs/mockall/latest/mockall/)
- [proptest](https://docs.rs/proptest/latest/proptest/)

## 📝 进度追踪

**创建时间**：2026-05-04  
**负责人**：Cooper  
**当前阶段**：Finding  
**完成度**：0% (0/41 tasks)

---

**下一步行动**：开始 Finding 阶段，审查现有测试并建立测试规范。
