#!/bin/bash
# agent-v0.2.sh - v0.2 多 Agent 协作入口
#
# 功能：
# - 多 Agent 角色支持 (PM/Coder/Reviewer)
# - 基于角色的循环逻辑
# - 共享协调机制
# - 消息传递
# - 心跳监控
#
# 用法：
#   ./agent-v0.2.sh                    # 启动交互模式
#   ./agent-v0.2.sh --role pm          # 指定角色
#   ./agent-v0.2.sh --task "实现xxx"   # 执行单个任务

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
AGENT_STATUS="${AGENT_STATUS:-idle}"
CURRENT_TASK="${CURRENT_TASK:-}"

# 工作目录
WORKSPACE="${WORKSPACE:-/workspace}"

# Git 配置
GIT_USER_NAME="${GIT_USER_NAME:-$AGENT_ROLE-$AGENT_ID}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-$AGENT_ROLE@$AGENT_ID.local}"

# 脚本目录
SCRIPTS_DIR="${SCRIPTS_DIR:-/app}"

# 轮询间隔
POLL_INTERVAL="${POLL_INTERVAL:-30}"

# ============================================
# 颜色输出
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_agent() { echo -e "${BLUE}[$AGENT_NAME]${NC} $1"; }
log_role() { echo -e "${PURPLE}[$AGENT_ROLE]${NC} $1"; }

# ============================================
# 加载核心模块
# ============================================

load_modules() {
    # 加载协调模块
    if [ -f "$SCRIPTS_DIR/agent-coordinator.sh" ]; then
        source "$SCRIPTS_DIR/agent-coordinator.sh"
        log_info "加载协调模块"
    elif [ -f "./scripts/agent-coordinator.sh" ]; then
        source "./scripts/agent-coordinator.sh"
        log_info "加载协调模块 (本地)"
    else
        log_warn "协调模块不存在"
    fi

    # 加载消息模块
    if [ -f "$SCRIPTS_DIR/agent-messaging.sh" ]; then
        source "$SCRIPTS_DIR/agent-messaging.sh"
        log_info "加载消息模块"
    elif [ -f "./scripts/agent-messaging.sh" ]; then
        source "./scripts/agent-messaging.sh"
        log_info "加载消息模块 (本地)"
    else
        log_warn "消息模块不存在"
    fi

    # 加载心跳模块
    if [ -f "$SCRIPTS_DIR/agent-heartbeat.sh" ]; then
        source "$SCRIPTS_DIR/agent-heartbeat.sh"
        log_info "加载心跳模块"
    elif [ -f "./scripts/agent-heartbeat.sh" ]; then
        source "./scripts/agent-heartbeat.sh"
        log_info "加载心跳模块 (本地)"
    else
        log_warn "心跳模块不存在"
    fi
}

# ============================================
# 初始化
# ============================================

init() {
    log_info "=============================================="
    log_info "Agent v0.2 - 多 Agent 协作模式"
    log_info "=============================================="
    log_info "Agent ID: $AGENT_ID"
    log_info "角色: $AGENT_ROLE"
    log_info "名称: $AGENT_NAME"
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

    # 加载模块
    load_modules

    # 初始化目录
    init_coordinator_dirs 2>/dev/null || true
    init_messaging_dirs 2>/dev/null || true
    init_heartbeat_dirs 2>/dev/null || true

    # 初始化心跳
    create_heartbeat_file "$AGENT_ID" 2>/dev/null || true

    log_info "初始化完成"
}

# ============================================
# 角色特定循环
# ============================================

run_role_loop() {
    local role="${1:-$AGENT_ROLE}"

    case "$role" in
        pm)
            log_role "启动 PM Agent 循环"
            if [ -f "$SCRIPTS_DIR/agent-pm-loop.sh" ]; then
                source "$SCRIPTS_DIR/agent-pm-loop.sh"
            elif [ -f "./scripts/agent-pm-loop.sh" ]; then
                source "./scripts/agent-pm-loop.sh"
            else
                log_error "PM 循环脚本不存在"
                exit 1
            fi
            ;;
        coder)
            log_role "启动 Coder Agent 循环"
            if [ -f "$SCRIPTS_DIR/agent-coder-loop.sh" ]; then
                source "$SCRIPTS_DIR/agent-coder-loop.sh"
            elif [ -f "./scripts/agent-coder-loop.sh" ]; then
                source "./scripts/agent-coder-loop.sh"
            else
                log_error "Coder 循环脚本不存在"
                exit 1
            fi
            ;;
        reviewer)
            log_role "启动 Reviewer Agent 循环"
            if [ -f "$SCRIPTS_DIR/agent-reviewer-loop.sh" ]; then
                source "$SCRIPTS_DIR/agent-reviewer-loop.sh"
            elif [ -f "./scripts/agent-reviewer-loop.sh" ]; then
                source "./scripts/agent-reviewer-loop.sh"
            else
                log_error "Reviewer 循环脚本不存在"
                exit 1
            fi
            ;;
        *)
            log_error "未知角色: $role"
            log_info "可用角色: pm, coder, reviewer"
            exit 1
            ;;
    esac
}

# ============================================
# GLM Provider (保留 v0.1 兼容)
# ============================================

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
            --max-time 120)

        # 检查是否有错误
        local error_code=$(echo "$response" | grep -o '"code":[0-9]*' | head -1 | grep -o '[0-9]*')

        if [ "$error_code" = "5001" ]; then
            log_warn "QPS 限流，等待 ${retry_delay}s 后重试 ($i/$max_retries)..."
            sleep $retry_delay
            retry_delay=$((retry_delay * 2))
            continue
        fi

        echo "$response"
        return 0
    done

    log_error "API 调用失败，已达最大重试次数"
    echo "$response"
    return 1
}

chat() {
    local user_message="$1"
    local role_prompt="${AGENT_PROMPT:-你是$AGENT_NAME，一个专业的$AGENT_ROLE角色。}"

    local messages='[
        {"role": "system", "content": "'"$role_prompt"'"},
        {"role": "user", "content": "'"$user_message"'"}
    ]'

    log_info "发送请求到 GLM..."
    local response=$(call_glm "$messages")

    local content=$(echo "$response" | grep -o '"content":"[^"]*"' | head -1 | sed 's/"content":"//;s/"$//')

    if [ -n "$content" ]; then
        log_agent "$content"
    else
        log_error "API 调用失败"
        echo "$response"
    fi
}

# ============================================
# 配置管理
# ============================================

load_role_config() {
    local role_file=""
    for path in ".agent/roles/${AGENT_ROLE}/config.yaml" "/app/roles/${AGENT_ROLE}/config.yaml"; do
        if [ -f "$path" ]; then
            role_file="$path"
            break
        fi
    done

    if [ -n "$role_file" ]; then
        log_info "加载角色配置: $role_file"

        # 解析 YAML 配置
        export AGENT_ROLE_NAME=$(grep "^name:" "$role_file" | awk '{print $2}')
        export AGENT_MODEL=$(grep "^  model:" "$role_file" -A1 | tail -1 | awk '{print $2}')

        # 加载角色提示词
        local prompt_file="${role_file/config.yaml/prompt.md}"
        if [ -f "$prompt_file" ]; then
            export AGENT_PROMPT=$(cat "$prompt_file")
        fi
    else
        log_warn "角色配置不存在，使用默认配置"
        export AGENT_PROMPT="你是$AGENT_NAME，一个专业的$AGENT_ROLE角色。"
    fi
}

show_config() {
    echo "=============================================="
    echo "Agent v0.2 配置"
    echo "=============================================="
    echo "Agent ID:    $AGENT_ID"
    echo "角色:        $AGENT_ROLE"
    echo "名称:        $AGENT_NAME"
    echo "模型:        $OPENAI_MODEL"
    echo "API 端点:    $OPENAI_BASE_URL"
    echo "工作目录:    $(pwd)"
    echo "轮询间隔:    ${POLL_INTERVAL}s"
    echo "=============================================="
}

# ============================================
# CLI 交互
# ============================================

show_help() {
    echo "Agent v0.2 - 多 Agent 协作模式"
    echo ""
    echo "命令："
    echo "  help          显示帮助"
    echo "  config        显示配置"
    echo "  status        显示 Git 状态"
    echo "  agents        显示所有 Agent 状态"
    echo "  tasks         显示任务列表"
    echo "  messages      显示收件箱消息"
    echo "  chat <msg>    与 Agent 对话"
    echo "  run           启动角色循环"
    echo "  quit          退出"
    echo ""
    echo "环境变量："
    echo "  OPENAI_API_KEY    API 密钥"
    echo "  OPENAI_BASE_URL   API 端点"
    echo "  OPENAI_MODEL      模型名称"
    echo "  AGENT_ROLE        Agent 角色 (pm/coder/reviewer)"
    echo "  WORKSPACE         工作目录"
    echo "  POLL_INTERVAL     轮询间隔（秒）"
}

interactive_loop() {
    log_info "启动交互模式（输入 'help' 查看命令）"

    while true; do
        echo ""
        read -p "[$AGENT_ROLE]> " input

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
                git status -s
                ;;
            agents)
                show_all_agents 2>/dev/null || echo "心跳模块未加载"
                ;;
            tasks)
                echo "=== 待办任务 ==="
                list_tasks_by_state "pending" 2>/dev/null || echo "协调模块未加载"
                echo ""
                echo "=== 进行中任务 ==="
                list_tasks_by_state "in-progress" 2>/dev/null || true
                echo ""
                echo "=== 审查中任务 ==="
                list_tasks_by_state "review" 2>/dev/null || true
                ;;
            messages)
                echo "=== 收件箱 ==="
                local msgs=$(get_unread_messages "$AGENT_ID" 2>/dev/null)
                if [ -n "$msgs" ]; then
                    for msg in $msgs; do
                        show_message_summary "$msg" 2>/dev/null || echo "$msg"
                    done
                else
                    echo "无新消息"
                fi
                ;;
            chat)
                if [ -n "$args" ]; then
                    chat "$args"
                else
                    log_warn "请输入消息"
                fi
                ;;
            run)
                run_role_loop "$AGENT_ROLE"
                ;;
            quit|exit)
                log_info "退出"
                stop_heartbeat_daemon "$AGENT_ID" 2>/dev/null || true
                break
                ;;
            "")
                ;;
            *)
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
            --role)
                shift
                export AGENT_ROLE="$1"
                run_role_loop "$AGENT_ROLE"
                ;;
            --task)
                shift
                chat "$@"
                ;;
            --chat)
                shift
                chat "$@"
                ;;
            --run)
                run_role_loop "$AGENT_ROLE"
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
