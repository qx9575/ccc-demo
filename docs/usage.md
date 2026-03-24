# Agent v0.1 使用指南

## 快速开始

### 1. Docker Compose 方式

```bash
# 启动容器（后台运行）
docker compose up -d

# 查看运行状态
docker compose ps

# 查看日志
docker compose logs -f
```

### 2. Docker 直接运行

```bash
# 构建镜像
docker build -t agent-v0.1:latest .

# 运行容器
docker run -it --rm \
  -e OPENAI_API_KEY=your_key \
  -e OPENAI_BASE_URL=https://maas-api.ai-yuanjing.com/openapi/compatible-mode/v1 \
  -e OPENAI_MODEL=glm-5 \
  -v $(pwd):/workspace \
  agent-v0.1:latest
```

---

## 命令详解

### 命令行参数解析流程

```
docker exec agent-coder /app/agent-v0.1.sh --chat "你好"
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
| `--config` | 显示当前配置 | `--config` |
| `--help` | 显示帮助信息 | `--help` |
| 无参数 | 进入交互模式 | 直接运行 |

### --chat 命令流程

```bash
docker exec agent-coder /app/agent-v0.1.sh --chat "你好"
```

**执行流程：**

```
1. main() 接收参数: $1 = "--chat", $2 = "你好"

2. case "$1" 匹配 --chat 分支:
   --chat)
       shift              # 移除 --chat，$@ 变为 "你好"
       chat "$@"          # 调用 chat "你好"
       ;;

3. chat() 函数执行:
   chat() {
       local user_message="$1"  # "你好"

       # 构建 JSON 消息
       local messages='[
           {"role": "system", "content": "你是程序员..."},
           {"role": "user", "content": "你好"}
       ]'

       # 调用 GLM API
       local response=$(call_glm "$messages")

       # 提取并输出回复
       log_agent "$content"
   }

4. 输出结果:
   [程序员] 你好！我是专业的程序员...
```

**特点：**
- 纯对话，不调用工具
- 单次执行，退出容器
- 适合简单问答

### --task 命令流程

```bash
docker exec agent-coder /app/agent-v0.1.sh --task "读取 README.md 文件内容"
```

**执行流程：**

```
1. main() 接收参数: $1 = "--task", $2+ = "读取 README.md 文件内容"

2. case "$1" 匹配 --task 分支:
   --task)
       shift
       chat_with_tools "$@"
       ;;

3. chat_with_tools() 函数执行:
   chat_with_tools() {
       # 构建消息（包含工具说明）
       local messages='[
           {"role": "system", "content": "你是程序员...你有工具：file_read, file_write, shell_run"},
           {"role": "user", "content": "读取 README.md 文件内容"}
       ]'

       # 定义可用工具
       local tools='[
           {"type": "function", "function": {"name": "file_read", ...}},
           {"type": "function", "function": {"name": "file_write", ...}},
           {"type": "function", "function": {"name": "shell_run", ...}}
       ]'

       # 调用 API
       local response=$(call_glm "$messages" "$tools")

       # 检查是否有工具调用
       if [ -n "$tool_calls" ]; then
           handle_tool_calls "$response"
       fi
   }

4. GLM 返回工具调用:
   {
     "choices": [{
       "message": {
         "tool_calls": [{
           "function": {
             "name": "file_read",
             "arguments": "{\"filename\": \"README.md\"}"
           }
         }]
       }
     }]
   }

5. handle_tool_calls() 解析并执行:
   - 提取工具名: file_read
   - 提取参数: {"filename": "README.md"}
   - 执行对应操作: cat README.md
   - 输出文件内容
```

**工具调用解析：**

```bash
# API 返回的 arguments 格式（带转义引号）
arguments: "{\"filename\": \"README.md\"}"

# 解析步骤
1. 提取 arguments 字符串
   tool_args=$(echo "$response" | sed -n 's/.*"arguments":"\({[^}]*}\)".*/\1/p')
   # 结果: {\"filename\": \"README.md\"}

2. 去除转义
   clean_args=$(echo "$tool_args" | sed 's/\\"/"/g')
   # 结果: {"filename": "README.md"}

3. 提取具体参数值
   filename=$(echo "$clean_args" | sed -n 's/.*"filename"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
   # 结果: README.md

4. 执行工具操作
   cat "$filename"
```

---

## docker attach 详解

### 原理说明

```
┌─────────────────────────────────────────────────────────┐
│                    Docker 容器                           │
│                                                         │
│  ┌─────────────────┐                                    │
│  │  agent-v0.1.sh  │                                    │
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
| 示例 | `docker attach agent-coder` | `docker exec agent-coder /app/agent-v0.1.sh --chat "你好"` |

### docker attach 使用流程

```bash
# 1. 启动容器（必须开启 stdin 和 tty）
docker compose up -d

# 2. 连接到容器主进程
docker attach agent-coder

# 此时终端显示：
# [INFO] 启动交互模式（输入 'help' 查看命令）
# >
```

**进入交互模式后可执行的命令：**

```
> help              # 显示帮助
> config            # 显示配置
> status            # 显示 Git 状态
> pull              # 拉取最新代码
> push              # 推送代码
> chat 你好         # 与 Agent 对话（无工具）
> task 读取 xxx.md  # 执行任务（带工具）
> quit              # 退出（容器停止）
```

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
docker exec agent-coder /app/agent-v0.1.sh --chat "你好"
```

### docker-compose.yaml 配置说明

```yaml
services:
  agent-coder:
    # ... 其他配置 ...
    stdin_open: true    # 开启 stdin，允许交互输入
    tty: true           # 分配伪终端，支持终端特性
```

这两个配置是 `docker attach` 正常工作的前提：

- `stdin_open: true` - 保持 stdin 打开，否则 attach 后无法输入
- `tty: true` - 分配 TTY，否则没有命令提示符和交互体验

### 完整使用示例

```bash
# === 场景 1: 单次命令执行 ===
docker exec agent-coder /app/agent-v0.1.sh --chat "你好"
# 执行后立即返回结果，容器继续运行

# === 场景 2: 执行任务 ===
docker exec agent-coder /app/agent-v0.1.sh --task "读取 README.md"
# Agent 会调用 file_read 工具执行任务

# === 场景 3: 交互式会话 ===
docker attach agent-coder
# 进入交互模式
> config
> chat 你好
> task 列出当前目录文件
> quit  # 或 Ctrl+P Ctrl+Q

# === 场景 4: 查看容器日志 ===
docker compose logs -f agent-coder
# 实时查看输出，不能输入命令
```

---

## 环境变量配置

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `OPENAI_API_KEY` | API 密钥 | 必填 |
| `OPENAI_BASE_URL` | API 端点 | `https://maas-api.ai-yuanjing.com/openapi/compatible-mode/v1` |
| `OPENAI_MODEL` | 模型名称 | `glm-5` |
| `AGENT_ID` | Agent 标识 | `agent-$(hostname)` |
| `AGENT_ROLE` | 角色 | `coder` |
| `AGENT_NAME` | 显示名称 | `程序员` |
| `WORKSPACE` | 工作目录 | `/workspace` |

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
docker exec agent-coder /app/agent-v0.1.sh --config
```

### Q: 工具调用不生效

确认工作目录挂载：
```bash
docker exec agent-coder ls -la /workspace
```
