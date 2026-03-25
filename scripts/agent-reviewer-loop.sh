#!/bin/bash
# agent-reviewer-loop.sh - Reviewer Agent 循环
#
# Reviewer 角色：
# - 接收审查请求
# - 审查代码变更
# - 提供审查意见
# - 批准或驳回任务
# - 维护代码质量
# - 归档完成的任务
#
# 用法: source scripts/agent-reviewer-loop.sh (由 agent-v0.2.sh 调用)

set -e

# ============================================
# Reviewer 配置
# ============================================

REVIEWER_POLL_INTERVAL="${REVIEWER_POLL_INTERVAL:-30}"
REVIEW_STANDARDS="${REVIEW_STANDARDS:-.agent/review-standards.md}"

# 加载归档工具
if [ -f "$SCRIPTS_DIR/archive-utils.sh" ]; then
    source "$SCRIPTS_DIR/archive-utils.sh"
elif [ -f "./scripts/archive-utils.sh" ]; then
    source "./scripts/archive-utils.sh"
fi

# ============================================
# Reviewer 初始化
# ============================================

reviewer_init() {
    log_role "Reviewer Agent 初始化..."
    set_idle

    # 加载审查标准
    if [ -f "$REVIEW_STANDARDS" ]; then
        export REVIEW_STANDARDS_CONTENT=$(cat "$REVIEW_STANDARDS")
        log_role "加载审查标准: $REVIEW_STANDARDS"
    else
        export REVIEW_STANDARDS_CONTENT="通用代码审查标准：
1. 代码风格一致性
2. 无明显 bug
3. 有适当的测试
4. 文档完整
5. 无安全问题"
    fi

    log_role "Reviewer Agent 就绪"
}

# ============================================
# 审查执行
# ============================================

# 获取变更内容
reviewer_get_changes() {
    local task_id="$1"
    local task_file=$(get_task_file "$task_id")

    # 获取任务变更的文件列表
    local changed_files=""

    # 方法1：从任务文件读取
    if [ -f "$task_file" ]; then
        changed_files=$(grep "changed_files:" -A 100 "$task_file" 2>/dev/null | grep "^  -" | sed 's/  - //')
    fi

    # 方法2：从 Git 历史获取
    if [ -z "$changed_files" ]; then
        changed_files=$(git diff --name-only HEAD~5 2>/dev/null || echo "")
    fi

    echo "$changed_files"
}

# 审查代码
reviewer_review_task() {
    local task_id="$1"
    local task_file=$(get_task_file "$task_id")

    if [ ! -f "$task_file" ]; then
        log_error "任务文件不存在: $task_id"
        echo "rejected|任务文件不存在"
        return 1
    fi

    log_role "=============================================="
    log_role "审查任务: $task_id"
    log_role "=============================================="

    # 更新状态
    set_active "$task_id"

    # 解析任务信息
    local title=$(grep "^title:" "$task_file" | cut -d: -f2- | sed 's/^ *//')
    local description=$(sed -n '/^description:/,/^[a-z_]*:/p' "$task_file" | head -n -1 | tail -n +2)

    log_role "标题: $title"

    # 获取变更文件
    local changed_files=$(reviewer_get_changes "$task_id")

    if [ -z "$changed_files" ]; then
        log_warn "未找到变更文件"
        echo "rejected|未找到代码变更。请确保已创建所需的代码文件。"
        return 1
    fi

    log_role "变更文件:"
    for f in $changed_files; do
        log_role "  - $f"
    done

    # 读取变更内容
    local changes_content=""
    for f in $changed_files; do
        if [ -f "$f" ]; then
            changes_content+="\n=== $f ===\n"
            changes_content+=$(cat "$f" 2>/dev/null || echo "无法读取文件")
            changes_content+="\n"
        fi
    done

    # 提取验收标准
    local acceptance_criteria=""
    local in_criteria=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^acceptance_criteria: ]]; then
            in_criteria=true
            continue
        fi
        if [ "$in_criteria" = true ]; then
            if [[ "$line" =~ ^[a-z_]+: ]] && [[ ! "$line" =~ ^[[:space:]]*- ]]; then
                break
            fi
            acceptance_criteria="$acceptance_criteria$line\n"
        fi
    done < "$task_file"

    # 构建 AI 审查提示词
    local prompt="你是$AGENT_NAME，一个资深的代码审查员。

请审查以下任务的代码变更：

任务 ID: $task_id
标题: $title
描述:
$description

验收标准:
$acceptance_criteria

审查标准：
$REVIEW_STANDARDS_CONTENT

变更内容：
$changes_content

请按以下格式输出审查结果：

## 审查结果
[approved / rejected]

## 审查意见
[详细的审查意见，必须包括：
- 代码质量评价
- 发现的具体问题（如果有）
- 改进建议（如果需要）
- 测试覆盖情况
- 验收标准完成情况]

## 决定
[最终决定及理由]"

    # 调用 AI 进行审查
    local review_result=$(chat "$prompt")

    log_role "审查结果:"
    echo "$review_result"

    # 解析审查结果
    local decision="approved"
    if echo "$review_result" | grep -qi "rejected\|驳回\|不通过"; then
        decision="rejected"
    fi

    # 返回决定和审查意见
    echo "$decision|$review_result"
}

# 发送审查结果
reviewer_send_result() {
    local task_id="$1"
    local result="$2"
    local comments="$3"
    local changed_files="$4"

    log_role "发送审查结果: $task_id - $result"

    # 获取任务的原作者
    local task_file=$(get_task_file "$task_id")
    local created_by=$(grep "^created_by:" "$task_file" | awk '{print $2}')
    local coder_id="$created_by"

    # 如果找不到作者，发送给 PM
    if [ -z "$coder_id" ]; then
        local pm_agents=$(get_agents_by_role "pm")
        coder_id=$(echo "$pm_agents" | head -1)
    fi

    # 发送审查结果消息
    send_review_result "$AGENT_ID" "$coder_id" "$task_id" "$result" "$comments" "$changed_files"

    # 更新任务状态
    if [ "$result" = "approved" ]; then
        approve_task "$task_id" "$AGENT_ID"
        log_role "任务已批准: $task_id"

        # 归档完成的任务
        if type archive_completed_task &>/dev/null; then
            archive_completed_task "$task_id"
        fi
    else
        reject_task "$task_id" "$AGENT_ID" "$comments"
        log_role "任务已驳回: $task_id"
    fi
}

# ============================================
# 消息处理
# ============================================

reviewer_handle_message() {
    local msg_file="$1"

    local msg_type=$(parse_message "$msg_file" "type")
    local from=$(parse_message "$msg_file" "from")

    log_role "处理消息: $msg_type (from: $from)"

    case "$msg_type" in
        review_request)
            reviewer_handle_review_request "$msg_file"
            ;;
        notification)
            reviewer_handle_notification "$msg_file"
            ;;
        *)
            log_role "未知消息类型: $msg_type"
            ;;
    esac
}

reviewer_handle_review_request() {
    local msg_file="$1"

    local task_id=$(grep "task_id:" "$msg_file" | head -1 | awk '{print $2}')
    local from=$(parse_message "$msg_file" "from")

    log_role "收到审查请求: $task_id (from: $from)"

    # 确认消息
    acknowledge_message "$msg_file" "accepted"

    # 确保任务在审查状态
    local state=$(get_task_state "$task_id")
    if [ "$state" != "review" ]; then
        log_role "任务状态不正确: $state，尝试更新"
        # 尝试更新状态
        update_task_state "$task_id" "review" "$AGENT_ID"
    fi

    # 执行审查
    local review_output=$(reviewer_review_task "$task_id")
    local decision=$(echo "$review_output" | cut -d'|' -f1)
    local review_comments=$(echo "$review_output" | cut -d'|' -f2-)

    # 获取变更文件
    local changed_files=$(reviewer_get_changes "$task_id")

    # 发送审查结果
    local comments=""
    if [ "$decision" = "approved" ]; then
        comments="代码审查通过。\n\n$review_comments"
    else
        # 提取审查意见中的关键问题
        local specific_issues=$(echo "$review_comments" | grep -A 10 "## 审查意见" | head -20)
        comments="代码需要修改。\n\n具体问题：\n$specific_issues"
    fi

    reviewer_send_result "$task_id" "$decision" "$comments" "$changed_files"

    # 提交审查结果
    git add -A 2>/dev/null || true
    git commit -m "review: $task_id - $decision by $AGENT_ID" 2>/dev/null || true
    git push origin main -q 2>/dev/null || true
}

reviewer_handle_notification() {
    local msg_file="$1"

    local subject=$(grep "subject:" "$msg_file" | cut -d: -f2- | sed 's/^ *//')

    log_role "通知: $subject"
    acknowledge_message "$msg_file" "read"
}

# ============================================
# 主动审查
# ============================================

reviewer_check_review_queue() {
    log_role "检查审查队列..."

    # 检查待审查任务
    for task_file in .agent/tasks/review/*.yaml; do
        [ -e "$task_file" ] || continue
        if [ -f "$task_file" ]; then
            local task_id=$(basename "$task_file" .yaml)
            local title=$(grep "^title:" "$task_file" | cut -d: -f2- | sed 's/^ *//')

            log_role "发现待审查任务: $task_id - $title"

            # 执行审查
            local review_output=$(reviewer_review_task "$task_id")
            local decision=$(echo "$review_output" | cut -d'|' -f1)
            local review_comments=$(echo "$review_output" | cut -d'|' -f2-)

            # 获取变更文件
            local changed_files=$(reviewer_get_changes "$task_id")

            # 发送审查结果
            local comments=""
            if [ "$decision" = "approved" ]; then
                comments="代码审查通过。\n\n$review_comments"
            else
                # 提取审查意见中的关键问题
                local specific_issues=$(echo "$review_comments" | grep -A 10 "## 审查意见" | head -20)
                comments="代码需要修改。\n\n具体问题：\n$specific_issues"
            fi

            reviewer_send_result "$task_id" "$decision" "$comments" "$changed_files"

            # 提交审查结果
            git add -A 2>/dev/null || true
            git commit -m "review: $task_id - $decision by $AGENT_ID" 2>/dev/null || true
            git push origin main -q 2>/dev/null || true

            # 一次只处理一个任务
            break
        fi
    done
}

# ============================================
# 主循环
# ============================================

reviewer_main_loop() {
    log_role "=============================================="
    log_role "Reviewer Agent 主循环启动"
    log_role "=============================================="

    local iteration=0

    while true; do
        iteration=$((iteration + 1))
        log_role "========== 第 $iteration 轮 =========="

        # 1. 更新心跳
        update_heartbeat "$AGENT_ID" "${AGENT_STATUS:-idle}" "${CURRENT_TASK:-}"

        # 2. 同步代码
        git_sync_pull

        # 3. 处理收件箱消息
        local unread=$(get_unread_messages "$AGENT_ID")
        if [ -n "$unread" ]; then
            for msg_file in $unread; do
                mark_message_read "$msg_file"
                reviewer_handle_message "$msg_file"
            done

            # 提交消息状态变更
            git add .agent/messages/ 2>/dev/null || true
            git commit -m "reviewer: 处理消息" 2>/dev/null || true
            git push origin main -q 2>/dev/null || true
        fi

        # 4. 主动检查审查队列
        if [ -z "$CURRENT_TASK" ]; then
            reviewer_check_review_queue
        fi

        # 5. 提交心跳
        git add .agent/heartbeat/ 2>/dev/null || true
        git commit -m "heartbeat: $AGENT_ID (reviewer)" 2>/dev/null || true
        git push origin main -q 2>/dev/null || true

        # 6. 设置状态
        set_idle

        # 7. 等待下一轮
        log_role "等待 ${REVIEWER_POLL_INTERVAL}s..."
        sleep $REVIEWER_POLL_INTERVAL
    done
}

# ============================================
# 入口
# ============================================

reviewer_init
reviewer_main_loop
