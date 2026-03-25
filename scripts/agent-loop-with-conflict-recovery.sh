#!/bin/bash
# agent-loop-with-conflict-recovery.sh
# Agent 执行循环（带冲突自动恢复）
#
# 用法: ./agent-loop-with-conflict-recovery.sh

set -e

# 配置
AGENT_ID="coder-$(hostname)"
AGENT_ROLE="coder"
WORKSPACE="/workspace"
POLL_INTERVAL=30

echo "=============================================="
echo "Agent 执行循环启动"
echo "Agent ID: $AGENT_ID"
echo "角色: $AGENT_ROLE"
echo "=============================================="

# 创建必要目录
mkdir -p .agent/conflicts
mkdir -p .agent/notifications
mkdir -p .agent/tasks/in-progress
mkdir -p .agent/archives/tasks
mkdir -p .agent/archives/tests
mkdir -p .agent/archives/commits

# 检查是否有未解决的冲突
check_pending_conflicts() {
    echo "检查是否有未解决的冲突..."

    # 查找当前 Agent 的未解决冲突
    for report in .agent/conflicts/*.yaml; do
        [ -e "$report" ] || continue
        if [ -f "$report" ]; then
            STATUS=$(grep "^status:" "$report" | awk '{print $2}')
            if [ "$STATUS" = "pending" ]; then
                echo "发现未解决的冲突: $report"
                wait_for_conflict_resolution "$report"
            fi
        fi
    done
}

# 等待冲突解决
wait_for_conflict_resolution() {
    local report="$1"
    local task_id=$(grep "^task_id:" "$report" | awk '{print $2}')

    echo "=============================================="
    echo "等待冲突解决"
    echo "冲突报告: $report"
    echo "任务 ID: $task_id"
    echo "=============================================="

    while true; do
        # 拉取最新代码
        git pull origin main -q 2>/dev/null || true

        # 检查冲突报告状态
        if [ -f "$report" ]; then
            STATUS=$(grep "^status:" "$report" | awk '{print $2}')

            if [ "$STATUS" = "resolved" ]; then
                echo "✅ 冲突已解决（status: resolved）"

                # 归档冲突报告
                mv "$report" .agent/conflicts/archived/ 2>/dev/null || true

                # 继续下一个任务
                return 0
            fi
        fi

        # 检查工作区是否还有冲突文件
        local remaining_conflicts=$(git diff --name-only --diff-filter=U 2>/dev/null | wc -l)

        if [ "$remaining_conflicts" -eq 0 ]; then
            echo "✅ 冲突已解决（无冲突文件）"

            # 更新冲突报告
            if [ -f "$report" ]; then
                sed -i 's/status: pending/status: resolved/' "$report"
                echo "resolved_by: human" >> "$report"
                echo "resolved_at: $(date -Iseconds)" >> "$report"
            fi

            return 0
        fi

        echo "[$(date '+%H:%M:%S')] 等待人工解决冲突... (${POLL_INTERVAL}s 后再次检查)"
        sleep $POLL_INTERVAL
    done
}

# 创建冲突报告
create_conflict_report() {
    local task_id="$1"
    local conflict_files="$2"

    mkdir -p .agent/conflicts

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local report=".agent/conflicts/${task_id}_${timestamp}.yaml"

    cat > "$report" << EOF
# 代码冲突报告
task_id: $task_id
agent_id: $AGENT_ID
detected_at: $(date -Iseconds)
status: pending

conflict_files:
$(for f in $conflict_files; do echo "  - $f"; done)

# 人工解决后更新
resolved_by: null
resolved_at: null
resolution_summary: null
EOF

    echo "$report"
}

# 通知人工
notify_human() {
    local task_id="$1"
    local conflict_files="$2"
    local report="$3"

    mkdir -p .agent/notifications

    cat >> .agent/notifications/alerts.txt << EOF

========================================
[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ 代码冲突需要人工处理
========================================
任务: $task_id
Agent: $AGENT_ID
冲突文件数: $(echo "$conflict_files" | wc -w)

冲突文件:
$(for f in $conflict_files; do echo "  - $f"; done)

冲突报告: $report

解决步骤:
1. 查看冲突文件: git diff --name-only --diff-filter=U
2. 编辑文件解决冲突
3. git add <files> && git commit && git push
4. 更新冲突报告状态为 resolved
EOF

    echo "通知已写入 .agent/notifications/alerts.txt"
}

# 查找可用任务
find_available_task() {
    # 查找未锁定的待办任务
    for task in .agent/tasks/pending/*.yaml; do
        [ -e "$task" ] || continue
        if [ -f "$task" ]; then
            local task_id=$(basename "$task" .yaml)
            local lock_file=".agent/tasks/in-progress/${task_id}.lock"

            # 检查是否有锁文件
            if [ ! -f "$lock_file" ]; then
                echo "$task_id"
                return 0
            fi

            # 检查锁是否过期（2小时）
            if [ -f "$lock_file" ]; then
                local expires=$(grep "expires_at:" "$lock_file" | awk '{print $2}')
                local expires_ts=$(date -d "$expires" +%s 2>/dev/null || echo 0)
                local now_ts=$(date +%s)

                if [ $now_ts -gt $expires_ts ]; then
                    echo "锁已过期，可以接管: $task_id"
                    rm -f "$lock_file"
                    echo "$task_id"
                    return 0
                fi
            fi
        fi
    done

    return 1
}

# 认领任务
claim_task() {
    local task_id="$1"

    local lock_file=".agent/tasks/in-progress/${task_id}.lock"
    local task_file=".agent/tasks/pending/${task_id}.yaml"

    # 创建锁文件
    cat > "$lock_file" << EOF
agent_id: $AGENT_ID
locked_at: $(date -Iseconds)
expires_at: $(date -Iseconds -d '+2 hours')
heartbeat: $(date -Iseconds)
EOF

    # 移动任务文件
    git mv "$task_file" ".agent/tasks/in-progress/" 2>/dev/null || true
    git add .agent/tasks/ .agent/conflicts/ 2>/dev/null || true
    git commit -m "chore: 认领任务 $task_id by $AGENT_ID" 2>/dev/null || true

    if git push origin main 2>&1; then
        echo "✅ 成功认领任务: $task_id"
        return 0
    else
        echo "❌ 认领失败，可能已被其他 Agent 认领"
        # 拉取最新状态
        git pull origin main -q
        return 1
    fi
}

# 执行任务（模拟）
execute_task() {
    local task_id="$1"

    echo ""
    echo "=============================================="
    echo "执行任务: $task_id"
    echo "=============================================="

    # 这里是任务执行逻辑
    # 实际实现中，这里会调用 LLM 来完成任务
    echo "执行中..."
    sleep 2

    echo "任务执行完成"
}

# 提交任务结果
commit_task_result() {
    local task_id="$1"

    # 提交代码
    git add . 2>/dev/null || true
    git commit -m "feat: 完成任务 $task_id by $AGENT_ID" 2>/dev/null || true

    # 尝试推送
    if git push origin main 2>&1; then
        echo "✅ 推送成功"
        return 0
    fi

    echo "推送失败，检查是否需要处理冲突..."

    # 拉取并尝试 rebase
    if git pull --rebase origin main 2>&1; then
        # 检查是否有冲突
        local conflict_files=$(git diff --name-only --diff-filter=U 2>/dev/null)

        if [ -n "$conflict_files" ]; then
            echo "=============================================="
            echo "⚠️ 检测到代码冲突！"
            echo "=============================================="
            echo "冲突文件："
            echo "$conflict_files"

            # 创建冲突报告
            local report=$(create_conflict_report "$task_id" "$conflict_files")
            echo "冲突报告: $report"

            # 提交冲突报告
            git add "$report" 2>/dev/null || true
            git commit -m "chore: 报告代码冲突 - $task_id" 2>/dev/null || true
            git push origin main 2>/dev/null || true

            # 通知人工
            notify_human "$task_id" "$conflict_files" "$report"

            # 等待冲突解决
            wait_for_conflict_resolution "$report"

            # 冲突解决后，重新提交
            git add . 2>/dev/null || true
            git rebase --continue 2>/dev/null || git commit --amend --no-edit 2>/dev/null || true
            git push origin main

            return 0
        fi

        # 无冲突，再次推送
        git push origin main
        return 0
    fi

    return 1
}

# 归档任务
archive_task() {
    local task_id="$1"

    local lock_file=".agent/tasks/in-progress/${task_id}.lock"
    local task_file=".agent/tasks/in-progress/${task_id}.yaml"

    # 调用归档脚本
    if [ -f "./scripts/archive-task.sh" ]; then
        bash ./scripts/archive-task.sh "$task_id" 2>/dev/null
    elif [ -f "/app/archive-task.sh" ]; then
        bash /app/archive-task.sh "$task_id" 2>/dev/null
    else
        # 简单归档：删除原文件
        rm -f "$task_file"
        rm -f "$lock_file"
    fi

    git add .agent/
    git commit -m "chore: 归档任务 $task_id (已完成)" 2>/dev/null || true
    git push origin main

    echo "✅ 任务归档: $task_id"
}

# 主循环
main() {
    # 检查是否有未解决的冲突
    check_pending_conflicts

    while true; do
        echo ""
        echo "=============================================="
        echo "$(date '+%Y-%m-%d %H:%M:%S') 开始新一轮循环"
        echo "=============================================="

        # 1. 同步代码
        git pull --rebase origin main -q 2>/dev/null || true

        # 2. 查找可用任务
        TASK_ID=$(find_available_task)

        if [ -z "$TASK_ID" ]; then
            echo "无可用任务，等待..."
            sleep $POLL_INTERVAL
            continue
        fi

        echo "发现可用任务: $TASK_ID"

        # 3. 认领任务
        if ! claim_task "$TASK_ID"; then
            sleep 5
            continue
        fi

        # 4. 执行任务
        execute_task "$TASK_ID"

        # 5. 提交结果
        if commit_task_result "$TASK_ID"; then
            # 6. 归档任务
            archive_task "$TASK_ID"
            echo "✅ 任务完成: $TASK_ID"
        else
            echo "❌ 任务提交失败: $TASK_ID"
        fi

        # 短暂休息
        sleep 5
    done
}

# 启动主循环
main
