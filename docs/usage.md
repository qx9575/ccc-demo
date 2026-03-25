# Agent 使用指南

## 版本说明

| 版本 | 功能 | 状态 |
|------|------|------|
| v0.1 | 单 Agent CLI 交互、GLM API 调用、工具执行 | ✅ 已完成 |
| v0.2 | 多 Agent 协作 (PM/Coder/Reviewer)、消息传递、心跳监控 | ✅ 已完成 |

## 快速开始

### v0.2 多 Agent 协作模式

```bash
# 构建镜像
docker compose build

# 启动所有 Agent（PM + Coder + Reviewer）
docker compose up -d

# 查看运行状态
docker compose ps

# 查看各 Agent 日志
docker compose logs -f agent-coder
docker compose logs -f agent-pm
docker compose logs -f agent-reviewer

# 单独启动某个角色
docker compose up -d agent-coder
docker compose up -d agent-pm
docker compose up -d agent-reviewer
```

### v0.1 单 Agent 模式

```bash
# 启动容器（后台运行）
docker compose up -d agent-coder

# 查看运行状态
docker compose ps

# 查看日志
docker compose logs -f
```

### Docker 直接运行

```bash
# 构建镜像
docker build -t agent-v0.2:latest .

# 运行容器
docker run -it --rm \
  -e OPENAI_API_KEY=your_key \
  -e OPENAI_BASE_URL=https://maas-api.ai-yuanjing.com/openapi/compatible-mode/v1 \
  -e OPENAI_MODEL=glm-5 \
  -e AGENT_ROLE=coder \
  -v $(pwd):/workspace \
  agent-v0.2:latest
```

---

## 命令详解

### 命令行参数解析流程

```
docker exec agent-coder /app/agent-v0.2.sh --chat "你好"
                                    │
                                    ▼
                            ┌──────────────┐
                            │   main()     │
                            │  入口函数     │
                            └──────┬───────┘
                                   │
                                   ▼
                            ┌──────────────┐
                            │    init()    │
                            │  初始化配置   │
                            └──────┬───────┘
                                   │
                                   ▼
                            ┌──────────────┐
                            │load_role_config()│
                            │  加载角色配置  │
                            └──────┬───────┘
                                   │
                                   ▼
                      ┌────────────────────────┐
                      │   检查 $1 参数          │
                      │   有参数？              │
                      └───────────┬────────────┘
                                  │
              ┌───────────────────┼───────────────────┐
              │                   │                   │
              ▼                   ▼                   ▼
        --chat "消息"       --task "任务"          无参数
              │                   │                   │
              ▼                   ▼                   ▼
        chat "$@"          chat_with_tools "$@"   interactive_loop()
        单次对话            带工具执行任务          交互模式
```

### 命令参数说明

| 命令 | 说明 | 示例 |
|------|------|------|
| `--chat "消息"` | 单次对话，无工具调用 | `--chat "你好"` |
| `--task "任务"` | 执行任务，带工具调用 | `--task "读取 README.md"` |
| `--role <role>` | 指定角色运行 | `--role pm` |
| `--run` | 启动角色循环 | `--run` |
| `--config` | 显示当前配置 | `--config` |
| `--help` | 显示帮助信息 | `--help` |
| 无参数 | 进入交互模式 | 直接运行 |

### 交互模式命令

```
> help              # 显示帮助
> config            # 显示配置
> status            # 显示 Git 状态
> agents            # 显示所有 Agent 状态
> tasks             # 显示任务列表
> messages          # 显示收件箱消息
> chat 你好         # 与 Agent 对话（无工具）
> run               # 启动角色循环
> quit              # 退出
```

---

## docker attach 详解

### 原理说明

```
┌─────────────────────────────────────────────────────────┐
│                    Docker 容器                           │
│                                                         │
│  ┌─────────────────┐                                    │
│  │  agent-v0.2.sh  │                                    │
│  │   (PID 1)       │                                    │
│  │                 │                                    │
│  │  等待输入...    │◄──── stdin (管道)                  │
│  │       │         │                                    │
│  │       ▼         │                                    │
│  │  处理命令       │────► stdout/stderr (终端)          │
│  └─────────────────┘                                    │
│                                                         │
└─────────────────────────────────────────────────────────┘
         ▲                    ▲
         │                    │
    docker attach        docker exec
    (连接到主进程)         (新开进程)
```

### docker attach vs docker exec

| 特性 | docker attach | docker exec |
|------|---------------|-------------|
| 连接目标 | 主进程 (PID 1) | 新建子进程 |
| 输入输出 | 共享主进程的 stdin/stdout | 独立的 stdin/stdout |
| 退出影响 | 可能导致容器停止 | 不影响容器运行 |
| 用途 | 交互式会话 | 执行单次命令 |
| 示例 | `docker attach agent-coder` | `docker exec agent-coder /app/agent-v0.2.sh --chat "你好"` |

### 退出 attach 模式

**重要：** 直接 Ctrl+C 或输入 `quit` 会导致容器停止！

**安全退出方式：**

```bash
# 方式 1: 输入 quit 命令（优雅退出，容器停止）
> quit

# 方式 2: 使用 Ctrl+P Ctrl+Q 序列（脱离但不停止容器）
# 按 Ctrl+P，然后按 Ctrl+Q
# 容器继续运行，你返回宿主机终端

# 方式 3: 新开终端，使用 docker exec
docker exec agent-coder /app/agent-v0.2.sh --chat "你好"
```

---

## 环境变量配置

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `OPENAI_API_KEY` | API 密钥 | 必填 |
| `OPENAI_BASE_URL` | API 端点 | `https://maas-api.ai-yuanjing.com/openapi/compatible-mode/v1` |
| `OPENAI_MODEL` | 模型名称 | `glm-5` |
| `AGENT_ID` | Agent 标识 | `agent-$(hostname)` |
| `AGENT_ROLE` | 角色 (coder/pm/reviewer) | `coder` |
| `AGENT_NAME` | 显示名称 | `程序员` |
| `WORKSPACE` | 工作目录 | `/workspace` |
| `POLL_INTERVAL` | 轮询间隔（秒） | `30` |

---

## v0.2 多 Agent 协作

### 架构概览

```
+------------------+     +------------------+     +------------------+
|    PM Agent      |     |   Coder Agent    |     |  Reviewer Agent  |
|  (任务创建)       |     |  (任务执行)       |     |  (质量把关)       |
+--------+---------+     +--------+---------+     +--------+---------+
         |                        |                        |
         v                        v                        v
    +---------------------------------------------------------+
    |              共享文件协调层                               |
    |  .agent/tasks/          (pending/in-progress/review)    |
    |  .agent/messages/       (agent-to-agent messages)       |
    |  .agent/heartbeat/      (agent health status)           |
    +---------------------------------------------------------+
                              |
                              v
                    +------------------+
                    |   Git Remote     |
                    +------------------+
```

### 任务状态机

```
pending → assigned → in_progress → review → archived
                        ↑               |
                        |---------------|  (changes_requested)
```

### Agent 角色

| 角色 | 职责 | 默认模型 |
|------|------|----------|
| PM (项目经理) | 创建任务、分配任务、监控进度 | glm-4-plus |
| Coder (程序员) | 执行任务、提交代码、请求审查 | glm-5 |
| Reviewer (审查员) | 代码审查、批准/驳回任务 | glm-4-plus |

### 目录结构

```
.agent/
├── tasks/
│   ├── pending/          # 待认领任务
│   ├── assigned/         # 已分配任务
│   ├── in-progress/      # 进行中任务
│   └── review/           # 待审查任务
├── archives/             # 归档目录
│   ├── tasks/            # 任务归档（按月）
│   ├── tests/            # 测试报告归档
│   └── commits/          # 提交记录归档
├── messages/
│   ├── inbox/{agent-id}/ # 收件箱
│   ├── outbox/           # 发件箱
│   └── archive/          # 归档
├── heartbeat/            # 心跳状态
├── conflicts/            # 冲突报告
├── coordination/         # 协调数据
├── roles/                # 角色配置
│   ├── coder/config.yaml
│   ├── pm/config.yaml
│   └── reviewer/config.yaml
└── review-standards.md   # 审查标准
```

### 消息类型

| 类型 | 发送者 | 接收者 | 说明 |
|------|--------|--------|------|
| `task_assign` | PM | Coder | 任务分配 |
| `review_request` | Coder | Reviewer | 审查请求 |
| `review_result` | Reviewer | Coder/PM | 审查结果 |
| `notification` | Any | Any | 通知 |

### 测试

```bash
# 运行多 Agent 协作测试
cd /home/qx/ai-tools/docker/ccc-demo
bash tests/test-multi-agent.sh
```

### 创建任务

```yaml
# .agent/tasks/pending/task-xxx.yaml
id: task-xxx
title: 任务标题
priority: P1
role: coder
status: pending
created_at: 2026-03-24T10:00:00Z
created_by: pm

acceptance_criteria:
  - 条件1
  - 条件2

description: |
  详细任务描述
```

### 脚本说明

| 脚本 | 功能 |
|------|------|
| `agent-v0.2.sh` | 多 Agent 入口点 |
| `agent-coordinator.sh` | 任务协调（认领、状态转换） |
| `agent-messaging.sh` | 消息传递 |
| `agent-heartbeat.sh` | 心跳监控 |
| `agent-pm-loop.sh` | PM Agent 循环 |
| `agent-coder-loop.sh` | Coder Agent 循环 |
| `agent-reviewer-loop.sh` | Reviewer Agent 循环 |
| `archive-task.sh` | 任务归档脚本 |
| `archive-utils.sh` | 归档工具函数 |

---

## 归档系统

### 归档目录结构

```
.agent/archives/
├── tasks/                    # 任务归档
│   ├── registry.yaml        # 全局任务索引
│   └── 2026-03/             # 按月归档
│       ├── task-xxx.yaml    # 任务完整记录
│       └── index.yaml       # 月度索引
├── tests/                    # 测试归档
│   ├── registry.yaml        # 全局测试索引
│   └── 2026-03/
│       └── task-xxx/        # 按任务组织
│           ├── test_report.yaml   # 测试报告
│           └── test_xxx.py        # 测试脚本快照
└── commits/                  # 提交记录归档
    ├── registry.yaml        # 全局提交索引
    └── 2026-03/
        ├── commit-xxx.yaml  # 每次提交一条
        └── index.yaml
```

### 手动归档任务

```bash
# 归档完成的任务
./scripts/archive-task.sh task-006

# 归档并包含测试报告
./scripts/archive-task.sh task-006 --test-report path/to/report
```

### Git 提交模板

项目使用规范的提交消息格式：

```bash
# 配置提交模板
git config commit.template .git-commit-template

# 提交消息格式
<type>(<scope>): <subject>

<body>

Related: <task-id>
Files: <changed-files>
Tests: <test-status>

Co-Authored-By: <agent-id>
```

**提交类型**：
- `feat`: 新功能
- `fix`: Bug 修复
- `refactor`: 重构
- `docs`: 文档变更
- `test`: 测试相关
- `chore`: 构建/工具/配置

### 归档内容说明

**任务归档**（task-xxx.yaml）：
- 任务基本信息（ID、标题、优先级、角色）
- 完整生命周期（创建、开始、提交、审查、完成时间）
- 验收标准及完成状态
- 产出物列表（代码文件、测试报告）
- 提交记录关联
- 审查历史

**测试归档**（test_report.yaml）：
- 测试概要（通过/失败数量、覆盖率）
- 测试用例详情
- 测试脚本快照（保留当时版本）
- 原始测试输出

**提交记录**（commit-xxx.yaml）：
- 提交 SHA 和作者
- 提交类型和范围
- 变更文件列表
- 关联任务和测试报告

---

## 故障排查

### Q: attach 后没有响应

检查 stdin_open 和 tty 配置：
```bash
docker inspect agent-coder | grep -A 5 "Tty"
```

### Q: 容器启动后立即退出

检查日志：
```bash
docker compose logs agent-coder
```

### Q: API 调用失败

检查环境变量：
```bash
docker exec agent-coder /app/agent-v0.2.sh --config
```

### Q: 工具调用不生效

确认工作目录挂载：
```bash
docker exec agent-coder ls -la /workspace
```

### Q: Agent 无法认领任务

检查任务锁：
```bash
ls -la .agent/tasks/in-progress/*.lock
```

### Q: 消息未送达

检查收件箱：
```bash
ls -la .agent/messages/inbox/
```
