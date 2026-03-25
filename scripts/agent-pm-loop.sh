#!/bin/bash
# agent-pm-loop.sh - PM Agent 循环
#
# PM 角色：
# - 创建任务
# - 分配任务给 Coder
# - 监控任务进度
# - 处理 Coder 报告
# - 协调资源
#
# 用法: source scripts/agent-pm-loop.sh (由 agent-v0.2.sh 调用)

set -e

# ============================================
# PM 配置
# ============================================

PM_POLL_INTERVAL="${PM_POLL_INTERVAL:-60}"
PM_TASK_CHECK_INTERVAL="${PM_TASK_CHECK_INTERVAL:-300}"

# ============================================
# PM 初始化
# ============================================

pm_init() {
    log_role "PM Agent 初始化..."
    set_idle
    log_role "PM Agent 就绪"
}

# ============================================
# 任务管理
# ============================================

# 创建任务
pm_create_task() {
    local title="$1"
    local description="$2"
    local role="${3:-coder}"
    local priority="${4:-P1}"

    local task_id="task-$(date +%Y%m%d%H%M%S)"

    log_role "创建任务: $task_id - $title"

    create_task "$task_id" "$title" "$description" "$role" "$priority" "$AGENT_ID"

    echo "$task_id"
}

# 分配任务
pm_assign_task() {
    local task_id="$1"
    local target_agent="$2"

    log_role "分配任务: $task_id -> $target_agent"

    # 发送消息通知
    local task_file=$(get_task_file "$task_id")
    local title=$(grep "^title:" "$task_file" | cut -d: -f2- | sed 's/^ *//')

    send_task_assign "$AGENT_ID" "$target_agent" "$task_id" "$title"

    # 更新任务状态为已分配
    update_task_state "$task_id" "assigned" "$AGENT_ID"

    log_role "任务已分配: $task_id"
}

# 检查任务进度
pm_check_progress() {
    log_role "检查任务进度..."

    # 检查进行中的任务
    for task_file in .agent/tasks/in-progress/*.yaml; do
        [ -e "$task_file" ] || continue
        if [ -f "$task_file" ]; then
            local task_id=$(basename "$task_file" .yaml)
            local title=$(grep "^title:" "$task_file" | cut -d: -f2- | sed 's/^ *//')

            # 检查是否超时
            if is_task_timed_out "$task_id"; then
                log_warn "任务超时: $task_id - $title"

                # 检查 Agent 状态
                local lock_file=".agent/tasks/in-progress/${task_id}.lock"
                local owner=$(grep "^agent_id:" "$lock_file" | awk '{print $2}')

                if ! is_agent_online "$owner"; then
                    log_role "Agent $owner 离线，重新分配任务"
                    release_task "$task_id" "$AGENT_ID" "agent_offline"
                fi
            fi
        fi
    done

    # 检查待审查任务
    for task_file in .agent/tasks/review/*.yaml; do
        [ -e "$task_file" ] || continue
        if [ -f "$task_file" ]; then
            local task_id=$(basename "$task_file" .yaml)
            log_role "任务待审查: $task_id"
        fi
    done
}

# ============================================
# 消息处理
# ============================================

pm_handle_message() {
    local msg_file="$1"

    local msg_type=$(parse_message "$msg_file" "type")
    local from=$(parse_message "$msg_file" "from")

    log_role "处理消息: $msg_type (from: $from)"

    case "$msg_type" in
        review_result)
            pm_handle_review_result "$msg_file"
            ;;
        notification)
            pm_handle_notification "$msg_file"
            ;;
        *)
            log_role "未知消息类型: $msg_type"
            ;;
    esac
}

pm_handle_review_result() {
    local msg_file="$1"

    local task_id=$(grep "task_id:" "$msg_file" | head -1 | awk '{print $2}')
    local result=$(grep "result:" "$msg_file" | awk '{print $2}')

    log_role "审查结果: $task_id - $result"

    if [ "$result" = "approved" ]; then
        # 任务已完成
        log_role "任务完成: $task_id"
    else
        # 需要重新分配
        log_role "任务需要修改: $task_id"
    fi
}

pm_handle_notification() {
    local msg_file="$1"

    local subject=$(grep "subject:" "$msg_file" | cut -d: -f2- | sed 's/^ *//')

    log_role "通知: $subject"
}

# ============================================
# 任务规划
# ============================================

pm_plan_tasks() {
    # 检查是否有足够的待办任务
    local pending_count=$(find .agent/tasks/pending -name "*.yaml" 2>/dev/null | wc -l)
    local in_progress_count=$(find .agent/tasks/in-progress -name "*.yaml" 2>/dev/null | wc -l)

    log_role "任务统计: 待办=$pending_count, 进行中=$in_progress_count"

    # 如果待办任务不足，可以考虑创建新任务
    # 这里可以集成 AI 来生成任务
}

# ============================================
# 协调逻辑
# ============================================

pm_coordinate() {
    # 检查在线 Coder
    local coders=$(get_agents_by_role "coder")
    local coder_count=$(echo "$coders" | grep -c . || echo 0)

    log_role "在线 Coder 数量: $coder_count"

    # 检查在线 Reviewer
    local reviewers=$(get_agents_by_role "reviewer")
    local reviewer_count=$(echo "$reviewers" | grep -c . || echo 0)

    log_role "在线 Reviewer 数量: $reviewer_count"

    # 如果有任务但没有可用的 Coder，可以发出警告
    if [ $coder_count -eq 0 ]; then
        local pending_count=$(find .agent/tasks/pending -name "*.yaml" 2>/dev/null | wc -l)
        if [ $pending_count -gt 0 ]; then
            log_warn "有待办任务但没有在线的 Coder"
        fi
    fi
}

# ============================================
# 主循环
# ============================================

pm_main_loop() {
    log_role "=============================================="
    log_role "PM Agent 主循环启动"
    log_role "=============================================="

    local iteration=0
    local last_progress_check=0

    while true; do
        iteration=$((iteration + 1))
        log_role "========== 第 $iteration 轮 =========="

        # 1. 更新心跳
        update_heartbeat "$AGENT_ID" "active" ""

        # 2. 同步代码
        git_sync_pull

        # 3. 处理收件箱消息
        local unread=$(get_unread_messages "$AGENT_ID")
        if [ -n "$unread" ]; then
            for msg_file in $unread; do
                mark_message_read "$msg_file"
                pm_handle_message "$msg_file"
            done

            # 提交消息状态变更
            git add .agent/messages/ 2>/dev/null || true
            git commit -m "pm: 处理消息" 2>/dev/null || true
            git push origin main -q 2>/dev/null || true
        fi

        # 4. 定期检查任务进度
        local now=$(date +%s)
        if [ $((now - last_progress_check)) -gt $PM_TASK_CHECK_INTERVAL ]; then
            pm_check_progress
            last_progress_check=$now
        fi

        # 5. 任务规划
        pm_plan_tasks

        # 6. 协调
        pm_coordinate

        # 7. 提交心跳
        git add .agent/heartbeat/ 2>/dev/null || true
        git commit -m "heartbeat: $AGENT_ID (pm)" 2>/dev/null || true
        git push origin main -q 2>/dev/null || true

        # 8. 等待下一轮
        log_role "等待 ${PM_POLL_INTERVAL}s..."
        sleep $PM_POLL_INTERVAL
    done
}

# ============================================
# 入口
# ============================================

pm_init
pm_main_loop
