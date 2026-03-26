# 项目进度

## 当前阶段
v0.2 多 Agent 协作已完成，准备开发 v0.3 Python 版本

## 高优先级任务
### v0.3 Python 版本（最高优先级）
**原因**: Bash 处理复杂逻辑（JSON 解析、多轮对话、错误处理）不够健壮，需要用 Python 重构

**核心问题**:
1. JSON 字符串转义需要逐字符处理，Bash 实现复杂且易出错
2. 多轮对话状态管理在 Bash 中难以维护
3. 错误处理和日志记录分散，难以调试
4. API 响应解析依赖 grep/sed，对特殊字符脆弱

**Python 版本优势**:
- 原生 JSON 支持，无需手动转义
- 结构化错误处理
- 更好的异步支持（aiohttp）
- 丰富的 LLM SDK（openai, anthropic 等）
- 类型提示和 IDE 支持

**计划**:
- [ ] 创建 Python 项目结构
- [ ] 实现 Agent 基类
- [ ] 实现 LLM 客户端（支持多模型）
- [ ] 实现工具系统
- [ ] 实现 Git 协调器
- [ ] 实现任务状态机
- [ ] Docker 部署配置

---

## v0.2 多 Agent 协作完成情况
- [x] PM/Coder/Reviewer 三角色协作
- [x] 文件级消息传递（inbox/outbox）
- [x] 心跳监控（在线检测）
- [x] 任务状态机（pending → in-progress → review → archived）
- [x] 原子任务认领（锁机制）
- [x] Git 同步与冲突处理
- [x] 多模型支持（GLM/GPT/DeepSeek/Kimi）
- [x] Docker Compose 多容器部署
- [x] SSH 支持（Git push）
- [x] 归档系统（任务/测试/提交按月归档）
- [x] Git 提交模板规范化
- [x] LLM API 多轮对话循环
- [x] JSON 字符串转义处理

## v0.2 已测试功能
| 功能 | 状态 | 说明 |
|------|------|------|
| 任务认领 | ✅ | 原子锁机制正常 |
| 任务状态流转 | ✅ | pending→in-progress→review→archived |
| Agent 间消息 | ✅ | 消息发送/读取/确认 |
| 心跳监控 | ✅ | 30s 更新，离线检测 |
| Git 同步 | ✅ | pull/push/冲突重试 |
| 多模型 API | ✅ | GLM/GPT/DeepSeek/Kimi |
| Docker 部署 | ✅ | 三个容器同时运行 |
| 任务归档 | ✅ | 按月归档，包含生命周期记录 |
| 测试归档 | ✅ | 测试脚本快照 + 测试报告 |
| 提交归档 | ✅ | 提交类型解析 + 文件变更记录 |
| 多轮对话 | ✅ | 支持 20 轮工具调用循环 |
| JSON 转义 | ✅ | 正确处理换行、引号等特殊字符 |

## 归档系统
### 目录结构
```
.agent/archives/
├── tasks/
│   ├── registry.yaml       # 全局任务索引
│   └── 2026-03/            # 按月归档
│       ├── index.yaml      # 月度索引
│       └── task-xxx.yaml   # 任务完整记录
├── tests/
│   ├── registry.yaml
│   └── 2026-03/
│       └── task-xxx/
│           ├── test_report.yaml
│           └── test_*.py   # 测试脚本快照
└── commits/
    ├── registry.yaml
    └── 2026-03/
        ├── index.yaml
        └── commit-xxx.yaml # 提交记录
```

### 已归档内容
- 任务: task-001 ~ task-005 (5个)
- 测试: task-005 测试套件 (4个文件)
- 提交: 4 条提交记录

## Git 提交模板
```
<type>(<scope>): <subject>

<body>

Related: <task-id>
Files: <changed-files>
Tests: <test-status>

Co-Authored-By: <agent-id>
```

支持类型: feat/fix/refactor/docs/test/chore/style/perf

## v0.1 MVP 完成情况
- [x] GLM Provider（OpenAI 兼容接口）
- [x] QPS 限流重试机制（指数退避）
- [x] Git 同步（pull/push）
- [x] CLI 交互模式
- [x] 工具调用（file_read, file_write, shell_run）
- [x] Docker 镜像构建
- [x] Docker Compose 配置

## 已测试功能
| 功能 | 状态 | 说明 |
|------|------|------|
| chat 对话 | ✅ | GLM-5 正常响应 |
| file_read | ✅ | 读取文件成功 |
| file_write | ✅ | 写入文件成功 |
| shell_run | ✅ | 执行命令成功 |
| QPS 重试 | ✅ | 5s→10s→20s 指数退避 |
| Docker 构建 | ✅ | 23.2MB Alpine 镜像 |
| Docker Compose | ✅ | 容器正常运行 |
| 交互模式 | ✅ | attach/exec 均可用 |

## 文档
- [使用指南](../docs/usage.md) - Docker 命令详解、attach 原理、参数解析流程

## Git 提交记录
### v0.2 Bug 修复
- `b759154` fix: 修复 LLM API 多轮对话中的 JSON 转义问题
- `d23a2ee` review: 多 Agent 协作测试运行
- `0785523` chore: 任务认领流程修复
- 多次 Agent 自动提交（任务认领、状态流转、心跳更新）

### v0.1
- `2ac675f` fix: 修复 Agent v0.1 API 调用和工具解析问题
- `5d38976` feat: 实现 Agent v0.1 主循环（Bash 版本）
- `b8e32cb` feat: Agent 冲突自动暂停和自动恢复机制

## Bug 修复详细记录

### 2026-03-26 JSON 转义问题（重大）
**问题**: GLM API 返回 "QPS限流" 错误，实际是请求 JSON 格式错误
**原因**:
1. 多行字符串（系统提示）包含未转义的换行符
2. 工具调用参数中的转义引号 `\"` 无法正确解析
3. 工具执行结果中的引号和特殊字符导致 JSON 截断

**解决**:
1. 添加 `json_escape()` 函数逐字符处理特殊字符
2. 添加 `extract_json_string()` 函数正确提取含转义的 JSON 值
3. 实现 `chat()` 多轮对话循环
4. 日志输出重定向到 stderr，避免污染返回值

**影响文件**: `scripts/agent-v0.2.sh`

### 2026-03-25 任务认领失败修复
**问题**: `find_available_tasks` 返回空任务 ID
**原因**: `git_sync_pull` 的日志输出污染了函数返回值
**解决**: 将日志输出重定向到 stderr (`>&2`)
**影响文件**: `scripts/agent-coordinator.sh`

### 2026-03-25 BusyBox 日期兼容
**问题**: Alpine 容器中 `date -Iseconds -d "+7200 seconds"` 不支持
**解决**: 添加 `get_iso_timestamp()` 和 `get_future_timestamp()` 辅助函数
**影响文件**: `scripts/agent-coordinator.sh`

### 2026-03-25 Docker SSH 支持
**问题**: 容器无法 Git push（缺少 SSH 客户端）
**解决**: Dockerfile 添加 `openssh-client`，docker-compose 挂载 `~/.ssh`
**影响文件**: `Dockerfile`, `docker-compose.yaml`

## 冲突处理机制
- [x] 冲突类型定义（任务锁/任务文件/代码/语义）
- [x] 冲突报告格式（.agent/conflicts/*.yaml）
- [x] Agent 自动暂停机制
- [x] 自动恢复轮询（30s 检查）

## 已知问题
1. **API 限流**: GLM-5 有 QPS 限制，连续请求返回 code 5001
   - 临时方案: 等待后重试
   - 长期方案: 换用更高配额 API 或本地模型

2. **模型智能**: GLM-5 有时执行不相关命令
   - 优化 system prompt
   - 考虑换用更智能模型

## 待办（降低优先级）
- [ ] 数据库持久化
- [ ] Web UI 界面
- [ ] 更多 LLM 模型支持
