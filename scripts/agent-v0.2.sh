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

# ============================================
# JSON 工具函数
# ============================================

# 转义字符串用于 JSON（处理换行符等特殊字符）
json_escape() {
    local str="$1"
    # 使用 sed 进行转义，逐个替换特殊字符
    # 注意：必须按顺序处理，先处理反斜杠
    local result=""
    local char=""
    local i=0
    while [ $i -lt ${#str} ]; do
        char="${str:$i:1}"
        case "$char" in
            '\\') result="${result}\\\\" ;;
            '"') result="${result}\\\"" ;;
            $'\t') result="${result}\\t" ;;
            $'\r') result="${result}\\r" ;;
            $'\n') result="${result}\\n" ;;
            *) result="${result}${char}" ;;
        esac
        i=$((i + 1))
    done
    printf '%s' "$result"
}
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
            # 调用入口函数（在所有函数加载后）
            pm_init
            pm_main_loop
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
            # 调用入口函数（在所有函数加载后）
            coder_init
            coder_main_loop
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
            # 调用入口函数（在所有函数加载后）
            reviewer_init
            reviewer_main_loop
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
            # 限流：指数退避 + 额外延迟 (10s, 30s, 60s, 120s, 300s)
            echo $((base_delay * (2 ** retry_count) + retry_count * 10))
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
    local max_retries=5
    local base_delay=10
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

        # 追加完整请求响应到调试日志
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        {
            echo ""
            echo "========================================"
            echo "=== [$timestamp] API 请求 $i/$max_retries ==="
            echo "========================================"
            echo "URL: ${OPENAI_BASE_URL}/chat/completions"
            echo "Model: $OPENAI_MODEL"
            echo "Payload 长度: ${#payload}"
            echo ""
            echo "--- 完整 Payload ---"
            echo "$payload"
            echo ""
        } >> /tmp/api_debug.log

        local response=$(curl -s -X POST \
            "${OPENAI_BASE_URL}/chat/completions" \
            -H "Authorization: Bearer $OPENAI_API_KEY" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            --max-time 120 2>&1)

        # 追加完整响应到调试日志
        {
            echo "--- 完整 Response ---"
            echo "Response 长度: ${#response}"
            echo ""
            echo "$response"
            echo ""
            echo "========================================"
            echo ""
        } >> /tmp/api_debug.log

        log_info "响应长度: ${#response}"

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
                    # 限流，保存完整响应用于分析
                    echo "$response" > /tmp/rate_limit_response.json
                    log_warn "API 错误 ($error_type): $error_msg"
                    log_warn "完整响应已保存到 /tmp/rate_limit_response.json"
                    log_warn "响应内容: $response"
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

# 工具定义
get_tools_definition() {
    echo '[
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
                "description": "写入文件内容，创建文件或覆盖现有文件",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "filename": {"type": "string", "description": "文件名（可以是相对路径或绝对路径）"},
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
}

# 提取 JSON 字符串值的函数（处理转义引号）
# 用法: extract_json_string "json_text" "key_name"
# 返回 key 对应的字符串值（不包含外层引号）
extract_json_string() {
    local json="$1"
    local key="$2"

    # 找到 "key":" 后的位置
    local pattern="\"$key\"[[:space:]]*:[[:space:]]*\""
    local start=$(echo "$json" | grep -o "$pattern" | head -1)

    if [ -z "$start" ]; then
        return 1
    fi

    # 提取从 key 开始的字符串
    local remaining=$(echo "$json" | sed "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"//")

    # 遍历找到结束引号（处理转义）
    local result=""
    local i=0
    local len=${#remaining}
    local in_escape=0

    while [ $i -lt $len ]; do
        local char="${remaining:$i:1}"
        if [ "$in_escape" -eq 1 ]; then
            result="${result}${char}"
            in_escape=0
        elif [ "$char" = "\\" ]; then
            result="${result}${char}"
            in_escape=1
        elif [ "$char" = '"' ]; then
            # 找到结束引号
            break
        else
            result="${result}${char}"
        fi
        i=$((i + 1))
    done

    echo "$result"
    return 0
}

# 处理工具调用 - 返回 JSON 格式的工具调用 ID 和结果
# 输出格式: {"id":"call_xxx","name":"xxx","result":"xxx"}
# 注意：所有日志输出到 stderr，只有最终的 JSON 结果输出到 stdout
handle_tool_calls() {
    local response="$1"

    # 提取 tool_calls 数组部分
    local tool_calls_section=$(echo "$response" | sed -n '/"tool_calls":\[/,/\]/p')

    # 提取第一个工具调用的 id 和 name
    local tool_id=$(echo "$tool_calls_section" | grep -o '"id":"[^"]*"' | head -1 | sed 's/"id":"//;s/"$//')
    local tool_name=$(echo "$tool_calls_section" | grep -o '"name":"[^"]*"' | head -1 | sed 's/"name":"//;s/"$//')

    # 使用自定义函数提取 arguments
    local tool_args=$(extract_json_string "$tool_calls_section" "arguments")

    if [ -z "$tool_name" ]; then
        log_warn "无法提取工具调用信息" >&2
        echo '{"id":"","name":"","result":"error: cannot parse tool call"}'
        return 1
    fi

    log_info "工具调用: $tool_name (id: $tool_id)" >&2
    log_info "参数: $tool_args" >&2

    # 去除转义：将 \" 转换为 "，将 \\ 转换为 \
    # 注意：tool_args 格式如 {\"filename\": \"value\"}
    local clean_args=$(printf '%s' "$tool_args" | sed 's/\\"/"/g')

    log_info "清理后参数: $clean_args" >&2

    local tool_result=""

    case "$tool_name" in
        "file_read")
            local filename=$(echo "$clean_args" | sed -n 's/.*"filename"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            if [ -f "$filename" ]; then
                log_info "读取文件: $filename" >&2
                tool_result=$(cat "$filename" 2>&1)
            else
                log_error "文件不存在: $filename" >&2
                tool_result="错误: 文件 $filename 不存在"
            fi
            ;;
        "file_write")
            local filename=$(echo "$clean_args" | sed -n 's/.*"filename"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            # content 需要特殊处理，提取整个 content 字段
            local content=$(echo "$clean_args" | sed -n 's/.*"content"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | sed 's/\\n/\n/g' | sed 's/\\t/\t/g')
            log_info "写入文件: $filename" >&2

            # 确保目录存在
            local dir=$(dirname "$filename")
            if [ "$dir" != "." ] && [ ! -d "$dir" ]; then
                mkdir -p "$dir"
            fi

            echo -e "$content" > "$filename"
            log_info "文件写入成功: $filename" >&2
            tool_result="成功写入文件: $filename"
            ;;
        "shell_run")
            local command=$(echo "$clean_args" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            log_info "执行命令: $command" >&2
            tool_result=$(eval "$command" 2>&1)
            ;;
        *)
            log_warn "未知工具: $tool_name" >&2
            tool_result="未知工具: $tool_name"
            ;;
    esac

    # 转义结果用于 JSON
    local escaped_result=$(json_escape "$tool_result")

    # 返回 JSON 格式的结果（只有这个输出到 stdout）
    echo "{\"id\":\"$tool_id\",\"name\":\"$tool_name\",\"result\":\"$escaped_result\"}"
    return 0
}

chat() {
    local user_message="$1"
    local role_prompt="${AGENT_PROMPT:-你是$AGENT_NAME，一个专业的$AGENT_ROLE角色。}"
    local max_turns=20  # 最大对话轮数，防止无限循环

    log_info "=== chat() 函数开始 ==="

    # 转义字符串用于 JSON（处理换行符等特殊字符）
    local escaped_prompt=$(json_escape "$role_prompt")
    local escaped_message=$(json_escape "$user_message")

    # 初始化消息数组 - 使用简单的追加方式
    local messages='[
        {"role": "system", "content": "'"$escaped_prompt"'。你有以下工具可用：file_read, file_write, shell_run。当需要创建或修改文件时，必须使用 file_write 工具。"},
        {"role": "user", "content": "'"$escaped_message"'"}
    ]'

    local tools=$(get_tools_definition)
    log_info "工具定义长度: ${#tools} 字符"

    local turn=0
    while [ $turn -lt $max_turns ]; do
        turn=$((turn + 1))
        log_info "=== 对话轮次 $turn ==="

        log_info "发送请求到 LLM（带工具）..."
        local response=$(call_glm "$messages" "$tools")

        # 调试：打印响应的前 300 字符
        log_info "API 响应预览: $(echo "$response" | head -c 300)"

        # 检查 finish_reason
        local finish_reason=$(echo "$response" | grep -o '"finish_reason":"[^"]*"' | head -1 | sed 's/"finish_reason":"//;s/"$//')
        log_info "finish_reason: $finish_reason"

        # 检查是否有工具调用
        local tool_calls=$(echo "$response" | grep -o '"tool_calls":\[' | head -1)
        local function_call=$(echo "$response" | grep -o '"function_call":{' | head -1)

        log_info "tool_calls 检测: $([ -n "$tool_calls" ] && echo "找到" || echo "未找到")"
        log_info "function_call 检测: $([ -n "$function_call" ] && echo "找到" || echo "未找到")"

        if [ -n "$tool_calls" ]; then
            log_info "检测到 tool_calls 调用"

            # 执行工具调用并获取结果
            local tool_result=$(handle_tool_calls "$response")

            # 提取工具调用信息用于构建消息
            local tool_id=$(echo "$tool_result" | sed 's/.*"id":"\([^"]*\)".*/\1/')
            local tool_name=$(echo "$tool_result" | sed 's/.*"name":"\([^"]*\)".*/\1/')
            # 使用 extract_json_string 正确提取包含特殊字符的 result
            local tool_output=$(extract_json_string "$tool_result" "result")

            log_info "工具执行结果: ${tool_output:0:100}..."

            # 从原始响应中提取完整的 arguments（使用自定义函数）
            local tool_calls_section=$(echo "$response" | sed -n '/"tool_calls":\[/,/\]/p')
            local tool_args=$(extract_json_string "$tool_calls_section" "arguments")
            # 如果没有提取到 arguments，使用空对象
            if [ -z "$tool_args" ]; then
                tool_args="{}"
            fi

            # 添加 assistant 消息（包含 tool_calls）和 tool 消息到对话历史
            local escaped_tool_output=$(json_escape "$tool_output")

            # 构建新的消息追加到数组
            # assistant 消息需要包含完整的 tool_calls 信息
            local assistant_msg='{"role":"assistant","content":"","tool_calls":[{"id":"'"$tool_id"'","type":"function","function":{"name":"'"$tool_name"'","arguments":"'"$tool_args"'"}}]}'
            local tool_msg='{"role":"tool","tool_call_id":"'"$tool_id"'","content":"'"$escaped_tool_output"'"}'

            # 追加到 messages 数组
            # 移除最后的 ]，添加新消息，再加回 ]
            messages=$(echo "$messages" | sed 's/]$//')
            messages="$messages, $assistant_msg, $tool_msg]"

            log_info "继续对话，等待模型响应..."

        elif [ -n "$function_call" ]; then
            log_info "检测到 function_call 调用（旧版格式）"
            # 处理旧版 function_call 格式
            local fc_name=$(echo "$response" | grep -o '"name":"[^"]*"' | head -1 | sed 's/"name":"//;s/"$//')
            local fc_args=$(echo "$response" | grep -o '"arguments":"[^"]*"' | head -1 | sed 's/"arguments":"//;s/"$//')
            log_info "工具: $fc_name, 参数: $fc_args"

            # 构造兼容的响应格式并调用处理函数
            local fake_response='{"tool_calls":[{"id":"call_'$turn'","type":"function","function":{"name":"'"$fc_name"'","arguments":"'"$fc_args"'"}}}'
            local tool_result=$(handle_tool_calls "$fake_response")

            local tool_output=$(echo "$tool_result" | sed 's/.*"result":"\([^"]*\)".*/\1/')
            local escaped_tool_output=$(json_escape "$tool_output")

            # 添加消息到历史
            local assistant_msg='{"role":"assistant","content":"","function_call":{"name":"'"$fc_name"'","arguments":"'"$fc_args"'"}}'
            local tool_msg='{"role":"function","name":"'"$fc_name"'","content":"'"$escaped_tool_output"'"}'

            messages=$(echo "$messages" | sed 's/]$//')
            messages="$messages, $assistant_msg, $tool_msg]"

            log_info "继续对话，等待模型响应..."

        else
            # 没有工具调用，检查是否有文本回复
            local content=$(echo "$response" | grep -o '"content":"[^"]*"' | head -1 | sed 's/"content":"//;s/"$//')
            if [ -n "$content" ]; then
                log_agent "$content"
                log_info "对话完成，模型返回最终回复"
                return 0
            else
                log_warn "模型返回空响应"
                return 1
            fi
        fi
    done

    log_warn "达到最大对话轮数 ($max_turns)，强制结束"
    return 0
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
