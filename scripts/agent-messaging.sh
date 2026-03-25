#!/bin/bash
# agent-messaging.sh - Agent 间消息传递系统
#
# 功能：
# - 发送消息到其他 Agent
# - 读取收件箱消息
# - 消息确认机制
# - 消息归档
#
# 消息类型：
# - task_assign: 任务分配
# - review_request: 审查请求
# - review_result: 审查结果
# - notification: 通知
# - query: 查询
# - response: 响应
#
# 用法: source scripts/agent-messaging.sh

set -e

# ============================================
# 配置
# ============================================

MESSAGES_DIR="${MESSAGES_DIR:-.agent/messages}"
INBOX_DIR="$MESSAGES_DIR/inbox"
OUTBOX_DIR="$MESSAGES_DIR/outbox"
ARCHIVE_DIR="$MESSAGES_DIR/archive"

# ============================================
# 颜色输出
# ============================================

PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_msg() { echo -e "${PURPLE}[MSG]${NC} $1"; }

# ============================================
# 目录初始化
# ============================================

init_messaging_dirs() {
    mkdir -p "$INBOX_DIR"
    mkdir -p "$OUTBOX_DIR"
    mkdir -p "$ARCHIVE_DIR"
}

# ============================================
# 消息格式
# ============================================

# 生成唯一消息 ID
generate_message_id() {
    echo "msg-$(date +%Y%m%d%H%M%S)-$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 6)"
}

# 创建消息文件
create_message() {
    local msg_id="$1"
    local from="$2"
    local to="$3"
    local type="$4"
    local content="$5"
    local priority="${6:-normal}"
    local requires_ack="${7:-false}"

    local msg_file="$OUTBOX_DIR/${msg_id}.yaml"

    cat > "$msg_file" << EOF
id: $msg_id
from: $from
to: $to
type: $type
priority: $priority
created_at: $(date -Iseconds)
read_at: null
acknowledged_at: null
requires_ack: $requires_ack
content:
$content
EOF

    echo "$msg_file"
}

# ============================================
# 发送消息
# ============================================

send_message() {
    local from="$1"
    local to="$2"
    local type="$3"
    local content="$4"
    local priority="${5:-normal}"
    local requires_ack="${6:-false}"

    local msg_id=$(generate_message_id)

    log_msg "发送消息: $msg_id" >&2
    log_msg "  从: $from" >&2
    log_msg "  到: $to" >&2
    log_msg "  类型: $type" >&2

    # 创建消息文件
    local msg_file=$(create_message "$msg_id" "$from" "$to" "$type" "$content" "$priority" "$requires_ack")

    # 移动到目标收件箱
    local target_inbox="$INBOX_DIR/$to"
    mkdir -p "$target_inbox"

    mv "$msg_file" "$target_inbox/${msg_id}.yaml"

    # 提交到 Git（静默模式）
    git add "$MESSAGES_DIR/" 2>/dev/null || true
    git commit -m "msg: $type from $from to $to" -q 2>/dev/null || true

    echo "$msg_id"
}

# 快捷方法：分配任务
send_task_assign() {
    local from="$1"      # 发送者 (通常是 PM)
    local to="$2"        # 接收者 (通常是 Coder)
    local task_id="$3"
    local task_title="$4"
    local priority="${5:-P1}"
    local deadline="${6:-}"

    local content="  task_id: $task_id
  task_title: $task_title
  priority: $priority
  action: assign
$(if [ -n "$deadline" ]; then echo "  deadline: $deadline"; fi)"

    send_message "$from" "$to" "task_assign" "$content" "normal" "true"
}

# 快捷方法：请求审查
send_review_request() {
    local from="$1"      # 发送者 (通常是 Coder)
    local to="$2"        # 接收者 (通常是 Reviewer)
    local task_id="$3"
    local summary="$4"
    local changed_files="$5"

    local content="  task_id: $task_id
  summary: |
    $summary
  changed_files:
$(for f in $changed_files; do echo "    - $f"; done)
  action: review_request"

    send_message "$from" "$to" "review_request" "$content" "high" "true"
}

# 快捷方法：发送审查结果
send_review_result() {
    local from="$1"      # 发送者 (Reviewer)
    local to="$2"        # 接收者 (Coder 或 PM)
    local task_id="$3"
    local result="$4"    # approved / rejected
    local comments="$5"
    local changed_files="$6"

    local content="  task_id: $task_id
  result: $result
  comments: |
    $comments
$(if [ -n "$changed_files" ] && [ "$result" = "approved" ]; then
    echo "  approved_files:"
    for f in $changed_files; do echo "    - $f"; done
fi)
  action: review_result"

    send_message "$from" "$to" "review_result" "$content" "high" "true"
}

# 快捷方法：发送通知
send_notification() {
    local from="$1"
    local to="$2"
    local subject="$3"
    local body="$4"
    local priority="${5:-normal}"

    local content="  subject: $subject
  body: |
    $body"

    send_message "$from" "$to" "notification" "$content" "$priority" "false"
}

# ============================================
# 读取消息
# ============================================

get_inbox() {
    local agent_id="$1"
    local inbox="$INBOX_DIR/$agent_id"

    if [ -d "$inbox" ]; then
        for msg_file in "$inbox"/*.yaml; do
        [ -e "$msg_file" ] || continue
            if [ -f "$msg_file" ]; then
                echo "$msg_file"
            fi
        done
    fi
}

get_unread_messages() {
    local agent_id="$1"
    local inbox="$INBOX_DIR/$agent_id"

    if [ -d "$inbox" ]; then
        for msg_file in "$inbox"/*.yaml; do
        [ -e "$msg_file" ] || continue
            if [ -f "$msg_file" ]; then
                local read_at=$(grep "^read_at:" "$msg_file" | awk '{print $2}')
                if [ "$read_at" = "null" ] || [ -z "$read_at" ]; then
                    echo "$msg_file"
                fi
            fi
        done
    fi
}

get_pending_ack_messages() {
    local agent_id="$1"
    local inbox="$INBOX_DIR/$agent_id"

    if [ -d "$inbox" ]; then
        for msg_file in "$inbox"/*.yaml; do
        [ -e "$msg_file" ] || continue
            if [ -f "$msg_file" ]; then
                local requires_ack=$(grep "^requires_ack:" "$msg_file" | awk '{print $2}')
                local acknowledged=$(grep "^acknowledged_at:" "$msg_file" | awk '{print $2}')

                if [ "$requires_ack" = "true" ] && [ "$acknowledged" = "null" ]; then
                    echo "$msg_file"
                fi
            fi
        done
    fi
}

# 标记消息已读
mark_message_read() {
    local msg_file="$1"

    if [ -f "$msg_file" ]; then
        sed -i "s/^read_at:.*/read_at: $(date -Iseconds)/" "$msg_file"
        log_msg "消息已标记为已读: $(basename $msg_file .yaml)"
    fi
}

# 确认消息
acknowledge_message() {
    local msg_file="$1"
    local response="${2:-acknowledged}"

    if [ -f "$msg_file" ]; then
        sed -i "s/^acknowledged_at:.*/acknowledged_at: $(date -Iseconds)/" "$msg_file"
        echo "" >> "$msg_file"
        echo "ack_response: $response" >> "$msg_file"
        log_msg "消息已确认: $(basename $msg_file .yaml)"
    fi
}

# 归档消息
archive_message() {
    local msg_file="$1"

    if [ -f "$msg_file" ]; then
        mkdir -p "$ARCHIVE_DIR"
        mv "$msg_file" "$ARCHIVE_DIR/"
        log_msg "消息已归档: $(basename $msg_file .yaml)"
    fi
}

# ============================================
# 消息解析工具
# ============================================

parse_message() {
    local msg_file="$1"
    local field="$2"

    if [ -f "$msg_file" ]; then
        case "$field" in
            id|from|to|type|priority|created_at|read_at|requires_ack)
                grep "^$field:" "$msg_file" | awk '{print $2}'
                ;;
            content)
                # 返回 content 部分的所有内容
                sed -n '/^content:/,/^[a-z_]*:/p' "$msg_file" | head -n -1 | tail -n +2
                ;;
            *)
                grep "^$field:" "$msg_file" | awk '{print $2}'
                ;;
        esac
    fi
}

# 显示消息摘要
show_message_summary() {
    local msg_file="$1"

    if [ -f "$msg_file" ]; then
        local msg_id=$(parse_message "$msg_file" "id")
        local from=$(parse_message "$msg_file" "from")
        local type=$(parse_message "$msg_file" "type")
        local priority=$(parse_message "$msg_file" "priority")
        local created=$(parse_message "$msg_file" "created_at")
        local read_at=$(parse_message "$msg_file" "read_at")

        echo "[$msg_id] $type (from: $from, priority: $priority)"
        echo "  创建时间: $created"
        if [ "$read_at" = "null" ] || [ -z "$read_at" ]; then
            echo "  状态: 未读"
        else
            echo "  状态: 已读"
        fi
    fi
}

# 显示消息详情
show_message_detail() {
    local msg_file="$1"

    if [ -f "$msg_file" ]; then
        echo "=========================================="
        cat "$msg_file"
        echo "=========================================="
    fi
}

# ============================================
# 消息轮询
# ============================================

poll_messages() {
    local agent_id="$1"
    local callback="${2:-}"
    local interval="${3:-30}"

    log_msg "开始轮询消息 (Agent: $agent_id, 间隔: ${interval}s)"

    while true; do
        # 拉取最新消息
        git pull --rebase origin main -q 2>/dev/null || true

        # 检查未读消息
        local unread=$(get_unread_messages "$agent_id")

        if [ -n "$unread" ]; then
            for msg_file in $unread; do
                log_msg "收到新消息: $(basename $msg_file .yaml)"
                show_message_summary "$msg_file"

                # 如果有回调函数，执行它
                if [ -n "$callback" ] && [ "$(type -t $callback)" = "function" ]; then
                    $callback "$msg_file"
                fi
            done
        fi

        sleep $interval
    done
}

# ============================================
# 批量操作
# ============================================

# 处理所有未读消息
process_unread_messages() {
    local agent_id="$1"
    local handler_script="$2"

    for msg_file in $(get_unread_messages "$agent_id"); do
        log_msg "处理消息: $(basename $msg_file .yaml)"

        # 标记已读
        mark_message_read "$msg_file"

        # 如果指定了处理脚本，执行它
        if [ -n "$handler_script" ] && [ -x "$handler_script" ]; then
            $handler_script "$msg_file"
        fi

        # 如果需要确认，自动确认
        local requires_ack=$(parse_message "$msg_file" "requires_ack")
        if [ "$requires_ack" = "true" ]; then
            acknowledge_message "$msg_file" "processed"
        fi
    done

    # 提交状态变更
    git add "$MESSAGES_DIR/" 2>/dev/null || true
    git commit -m "msg: 处理消息" 2>/dev/null || true
    git push origin main -q 2>/dev/null || true
}

# 清理过期消息
cleanup_old_messages() {
    local days="${1:-7}"

    log_msg "清理 $days 天前的已读消息..."

    for inbox in "$INBOX_DIR"/*; do
        if [ -d "$inbox" ]; then
            for msg_file in "$inbox"/*.yaml; do
        [ -e "$msg_file" ] || continue
                if [ -f "$msg_file" ]; then
                    local read_at=$(parse_message "$msg_file" "read_at")

                    if [ "$read_at" != "null" ] && [ -n "$read_at" ]; then
                        # 检查消息是否过期
                        local msg_ts=$(date -d "$read_at" +%s 2>/dev/null || echo 0)
                        local cutoff_ts=$(date -d "$days days ago" +%s)

                        if [ $msg_ts -lt $cutoff_ts ]; then
                            archive_message "$msg_file"
                        fi
                    fi
                fi
            done
        fi
    done

    log_msg "清理完成"
}

# 初始化目录
init_messaging_dirs 2>/dev/null || true
