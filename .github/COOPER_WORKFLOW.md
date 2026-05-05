# Cooper 的贡献工作流程

> **策略**：在自己的 fork 仓库（Cooper-X-Oak/openless）中进行探索和规划，成熟后再向上游（appergb/openless）提交。

---

## 📋 两大母体 EPIC

### EPIC-001: 测试基础设施建设
- **文件**：`.github/issues/EPIC-001-testing-infrastructure.md`
- **目标**：测试覆盖率 0% → 60%+
- **任务数**：41 个子任务
- **预计时间**：6 周

### EPIC-002: ASR 功能扩展与优化
- **文件**：`.github/issues/EPIC-002-asr-enhancement.md`
- **目标**：混淆词纠错 + 本地 ASR 支持
- **任务数**：71 个子任务
- **预计时间**：6 周

---

## 🔄 工作流程

### 阶段 1: Finding（当前）

**目标**：深入调研，发现所有相关问题，填充到母体 EPIC 中。

#### 测试基础设施 Finding
```bash
# F1.1 审查现有测试
find openless-all/app/src-tauri/src -name "*.rs" -exec grep -l "#\[cfg(test)\]" {} \;
cargo test --manifest-path openless-all/app/src-tauri/Cargo.toml --lib -- --list

# F1.2 识别关键测试场景
# 读取核心模块代码，列出需要测试的函数和场景

# F1.3 分析模块依赖
# 绘制依赖图，确定哪些需要 mock

# F1.4 调研测试工具
# 评估 mockall, proptest, criterion 等工具

# F1.5 建立测试规范
# 编写 docs/testing-guidelines.md
```

#### ASR 功能扩展 Finding
```bash
# F1.1 收集 ASR 错词样本
# 从 issues、用户反馈、自己测试中收集

# F2.1 对比本地 ASR 技术栈
# 调研 whisper.cpp, sherpa-onnx, faster-whisper
# 测试性能、延迟、跨平台兼容性

# F2.7 编写技术方案
# docs/local-asr-plan.md
```

**产出**：
- 完善的子任务清单
- 技术方案文档
- 风险评估

---

### 阶段 2: 实施

**原则**：
- 每个子任务对应一个 commit
- 每个 Phase 对应一个 PR（在 fork 中）
- 重要功能先在 fork 中验证，再向上游提交

#### 分支策略
```bash
# 从 main 创建 feature 分支
git checkout main
git pull origin main
git checkout -b feat/testing-recorder    # 测试相关
git checkout -b feat/asr-correction       # ASR 纠错
git checkout -b feat/asr-local-whisper    # 本地 ASR

# 在 fork 中创建 PR
gh pr create --repo Cooper-X-Oak/openless --base main

# 验证通过后，向上游提交
gh pr create --repo appergb/openless --base main
```

#### Commit 规范
```bash
# 格式：<type>(<scope>): <subject>
# type: feat, fix, test, docs, refactor, perf, chore
# scope: 模块名（recorder, asr, coordinator, etc.）

# 示例
git commit -m "test(recorder): add unit tests for PCM data collection"
git commit -m "feat(asr): add correction layer for homophones"
git commit -m "docs(testing): add testing guidelines"
```

---

### 阶段 3: Review

**自我 Review 清单**：
- [ ] 代码符合项目规范（CLAUDE.md）
- [ ] 添加了测试（如果是功能代码）
- [ ] 更新了文档（如果改变了行为）
- [ ] 通过了 `cargo check` 和 `cargo test`
- [ ] 通过了 `npm run build`（如果改了前端）
- [ ] 提交信息清晰

**向上游提交前**：
- [ ] 在 fork 中验证至少 1 周
- [ ] 自己实机测试通过
- [ ] 写了详细的 PR 描述
- [ ] 关联了相关 issues

---

### 阶段 4: 同步上游

**定期同步**（每周一次）：
```bash
# 拉取上游更新
git checkout main
git pull origin main

# 推送到 fork
git push fork main

# rebase feature 分支
git checkout feat/testing-recorder
git rebase main
```

---

## 📊 进度追踪

### 使用 EPIC 文档追踪
- 每完成一个子任务，在 EPIC 文档中打勾 `- [x]`
- 更新完成度百分比
- 记录遇到的问题和解决方案

### 使用 GitHub Issues（fork 中）
```bash
# 为每个 Phase 创建 issue
gh issue create --repo Cooper-X-Oak/openless \
  --title "[Phase 1] 核心模块单元测试" \
  --body "参考 EPIC-001-testing-infrastructure.md Phase 1"

# 关联 commits
git commit -m "test(recorder): add unit tests

Refs Cooper-X-Oak/openless#1"
```

---

## 🎯 当前行动计划

### Week 1: Finding + 快速产出
- [ ] **Day 1-2**：完成测试基础设施 Finding（F1.1-F1.5）
- [ ] **Day 3-4**：完成 ASR 功能扩展 Finding（F1.1-F1.5, F2.1-F2.7）
- [ ] **Day 5-7**：实现混淆词纠错层（EPIC-002 Phase 1）

### Week 2-3: 测试基础建设
- [ ] 为 recorder.rs 补测试
- [ ] 为 asr/frame.rs 补测试
- [ ] 为 persistence.rs 补测试

### Week 4-6: 本地 ASR 支持
- [ ] 完成技术选型和方案设计
- [ ] 实现模型管理
- [ ] 实现本地推理
- [ ] 跨平台测试

---

## 🔧 工具和脚本

### 测试覆盖率检查
```bash
# 安装 cargo-llvm-cov
cargo install cargo-llvm-cov

# 运行覆盖率测试
cargo llvm-cov --manifest-path openless-all/app/src-tauri/Cargo.toml

# 生成 HTML 报告
cargo llvm-cov --html --manifest-path openless-all/app/src-tauri/Cargo.toml
```

### 代码质量检查
```bash
# Rust 格式化
cargo fmt --manifest-path openless-all/app/src-tauri/Cargo.toml --check

# Rust linting
cargo clippy --manifest-path openless-all/app/src-tauri/Cargo.toml -- -D warnings

# TypeScript 类型检查
cd openless-all/app && npm run build
```

---

## 🚀 快速开始

### 1. 确认环境
```bash
# 确认 git remote
git remote -v
# 应该看到：
# origin  https://github.com/appergb/openless.git
# fork    https://github.com/Cooper-X-Oak/openless.git

# 确认当前分支
git branch

# 确认构建环境
cd openless-all/app
npm ci
cargo check --manifest-path src-tauri/Cargo.toml
```

### 2. 开始 Finding
```bash
# 创建 finding 分支
git checkout -b finding/testing-infrastructure

# 开始调研，记录到 EPIC 文档
# 编辑 .github/issues/EPIC-001-testing-infrastructure.md
```

### 3. 提交 Finding 结果
```bash
# 提交 EPIC 文档更新
git add .github/issues/
git commit -m "docs(epic): complete finding phase for testing infrastructure"
git push fork finding/testing-infrastructure

# 在 fork 中创建 PR（可选）
gh pr create --repo Cooper-X-Oak/openless \
  --title "[Finding] 测试基础设施调研完成" \
  --body "完成了 EPIC-001 的 Finding 阶段，识别了 41 个子任务"
```

---

**最后更新**：2026-05-04  
**负责人**：Cooper  
**状态**：Finding 阶段
