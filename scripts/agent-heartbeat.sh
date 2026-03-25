#!/bin/bash
# agent-heartbeat.sh - Agent 心跳与健康监控
#
# 功能：
# - 周期性心跳更新
# - 检测离线 Agent
# - 任务超时检测
# - 健康状态报告
#
# 用法: source scripts/agent-heartbeat.sh

set -e

# ============================================
# 配置
# ============================================

HEARTBEAT_DIR="${HEARTBEAT_DIR:-.agent/heartbeat}"
HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-60}"         # 心跳间隔（秒）
HEARTBEAT_TIMEOUT="${HEARTBEAT_TIMEOUT:-300}"          # 超时判定（秒）
STALE_AGENT_TIMEOUT="${STALE_AGENT_TIMEOUT:-600}"      # 离线判定（秒）
TASK_TIMEOUT="${TASK_TIMEOUT:-7200}"                   # 任务超时（秒）

# Agent 状态
AGENT_STATUS_ACTIVE="active"
AGENT_STATUS_IDLE="idle"
AGENT_STATUS_WAITING="waiting"
AGENT_STATUS_ERROR="error"
AGENT_STATUS_OFFLINE="offline"

# ============================================
# 颜色输出
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_hb() { echo -e "${CYAN}[HEARTBEAT]${NC} $1"; }
log_health() { echo -e "${GREEN}[HEALTH]${NC} $1"; }

# ============================================
# 目录初始化
# ============================================

init_heartbeat_dirs() {
    mkdir -p "$HEARTBEAT_DIR"
}

# ============================================
# 心跳管理
# ============================================

# 创建心跳文件
create_heartbeat_file() {
    local agent_id="${1:-$AGENT_ID}"
    local hb_file="$HEARTBEAT_DIR/${agent_id}.yaml"

    cat > "$hb_file" << EOF
agent_id: $agent_id
role: ${AGENT_ROLE:-unknown}
status: ${AGENT_STATUS:-active}
current_task: ${CURRENT_TASK:-null}
last_heartbeat: $(date -Iseconds)
started_at: ${AGENT_STARTED_AT:-$(date -Iseconds)}
metadata:
  hostname: $(hostname)
  pid: $$
EOF

    echo "$hb_file"
}

# 更新心跳
update_heartbeat() {
    local agent_id="${1:-$AGENT_ID}"
    local status="${2:-active}"
    local current_task="${3:-}"

    local hb_file="$HEARTBEAT_DIR/${agent_id}.yaml"

    if [ ! -f "$hb_file" ]; then
        create_heartbeat_file "$agent_id"
        return
    fi

    # 更新心跳时间和状态
    sed -i "s/^last_heartbeat:.*/last_heartbeat: $(date -Iseconds)/" "$hb_file"
    sed -i "s/^status:.*/status: $status/" "$hb_file"

    if [ -n "$current_task" ]; then
        sed -i "s/^current_task:.*/current_task: $current_task/" "$hb_file"
    fi
}

# 获取心跳信息
get_heartbeat() {
    local agent_id="$1"
    local hb_file="$HEARTBEAT_DIR/${agent_id}.yaml"

    if [ -f "$hb_file" ]; then
        cat "$hb_file"
    else
        echo "Agent $agent_id 心跳文件不存在"
        return 1
    fi
}

# 解析心跳字段
parse_heartbeat() {
    local agent_id="$1"
    local field="$2"
    local hb_file="$HEARTBEAT_DIR/${agent_id}.yaml"

    if [ -f "$hb_file" ]; then
        grep "^$field:" "$hb_file" | awk '{print $2}'
    fi
}

# ============================================
# 健康检查
# ============================================

# 检查 Agent 是否在线
is_agent_online() {
    local agent_id="$1"
    local hb_file="$HEARTBEAT_DIR/${agent_id}.yaml"

    if [ ! -f "$hb_file" ]; then
        return 1
    fi

    local last_hb=$(parse_heartbeat "$agent_id" "last_heartbeat")
    local last_ts=$(date -d "$last_hb" +%s 2>/dev/null || echo 0)
    local now_ts=$(date +%s)
    local diff=$((now_ts - last_ts))

    if [ $diff -gt $STALE_AGENT_TIMEOUT ]; then
        return 1  # 离线
    fi

    return 0  # 在线
}

# 检查 Agent 是否活跃
is_agent_active() {
    local agent_id="$1"
    local hb_file="$HEARTBEAT_DIR/${agent_id}.yaml"

    if [ ! -f "$hb_file" ]; then
        return 1
    fi

    local last_hb=$(parse_heartbeat "$agent_id" "last_heartbeat")
    local last_ts=$(date -d "$last_hb" +%s 2>/dev/null || echo 0)
    local now_ts=$(date +%s)
    local diff=$((now_ts - last_ts))

    if [ $diff -gt $HEARTBEAT_TIMEOUT ]; then
        return 1  # 不活跃
    fi

    return 0  # 活跃
}

# 获取所有在线 Agent
get_online_agents() {
    for hb_file in "$HEARTBEAT_DIR"/*.yaml; do
        [ -e "$hb_file" ] || continue
        if [ -f "$hb_file" ]; then
            local agent_id=$(basename "$hb_file" .yaml)
            if is_agent_online "$agent_id"; then
                echo "$agent_id"
            fi
        fi
    done
}

# 获取所有离线 Agent
get_offline_agents() {
    for hb_file in "$HEARTBEAT_DIR"/*.yaml; do
        [ -e "$hb_file" ] || continue
        if [ -f "$hb_file" ]; then
            local agent_id=$(basename "$hb_file" .yaml)
            if ! is_agent_online "$agent_id"; then
                echo "$agent_id"
            fi
        fi
    done
}

# 获取指定角色的 Agent
get_agents_by_role() {
    local role="$1"

    for hb_file in "$HEARTBEAT_DIR"/*.yaml; do
        [ -e "$hb_file" ] || continue
        if [ -f "$hb_file" ]; then
            local agent_role=$(grep "^role:" "$hb_file" | awk '{print $2}')
            if [ "$agent_role" = "$role" ]; then
                local agent_id=$(basename "$hb_file" .yaml)
                echo "$agent_id"
            fi
        fi
    done
}

# ============================================
# 任务超时检测
# ============================================

# 检查任务是否超时
is_task_timed_out() {
    local task_id="$1"
    local lock_file=".agent/tasks/in-progress/${task_id}.lock"

    if [ ! -f "$lock_file" ]; then
        return 1  # 没有锁文件
    fi

    local locked_at=$(grep "^locked_at:" "$lock_file" | awk '{print $2}')
    local locked_ts=$(date -d "$locked_at" +%s 2>/dev/null || echo 0)
    local now_ts=$(date +%s)
    local diff=$((now_ts - locked_ts))

    if [ $diff -gt $TASK_TIMEOUT ]; then
        return 0  # 超时
    fi

    return 1  # 未超时
}

# 获取超时任务
get_timed_out_tasks() {
    for lock_file in .agent/tasks/in-progress/*.lock; do
        [ -e "$lock_file" ] || continue
        if [ -f "$lock_file" ]; then
            local task_id=$(basename "$lock_file" .lock)
            if is_task_timed_out "$task_id"; then
                echo "$task_id"
            fi
        fi
    done
}

# 检查心跳是否过期
is_heartbeat_stale() {
    local agent_id="$1"
    local hb_file="$HEARTBEAT_DIR/${agent_id}.yaml"

    if [ ! -f "$hb_file" ]; then
        return 0  # 过期（不存在）
    fi

    local last_hb=$(parse_heartbeat "$agent_id" "last_heartbeat")
    local last_ts=$(date -d "$last_hb" +%s 2>/dev/null || echo 0)
    local now_ts=$(date +%s)
    local diff=$((now_ts - last_ts))

    if [ $diff -gt $HEARTBEAT_TIMEOUT ]; then
        return 0  # 过期
    fi

    return 1  # 有效
}

# ============================================
# 健康报告
# ============================================

generate_health_report() {
    local report_file="${1:-.agent/health-report.yaml}"

    log_health "生成健康报告..."

    cat > "$report_file" << EOF
# Agent 健康报告
generated_at: $(date -Iseconds)

agents:
EOF

    # 添加所有 Agent 状态
    for hb_file in "$HEARTBEAT_DIR"/*.yaml; do
        [ -e "$hb_file" ] || continue
        if [ -f "$hb_file" ]; then
            local agent_id=$(basename "$hb_file" .yaml)
            local role=$(grep "^role:" "$hb_file" | awk '{print $2}')
            local status=$(grep "^status:" "$hb_file" | awk '{print $2}')
            local last_hb=$(grep "^last_heartbeat:" "$hb_file" | awk '{print $2}')
            local current_task=$(grep "^current_task:" "$hb_file" | awk '{print $2}')

            local online="offline"
            if is_agent_online "$agent_id"; then
                online="online"
            fi

            cat >> "$report_file" << EOF
  - id: $agent_id
    role: $role
    status: $status
    online: $online
    current_task: $current_task
    last_heartbeat: $last_hb
EOF
        fi
    done

    # 添加超时任务
    cat >> "$report_file" << EOF

timed_out_tasks:
EOF

    for task_id in $(get_timed_out_tasks); do
        local lock_file=".agent/tasks/in-progress/${task_id}.lock"
        local agent_id=$(grep "^agent_id:" "$lock_file" | awk '{print $2}')
        local locked_at=$(grep "^locked_at:" "$lock_file" | awk '{print $2}')

        cat >> "$report_file" << EOF
  - task_id: $task_id
    agent_id: $agent_id
    locked_at: $locked_at
EOF
    done

    log_health "健康报告已保存到: $report_file"
    echo "$report_file"
}

# ============================================
# 心跳守护进程
# ============================================

# 启动心跳守护进程
start_heartbeat_daemon() {
    local agent_id="${1:-$AGENT_ID}"
    local interval="${2:-$HEARTBEAT_INTERVAL}"

    log_hb "启动心跳守护进程 (Agent: $agent_id, 间隔: ${interval}s)"

    # 初始化心跳文件
    create_heartbeat_file "$agent_id"

    # 后台循环更新心跳
    (
        while true; do
            update_heartbeat "$agent_id" "${AGENT_STATUS:-active}" "${CURRENT_TASK:-}"

            # 提交心跳到 Git
            git add "$HEARTBEAT_DIR/" 2>/dev/null || true
            git commit -m "heartbeat: $agent_id" 2>/dev/null || true
            git push origin main -q 2>/dev/null || true

            sleep $interval
        done
    ) &

    local pid=$!
    echo $pid > "$HEARTBEAT_DIR/${agent_id}.pid"
    log_hb "心跳守护进程已启动 (PID: $pid)"
}

# 停止心跳守护进程
stop_heartbeat_daemon() {
    local agent_id="${1:-$AGENT_ID}"
    local pid_file="$HEARTBEAT_DIR/${agent_id}.pid"

    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        kill $pid 2>/dev/null || true
        rm -f "$pid_file"
        log_hb "心跳守护进程已停止 (PID: $pid)"
    fi
}

# 更新 Agent 状态
set_agent_status() {
    local status="$1"
    local current_task="${2:-}"

    export AGENT_STATUS="$status"
    export CURRENT_TASK="$current_task"

    update_heartbeat "${AGENT_ID}" "$status" "$current_task"
}

# 设置为活跃状态
set_active() {
    local task_id="${1:-}"
    set_agent_status "$AGENT_STATUS_ACTIVE" "$task_id"
}

# 设置为空闲状态
set_idle() {
    set_agent_status "$AGENT_STATUS_IDLE" ""
}

# 设置为等待状态
set_waiting() {
    set_agent_status "$AGENT_STATUS_WAITING" ""
}

# 设置为错误状态
set_error() {
    set_agent_status "$AGENT_STATUS_ERROR" ""
}

# ============================================
# 监控命令
# ============================================

# 显示所有 Agent 状态
show_all_agents() {
    echo "=========================================="
    echo "Agent 状态概览"
    echo "=========================================="

    for hb_file in "$HEARTBEAT_DIR"/*.yaml; do
        [ -e "$hb_file" ] || continue
        if [ -f "$hb_file" ]; then
            local agent_id=$(basename "$hb_file" .yaml)
            local role=$(grep "^role:" "$hb_file" | awk '{print $2}')
            local status=$(grep "^status:" "$hb_file" | awk '{print $2}')
            local current_task=$(grep "^current_task:" "$hb_file" | awk '{print $2}')
            local last_hb=$(grep "^last_heartbeat:" "$hb_file" | awk '{print $2}')

            local online="离线"
            if is_agent_online "$agent_id"; then
                online="在线"
            fi

            echo ""
            echo "Agent: $agent_id"
            echo "  角色: $role"
            echo "  状态: $status"
            echo "  在线: $online"
            echo "  当前任务: $current_task"
            echo "  最后心跳: $last_hb"
        fi
    done

    echo ""
    echo "=========================================="
}

# 初始化目录
init_heartbeat_dirs 2>/dev/null || true
