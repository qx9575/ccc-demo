#!/bin/bash
# agent-v0.1.sh - v0.1 MVP 主入口
#
# 功能：
# - GLM Provider（OpenAI 兼容接口）
# - Git 同步（pull/push）
# - 单 Agent 配置
# - CLI 交互
#
# 用法：
#   ./agent-v0.1.sh                    # 启动交互模式
#   ./agent-v0.1.sh --task "实现xxx"   # 执行单个任务

set -e

# ============================================
# 配置
# ============================================

# GLM API 配置（从环境变量读取）
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
OPENAI_BASE_URL="${OPENAI_BASE_URL:-https://maas-api.ai-yuanjing.com/openapi/compatible-mode/v1}"
OPENAI_MODEL="${OPENAI_MODEL:-glm-5}"

# Agent 配置
AGENT_ID="${AGENT_ID:-agent-$(hostname)}"
AGENT_ROLE="${AGENT_ROLE:-coder}"
AGENT_NAME="${AGENT_NAME:-程序员}"

# 工作目录
WORKSPACE="${WORKSPACE:-/workspace}"

# Git 配置
GIT_USER_NAME="${GIT_USER_NAME:-$AGENT_ROLE-$AGENT_ID}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-$AGENT_ROLE@$AGENT_ID.local}"

# ============================================
# 颜色输出
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_agent() {
    echo -e "${BLUE}[$AGENT_NAME]${NC} $1"
}

# ============================================
# 初始化
# ============================================

init() {
    log_info "初始化 Agent v0.1..."
    log_info "Agent ID: $AGENT_ID"
    log_info "角色: $AGENT_ROLE"
    log_info "模型: $OPENAI_MODEL"

    # 检查环境变量
    if [ -z "$OPENAI_API_KEY" ]; then
        log_error "请设置 OPENAI_API_KEY 环境变量"
        exit 1
    fi

    # 配置 Git
    git config user.name "$GIT_USER_NAME" 2>/dev/null || true
    git config user.email "$GIT_USER_EMAIL" 2>/dev/null || true

    # 切换到工作目录
    if [ -d "$WORKSPACE" ]; then
        cd "$WORKSPACE"
        log_info "工作目录: $(pwd)"
    else
        log_warn "工作目录不存在: $WORKSPACE"
    fi

    # 检查是否在 Git 仓库中
    if [ ! -d ".git" ]; then
        log_warn "当前目录不是 Git 仓库"
    fi

    log_info "初始化完成"
}

# ============================================
# Git 同步模块
# ============================================

# 拉取最新代码
git_pull() {
    log_info "拉取最新代码..."
    if git pull --rebase origin main 2>&1; then
        log_info "拉取成功"
        return 0
    else
        log_error "拉取失败"
        return 1
    fi
}

# 推送代码
git_push() {
    log_info "推送代码..."
    if git push origin main 2>&1; then
        log_info "推送成功"
        return 0
    else
        log_warn "推送失败，可能需要先拉取"
        return 1
    fi
}

# 检查是否有冲突
check_conflict() {
    local conflict_files=$(git diff --name-only --diff-filter=U 2>/dev/null)
    if [ -n "$conflict_files" ]; then
        log_warn "检测到代码冲突："
        echo "$conflict_files"
        return 0
    fi
    return 1
}

# Git 状态
git_status() {
    log_info "Git 状态："
    git status -s
}

# ============================================
# GLM Provider
# ============================================

# 调用 GLM API（带重试）
call_glm() {
    local messages="$1"
    local tools="$2"
    local max_retries=3
    local retry_delay=5

    local payload='{"model": "'"$OPENAI_MODEL"'", "messages": '"$messages"'}'

    if [ -n "$tools" ]; then
        payload='{"model": "'"$OPENAI_MODEL"'", "messages": '"$messages"', "tools": '"$tools"'}'
    fi

    for i in $(seq 1 $max_retries); do
        local response=$(curl -s -X POST \
            "${OPENAI_BASE_URL}/chat/completions" \
            -H "Authorization: Bearer $OPENAI_API_KEY" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            --max-time 60)

        # 检查是否有错误
        local error_code=$(echo "$response" | grep -o '"code":[0-9]*' | head -1 | grep -o '[0-9]*')

        if [ "$error_code" = "5001" ]; then
            # QPS 限流，等待重试
            log_warn "QPS 限流，等待 ${retry_delay}s 后重试 ($i/$max_retries)..."
            sleep $retry_delay
            retry_delay=$((retry_delay * 2))  # 指数退避
            continue
        fi

        # 返回响应
        echo "$response"
        return 0
    done

    # 重试失败
    log_error "API 调用失败，已达最大重试次数"
    echo "$response"
    return 1
}

# 简单对话（无工具）
chat() {
    local user_message="$1"

    local messages='[
        {"role": "system", "content": "你是'"$AGENT_NAME"'，一个专业的程序员。"},
        {"role": "user", "content": "'"$user_message"'"}
    ]'

    log_info "发送请求到 GLM..."
    local response=$(call_glm "$messages")

    # 提取回复内容
    local content=$(echo "$response" | grep -o '"content":"[^"]*"' | head -1 | sed 's/"content":"//;s/"$//')

    if [ -n "$content" ]; then
        log_agent "$content"
    else
        log_error "API 调用失败"
        echo "$response"
    fi
}

# 带工具调用的对话
chat_with_tools() {
    local user_message="$1"

    local messages='[
        {"role": "system", "content": "你是'"$AGENT_NAME"'，一个专业的程序员。你有以下工具可用：file_read, file_write, shell_run。"},
        {"role": "user", "content": "'"$user_message"'"}
    ]'

    local tools='[
        {
            "type": "function",
            "function": {
                "name": "file_read",
                "description": "读取文件内容",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "filename": {"type": "string", "description": "文件名"}
                    },
                    "required": ["filename"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "file_write",
                "description": "写入文件内容",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "filename": {"type": "string", "description": "文件名"},
                        "content": {"type": "string", "description": "文件内容"}
                    },
                    "required": ["filename", "content"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "shell_run",
                "description": "执行 shell 命令",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "command": {"type": "string", "description": "shell 命令"}
                    },
                    "required": ["command"]
                }
            }
        }
    ]'

    log_info "发送请求到 GLM（带工具）..."
    local response=$(call_glm "$messages" "$tools")

    # 检查是否有工具调用
    local tool_calls=$(echo "$response" | grep -o '"tool_calls":\[.*\]' | head -1)

    if [ -n "$tool_calls" ]; then
        log_info "检测到工具调用"
        # 解析工具调用并执行
        handle_tool_calls "$response"
    else
        # 提取回复内容
        local content=$(echo "$response" | grep -o '"content":"[^"]*"' | head -1 | sed 's/"content":"//;s/"$//')
        if [ -n "$content" ]; then
            log_agent "$content"
        else
            log_error "API 调用失败"
            echo "$response"
        fi
    fi
}

# 处理工具调用
handle_tool_calls() {
    local response="$1"

    # 提取工具调用信息
    # 格式: "tool_calls":[{"id":"...","type":"function","function":{"name":"file_read","arguments":"{\"filename\": \"README.md\"}"}}]
    local tool_name=$(echo "$response" | sed -n 's/.*"function":{ *"name":"\([^"]*\)".*/\1/p')

    # 提取 arguments JSON 字符串（带转义引号）
    local tool_args=$(echo "$response" | sed -n 's/.*"arguments":"\({[^}]*}\)".*/\1/p')

    log_info "工具调用: $tool_name"
    log_info "参数: $tool_args"

    # 去除转义，将 \" 替换为 "
    local clean_args=$(echo "$tool_args" | sed 's/\\"/"/g')

    # 解析参数中的值
    case "$tool_name" in
        "file_read")
            local filename=$(echo "$clean_args" | sed -n 's/.*"filename"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            if [ -f "$filename" ]; then
                log_info "读取文件: $filename"
                cat "$filename"
            else
                log_error "文件不存在: $filename"
            fi
            ;;
        "file_write")
            local filename=$(echo "$clean_args" | sed -n 's/.*"filename"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            # content 可能很长，需要特殊处理
            local content=$(echo "$clean_args" | sed -n 's/.*"content"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | sed 's/\\n/\n/g')
            log_info "写入文件: $filename"
            echo -e "$content" > "$filename"
            ;;
        "shell_run")
            local command=$(echo "$clean_args" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            log_info "执行命令: $command"
            eval "$command"
            ;;
        *)
            log_warn "未知工具: $tool_name"
            ;;
    esac
}

# ============================================
# 配置管理
# ============================================

# 加载角色配置
load_role_config() {
    local role_file=".agent/roles/${AGENT_ROLE}/prompt.md"

    if [ -f "$role_file" ]; then
        log_info "加载角色配置: $role_file"
        export AGENT_PROMPT=$(cat "$role_file")
    else
        log_warn "角色配置不存在: $role_file"
        export AGENT_PROMPT="你是$AGENT_NAME，一个专业的程序员。"
    fi
}

# 显示配置
show_config() {
    echo "=============================================="
    echo "Agent v0.1 配置"
    echo "=============================================="
    echo "Agent ID:    $AGENT_ID"
    echo "角色:        $AGENT_ROLE"
    echo "名称:        $AGENT_NAME"
    echo "模型:        $OPENAI_MODEL"
    echo "API 端点:    $OPENAI_BASE_URL"
    echo "工作目录:    $(pwd)"
    echo "=============================================="
}

# ============================================
# CLI 交互
# ============================================

# 显示帮助
show_help() {
    echo "Agent v0.1 - CLI 交互模式"
    echo ""
    echo "命令："
    echo "  help          显示帮助"
    echo "  config        显示配置"
    echo "  status        显示 Git 状态"
    echo "  pull          拉取最新代码"
    echo "  push          推送代码"
    echo "  chat <msg>    与 Agent 对话"
    echo "  task <msg>    执行任务（带工具）"
    echo "  quit          退出"
    echo ""
    echo "环境变量："
    echo "  OPENAI_API_KEY    API 密钥"
    echo "  OPENAI_BASE_URL   API 端点"
    echo "  OPENAI_MODEL      模型名称"
    echo "  AGENT_ROLE        Agent 角色"
    echo "  WORKSPACE         工作目录"
}

# 交互循环
interactive_loop() {
    log_info "启动交互模式（输入 'help' 查看命令）"

    while true; do
        echo ""
        read -p "> " input

        # 解析命令
        cmd=$(echo "$input" | awk '{print $1}')
        args=$(echo "$input" | cut -d' ' -f2-)

        case "$cmd" in
            help)
                show_help
                ;;
            config)
                show_config
                ;;
            status)
                git_status
                ;;
            pull)
                git_pull
                ;;
            push)
                git_push
                ;;
            chat)
                if [ -n "$args" ]; then
                    chat "$args"
                else
                    log_warn "请输入消息"
                fi
                ;;
            task)
                if [ -n "$args" ]; then
                    chat_with_tools "$args"
                else
                    log_warn "请输入任务描述"
                fi
                ;;
            quit|exit)
                log_info "退出"
                break
                ;;
            "")
                # 空输入，跳过
                ;;
            *)
                # 默认作为对话
                chat "$input"
                ;;
        esac
    done
}

# ============================================
# 主入口
# ============================================

main() {
    # 初始化
    init

    # 加载角色配置
    load_role_config

    # 处理命令行参数
    if [ -n "$1" ]; then
        case "$1" in
            --task)
                # 执行单个任务
                shift
                chat_with_tools "$@"
                ;;
            --chat)
                # 单次对话
                shift
                chat "$@"
                ;;
            --config)
                show_config
                ;;
            --help|-h)
                show_help
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    else
        # 交互模式
        interactive_loop
    fi
}

# 运行
main "$@"
