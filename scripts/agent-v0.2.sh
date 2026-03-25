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
# LLM Provider (支持 GLM/GPT/DeepSeek/Kimi 等)
# ============================================

# 错误类型定义
ERROR_TYPE_RATE_LIMIT="rate_limit"
ERROR_TYPE_AUTH="auth_error"
ERROR_TYPE_INVALID_REQUEST="invalid_request"
ERROR_TYPE_SERVER_ERROR="server_error"
ERROR_TYPE_UNKNOWN="unknown"

# 检测 API 提供商
detect_provider() {
    local base_url="${OPENAI_BASE_URL:-}"

    if [[ "$base_url" == *"openai.com"* ]]; then
        echo "openai"
    elif [[ "$base_url" == *"deepseek.com"* ]]; then
        echo "deepseek"
    elif [[ "$base_url" == *"moonshot.cn"* ]]; then
        echo "moonshot"
    elif [[ "$base_url" == *"ai-yuanjing.com"* ]] || [[ "$base_url" == *"zhipuai"* ]]; then
        echo "zhipu"
    elif [[ "$base_url" == *"dashscope.aliyuncs"* ]]; then
        echo "aliyun"
    else
        echo "unknown"
    fi
}

# 解析错误类型
parse_error_type() {
    local response="$1"
    local provider="$2"

    # 检查 HTTP 状态码（OpenAI 兼容格式）
    local http_status=$(echo "$response" | grep -o '"status":[[:space:]]*[0-9]*' | head -1 | grep -o '[0-9]*')

    # 如果没有 status 字段，检查 error 对象
    if [ -z "$http_status" ]; then
        http_status=$(echo "$response" | grep -o '"status_code":[[:space:]]*[0-9]*' | head -1 | grep -o '[0-9]*')
    fi

    # 检查错误码（GLM/智谱特有）
    local error_code=$(echo "$response" | grep -o '"code":[[:space:]]*[0-9]*' | head -1 | grep -o '[0-9]*')

    # 检查错误类型字段
    local error_type=$(echo "$response" | grep -o '"type":[[:space:]]*"[^"]*"' | head -1 | sed 's/"type":[[:space:]]*"//;s/"$//')

    # 根据不同格式判断错误类型

    # 1. HTTP 状态码判断（通用）
    case "$http_status" in
        429)
            echo "$ERROR_TYPE_RATE_LIMIT"
            return
            ;;
        401|403)
            echo "$ERROR_TYPE_AUTH"
            return
            ;;
        400)
            echo "$ERROR_TYPE_INVALID_REQUEST"
            return
            ;;
        500|502|503|504)
            echo "$ERROR_TYPE_SERVER_ERROR"
            return
            ;;
    esac

    # 2. GLM/智谱特有错误码
    case "$error_code" in
        5001)  # QPS 限流
            echo "$ERROR_TYPE_RATE_LIMIT"
            return
            ;;
        5002)  # Token 超限
            echo "$ERROR_TYPE_INVALID_REQUEST"
            return
            ;;
        5003)  # 模型错误
            echo "$ERROR_TYPE_SERVER_ERROR"
            return
            ;;
    esac

    # 3. OpenAI 错误类型
    case "$error_type" in
        "insufficient_quota"|"rate_limit_exceeded"|"requests_per_minute_limit_exceeded")
            echo "$ERROR_TYPE_RATE_LIMIT"
            return
            ;;
        "invalid_api_key"|"invalid_authentication")
            echo "$ERROR_TYPE_AUTH"
            return
            ;;
        "invalid_request_error"|"context_length_exceeded")
            echo "$ERROR_TYPE_INVALID_REQUEST"
            return
            ;;
    esac

    # 4. 检查响应中是否有错误信息
    if echo "$response" | grep -qi "rate.limit"; then
        echo "$ERROR_TYPE_RATE_LIMIT"
        return
    fi

    if echo "$response" | grep -qi "unauthorized\|invalid.api.key\|authentication"; then
        echo "$ERROR_TYPE_AUTH"
        return
    fi

    echo "$ERROR_TYPE_UNKNOWN"
}

# 获取错误描述
get_error_message() {
    local error_type="$1"
    local response="$2"

    # 尝试从响应中提取错误信息
    local error_msg=$(echo "$response" | grep -o '"message":[[:space:]]*"[^"]*"' | head -1 | sed 's/"message":[[:space:]]*"//;s/"$//')

    if [ -z "$error_msg" ]; then
        error_msg=$(echo "$response" | grep -o '"error":[[:space:]]*"[^"]*"' | head -1 | sed 's/"error":[[:space:]]*"//;s/"$//')
    fi

    case "$error_type" in
        "$ERROR_TYPE_RATE_LIMIT")
            echo "API 限流${error_msg:+: $error_msg}"
            ;;
        "$ERROR_TYPE_AUTH")
            echo "API 认证失败${error_msg:+: $error_msg}"
            ;;
        "$ERROR_TYPE_INVALID_REQUEST")
            echo "请求格式错误${error_msg:+: $error_msg}"
            ;;
        "$ERROR_TYPE_SERVER_ERROR")
            echo "服务器错误${error_msg:+: $error_msg}"
            ;;
        *)
            echo "未知错误${error_msg:+: $error_msg}"
            ;;
    esac
}

# 计算重试延迟
calculate_retry_delay() {
    local base_delay="$1"
    local retry_count="$2"
    local error_type="$3"

    case "$error_type" in
        "$ERROR_TYPE_RATE_LIMIT")
            # 限流：指数退避
            echo $((base_delay * (2 ** retry_count)))
            ;;
        "$ERROR_TYPE_SERVER_ERROR")
            # 服务器错误：固定延迟
            echo "$base_delay"
            ;;
        *)
            # 其他：短延迟
            echo "$base_delay"
            ;;
    esac
}

# 调用 LLM API（通用版）
call_glm() {
    local messages="$1"
    local tools="$2"
    local max_retries=3
    local base_delay=5
    local retry_delay=$base_delay

    local payload='{"model": "'"$OPENAI_MODEL"'", "messages": '"$messages"'}'

    if [ -n "$tools" ]; then
        payload='{"model": "'"$OPENAI_MODEL"'", "messages": '"$messages"', "tools": '"$tools"'}'
    fi

    # 检测 API 提供商
    local provider=$(detect_provider)
    log_info "API 提供商: $provider"

    for i in $(seq 1 $max_retries); do
        log_info "API 调用尝试 $i/$max_retries..."

        local response=$(curl -s -X POST \
            "${OPENAI_BASE_URL}/chat/completions" \
            -H "Authorization: Bearer $OPENAI_API_KEY" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            --max-time 120 2>&1)

        # 检查 curl 是否成功
        local curl_exit_code=$?
        if [ $curl_exit_code -ne 0 ]; then
            log_warn "网络请求失败 (exit code: $curl_exit_code)"
            if [ $i -lt $max_retries ]; then
                sleep $retry_delay
                retry_delay=$((retry_delay * 2))
                continue
            fi
            log_error "API 调用失败，网络错误"
            echo "$response"
            return 1
        fi

        # 检查响应是否包含错误
        if echo "$response" | grep -q '"error"\|"code".*500[0-9]\|"status":[[:space:]]*[45][0-9][0-9]'; then
            local error_type=$(parse_error_type "$response" "$provider")
            local error_msg=$(get_error_message "$error_type" "$response")

            log_warn "API 错误 ($error_type): $error_msg"

            case "$error_type" in
                "$ERROR_TYPE_RATE_LIMIT")
                    # 限流，等待重试
                    retry_delay=$(calculate_retry_delay "$base_delay" "$((i-1))" "$error_type")
                    log_warn "等待 ${retry_delay}s 后重试 ($i/$max_retries)..."
                    sleep $retry_delay
                    continue
                    ;;
                "$ERROR_TYPE_AUTH")
                    # 认证错误，不重试
                    log_error "API 认证失败，请检查 OPENAI_API_KEY"
                    echo "$response"
                    return 1
                    ;;
                "$ERROR_TYPE_INVALID_REQUEST")
                    # 请求错误，不重试
                    log_error "请求格式错误，请检查请求参数"
                    echo "$response"
                    return 1
                    ;;
                "$ERROR_TYPE_SERVER_ERROR")
                    # 服务器错误，重试
                    if [ $i -lt $max_retries ]; then
                        log_warn "服务器错误，等待 ${retry_delay}s 后重试..."
                        sleep $retry_delay
                        continue
                    fi
                    ;;
                *)
                    # 未知错误，尝试重试
                    if [ $i -lt $max_retries ]; then
                        log_warn "未知错误，等待 ${retry_delay}s 后重试..."
                        sleep $retry_delay
                        continue
                    fi
                    ;;
            esac
        fi

        # 检查是否有有效响应
        if echo "$response" | grep -q '"choices"\|"content"'; then
            log_info "API 调用成功"
            echo "$response"
            return 0
        fi

        # 响应格式不正确
        log_warn "响应格式不正确: ${response:0:200}..."
        if [ $i -lt $max_retries ]; then
            sleep $retry_delay
            continue
        fi
    done

    log_error "API 调用失败，已达最大重试次数 ($max_retries)"
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

    log_info "发送请求到 LLM..."
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
