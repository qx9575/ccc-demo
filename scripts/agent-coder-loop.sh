#!/bin/bash
# agent-coder-loop.sh - Coder Agent 循环
#
# Coder 角色：
# - 接收任务分配
# - 执行编码任务
# - 提交代码
# - 请求代码审查
# - 处理审查反馈
# - 归档完成的任务
#
# 用法: source scripts/agent-coder-loop.sh (由 agent-v0.2.sh 调用)

set -e

# ============================================
# Coder 配置
# ============================================

CODER_POLL_INTERVAL="${CODER_POLL_INTERVAL:-30}"
CODER_HEARTBEAT_INTERVAL="${CODER_HEARTBEAT_INTERVAL:-60}"
MAX_RETRIES="${MAX_RETRIES:-3}"

# 加载归档工具
if [ -f "$SCRIPTS_DIR/archive-utils.sh" ]; then
    source "$SCRIPTS_DIR/archive-utils.sh"
elif [ -f "./scripts/archive-utils.sh" ]; then
    source "./scripts/archive-utils.sh"
fi

# ============================================
# Coder 初始化
# ============================================

coder_init() {
    log_role "Coder Agent 初始化..."
    set_idle
    log_role "Coder Agent 就绪"
}

# ============================================
# 任务执行
# ============================================

# 执行任务
coder_execute_task() {
    local task_id="$1"
    local task_file=$(get_task_file "$task_id")

    if [ ! -f "$task_file" ]; then
        log_error "任务文件不存在: $task_id"
        return 1
    fi

    log_role "=============================================="
    log_role "执行任务: $task_id"
    log_role "=============================================="

    # 解析任务
    local title=$(grep "^title:" "$task_file" | cut -d: -f2- | sed 's/^ *//')
    local description=$(sed -n '/^description:/,/^[a-z_]*:/p' "$task_file" | head -n -1 | tail -n +2)

    log_role "标题: $title"
    log_role "描述: $description"

    # 更新状态为活跃
    set_active "$task_id"

    # 构建 AI 提示词
    local prompt="你必须使用 file_write 工具来完成此任务。不要只是描述代码，必须实际调用工具创建文件。

任务 ID: $task_id
标题: $title
描述:
$description

请按照以下步骤执行（必须使用工具）：
1. 使用 file_write 工具创建 src/ 目录下的代码文件
2. 使用 file_write 工具创建 tests/ 目录下的测试文件
3. 使用 shell_run 工具运行测试验证

重要提示：
- 你必须实际调用 file_write 工具来创建文件
- 不要只返回代码内容，必须调用工具
- 示例：调用 file_write(filename=\"src/string_utils.py\", content=\"...\") 创建文件

现在开始执行任务。"

    # 调用 AI 执行任务
    log_role "调用 AI 执行任务..."
    log_info "提示词长度: ${#prompt} 字符"

    # chat 函数的日志输出会被 $() 捕获，所以直接调用
    chat "$prompt"

    # 检查执行结果
    if [ $? -eq 0 ]; then
        log_role "任务执行完成: $task_id"
        return 0
    else
        log_error "任务执行失败: $task_id"
        return 1
    fi
}

# 验证任务完成情况
coder_verify_task_completion() {
    local task_id="$1"
    local task_file=$(get_task_file "$task_id")

    log_role "验证任务完成情况: $task_id"

    local verification_passed=true
    local missing_items=""

    # 提取任务描述和验收标准
    local title=$(grep "^title:" "$task_file" | cut -d: -f2- | sed 's/^ *//')
    local description=$(sed -n '/^description:/,/^[a-z_]*:/p' "$task_file" | head -n -1 | tail -n +2)
    local acceptance_criteria=$(sed -n '/^acceptance_criteria:/,/^[a-z_]*:/p' "$task_file" | head -n -1 | tail -n +2)

    # 获取 git 变更
    local git_status=$(git status --porcelain 2>/dev/null)
    local git_diff=$(git diff --name-only HEAD 2>/dev/null)
    local all_changes="$git_status\n$git_diff"

    log_role "检查代码变更..."

    # 检查是否有变更
    if [ -z "$git_status" ] && [ -z "$git_diff" ]; then
        log_warn "没有检测到任何代码变更"
        verification_passed=false
        missing_items="$missing_items\n- 没有任何代码变更"
    else
        log_role "检测到变更文件:"
        echo -e "$all_changes" | grep -v '^$' | while read -r line; do
            log_role "  $line"
        done
    fi

    # 解析任务描述中提到的文件/模块
    local mentioned_items=""

    # 从标题提取
    mentioned_items="$mentioned_items $title"

    # 从描述提取关键词
    mentioned_items="$mentioned_items $(echo "$description" | grep -oE '[a-zA-Z_][a-zA-Z0-9_]*\.(py|js|ts|go|java|rs|sh|yaml|yml|json|md|txt)' || true)"

    # 从验收标准提取
    mentioned_items="$mentioned_items $(echo "$acceptance_criteria" | grep -oE '[a-zA-Z_][a-zA-Z0-9_]*\.(py|js|ts|go|java|rs|sh|yaml|yml|json|md|txt)' || true)"

    # 提取描述中的模块名（如 datetime_utils, calculator）
    local module_names=$(echo "$description $acceptance_criteria" | grep -oE '(src/|tests/)?[a-zA-Z_][a-zA-Z0-9_]*' | sort -u || true)

    log_role "任务涉及模块: $(echo $module_names | tr '\n' ' ')"

    # 验证每个提到的文件/模块
    for item in $mentioned_items; do
        # 跳过常见的非文件关键词
        case "$item" in
            "任务"|"文件"|"目录"|"函数"|"测试"|"创建"|"实现"|"编写"|"添加"|"更新"|"修改")
                continue
                ;;
        esac

        # 检查是否是文件名
        if [[ "$item" =~ \. ]]; then
            local found=false

            # 检查变更列表
            if echo -e "$all_changes" | grep -q "$item"; then
                found=true
                log_role "  ✓ 找到变更: $item"
            else
                # 在文件系统中查找
                for dir in src tests . ; do
                    if [ -f "$dir/$item" ]; then
                        found=true
                        log_role "  ✓ 找到文件: $dir/$item"
                        break
                    fi
                done
            fi

            if [ "$found" = false ]; then
                log_role "  ✗ 未找到: $item"
                verification_passed=false
                missing_items="$missing_items\n- 缺少: $item"
            fi
        fi
    done

    # 验证模块对应的文件是否存在
    for module in $module_names; do
        # 跳过短名称和常见词
        if [ ${#module} -lt 4 ]; then
            continue
        fi

        case "$module" in
            "src"|"tests"|"目录"|"文件"|"任务"|"标准"|"描述")
                continue
                ;;
        esac

        # 检查是否已有匹配的变更
        if echo -e "$all_changes" | grep -qi "$module"; then
            log_role "  ✓ 变更匹配模块: $module"
            continue
        fi

        # 检查常见文件命名模式
        local patterns=(
            "src/${module}.py"
            "src/${module}.js"
            "src/${module}.ts"
            "tests/test_${module}.py"
            "tests/${module}_test.py"
            "tests/test-${module}.js"
            "${module}.py"
        )

        local module_found=false
        for pattern in "${patterns[@]}"; do
            if [ -f "$pattern" ]; then
                module_found=true
                log_role "  ✓ 找到模块文件: $pattern"
                break
            fi
        done

        # 如果模块名在描述中被强调但没有对应文件
        if [ "$module_found" = false ]; then
            # 检查是否在描述中被明确要求
            if echo "$description $acceptance_criteria" | grep -qi "创建.*$module\|编写.*$module\|实现.*$module"; then
                log_role "  ⚠ 需要创建: $module"
                # 不强制失败，因为可能已经在变更中
            fi
        fi
    done

    # 检查验收标准中的关键要求
    log_role "检查验收标准..."

    # 检查是否有新文件（针对"创建文件"类标准）
    if echo "$acceptance_criteria" | grep -qi "创建\|编写\|新增\|添加文件"; then
        local new_files=$(git status --porcelain | grep "^??" | wc -l)
        local modified_files=$(git status --porcelain | grep "^[AM]" | wc -l)

        if [ "$new_files" -eq 0 ] && [ "$modified_files" -eq 0 ]; then
            log_role "  ✗ 未检测到新增或修改的文件"
            verification_passed=false
            missing_items="$missing_items\n- 没有新增或修改的文件"
        else
            log_role "  ✓ 检测到 $((new_files + modified_files)) 个文件变更"
        fi
    fi

    # 检查测试要求
    if echo "$acceptance_criteria" | grep -qi "测试\|test"; then
        local test_changes=$(echo -e "$all_changes" | grep -i "test" || true)
        if [ -n "$test_changes" ]; then
            log_role "  ✓ 检测到测试文件变更"
        else
            # 检查是否有测试目录
            if ls tests/*.py tests/*.js 2>/dev/null | head -1 | grep -q .; then
                log_role "  ⚠ 测试目录存在但无新测试变更"
            else
                log_role "  ✗ 验收标准要求测试但未检测到测试变更"
                verification_passed=false
                missing_items="$missing_items\n- 缺少测试文件"
            fi
        fi
    fi

    # 最终结果
    if [ "$verification_passed" = true ]; then
        log_role "✅ 任务验证通过"
        return 0
    else
        log_error "❌ 任务验证失败"
        if [ -n "$missing_items" ]; then
            log_error "缺失项目:$missing_items"
        fi
        return 1
    fi
}

# 提交代码
coder_commit_changes() {
    local task_id="$1"

    log_role "提交代码变更..."

    # 检查是否有变更
    local changes=$(git status -s)
    if [ -z "$changes" ]; then
        log_role "没有代码变更"
        return 0
    fi

    # 显示变更
    log_role "变更文件:"
    echo "$changes" | while read -r line; do
        log_role "  $line"
    done

    # 提交代码
    git add -A
    git commit -m "feat: 完成任务 $task_id by $AGENT_ID"

    # 尝试推送
    if git push origin main 2>&1; then
        log_role "代码推送成功"
        return 0
    fi

    # 处理推送冲突
    log_warn "推送失败，处理冲突..."

    # 拉取并 rebase
    if git pull --rebase origin main 2>&1; then
        # 检查是否有冲突
        local conflicts=$(git diff --name-only --diff-filter=U 2>/dev/null | wc -l)

        if [ "$conflicts" -gt 0 ]; then
            log_error "存在代码冲突，需要人工介入"
            # 创建冲突报告
            create_conflict_report "$task_id" "$(git diff --name-only --diff-filter=U)"
            return 1
        fi

        # 再次推送
        git push origin main
        log_role "代码推送成功"
        return 0
    fi

    log_error "代码提交失败"
    return 1
}

# 请求审查
coder_request_review() {
    local task_id="$1"

    log_role "请求代码审查: $task_id"

    # 获取变更文件
    local changed_files=$(git diff --name-only HEAD~1 2>/dev/null || echo "")

    # 查找可用的 Reviewer
    local reviewers=$(get_agents_by_role "reviewer")
    local reviewer=""
    for r in $reviewers; do
        if is_agent_online "$r"; then
            reviewer="$r"
            break
        fi
    done

    if [ -z "$reviewer" ]; then
        log_warn "没有可用的 Reviewer，任务将保持待审查状态"
        # 提交到审查队列
        submit_for_review "$task_id" "$AGENT_ID"
        return 0
    fi

    # 发送审查请求
    local summary="任务 $task_id 已完成，请审查"
    send_review_request "$AGENT_ID" "$reviewer" "$task_id" "$summary" "$changed_files"

    # 提交到审查状态
    submit_for_review "$task_id" "$AGENT_ID"

    log_role "审查请求已发送给: $reviewer"
}

# ============================================
# 冲突处理
# ============================================

create_conflict_report() {
    local task_id="$1"
    local conflict_files="$2"

    mkdir -p .agent/conflicts

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local report=".agent/conflicts/${task_id}_${timestamp}.yaml"

    cat > "$report" << EOF
task_id: $task_id
agent_id: $AGENT_ID
detected_at: $(date -Iseconds)
status: pending

conflict_files:
$(for f in $conflict_files; do echo "  - $f"; done)

resolution:
  resolved_by: null
  resolved_at: null
  summary: null
EOF

    log_role "创建冲突报告: $report"
    echo "$report"
}

wait_for_conflict_resolution() {
    local report="$1"

    log_role "等待冲突解决..."

    while true; do
        git pull origin main -q 2>/dev/null || true

        if [ -f "$report" ]; then
            local status=$(grep "^status:" "$report" | awk '{print $2}')
            if [ "$status" = "resolved" ]; then
                log_role "冲突已解决"
                return 0
            fi
        fi

        # 检查工作区是否还有冲突
        local remaining=$(git diff --name-only --diff-filter=U 2>/dev/null | wc -l)
        if [ "$remaining" -eq 0 ]; then
            log_role "冲突已解决（无冲突文件）"

            if [ -f "$report" ]; then
                sed -i 's/status: pending/status: resolved/' "$report"
                echo "resolved_by: $AGENT_ID" >> "$report"
                echo "resolved_at: $(date -Iseconds)" >> "$report"
            fi

            return 0
        fi

        log_role "等待冲突解决... (${CODER_POLL_INTERVAL}s)"
        sleep $CODER_POLL_INTERVAL
    done
}

# ============================================
# 消息处理
# ============================================

coder_handle_message() {
    local msg_file="$1"

    local msg_type=$(parse_message "$msg_file" "type")
    local from=$(parse_message "$msg_file" "from")

    log_role "处理消息: $msg_type (from: $from)"

    case "$msg_type" in
        task_assign)
            coder_handle_task_assign "$msg_file"
            ;;
        review_result)
            coder_handle_review_result "$msg_file"
            ;;
        notification)
            coder_handle_notification "$msg_file"
            ;;
        *)
            log_role "未知消息类型: $msg_type"
            ;;
    esac
}

coder_handle_task_assign() {
    local msg_file="$1"

    local task_id=$(grep "task_id:" "$msg_file" | head -1 | awk '{print $2}')
    local task_title=$(grep "task_title:" "$msg_file" | awk '{print $2}')

    log_role "收到任务分配: $task_id - $task_title"

    # 确认消息
    acknowledge_message "$msg_file" "accepted"

    # 尝试认领任务
    if claim_task "$task_id" "$AGENT_ID"; then
        log_role "成功认领任务: $task_id"
        export CURRENT_TASK="$task_id"

        # 执行任务
        if coder_execute_task "$task_id"; then
            # 提交代码
            if coder_commit_changes "$task_id"; then
                # 请求审查
                coder_request_review "$task_id"
            fi
        else
            # 任务执行失败，释放任务
            release_task "$task_id" "$AGENT_ID" "execution_failed"
        fi

        export CURRENT_TASK=""
    else
        log_role "任务已被其他 Agent 认领: $task_id"
    fi
}

coder_handle_review_result() {
    local msg_file="$1"

    local task_id=$(grep "task_id:" "$msg_file" | head -1 | awk '{print $2}')
    local result=$(grep "result:" "$msg_file" | awk '{print $2}')

    log_role "收到审查结果: $task_id - $result"

    # 确认消息
    acknowledge_message "$msg_file" "received"

    if [ "$result" = "approved" ]; then
        log_role "任务通过审查: $task_id"

        # 归档完成的任务
        if type archive_completed_task &>/dev/null; then
            archive_completed_task "$task_id"
        fi

        # 任务已完成，由 Reviewer 更新状态
    else
        log_role "任务需要修改: $task_id"

        # 读取审查意见
        local comments=$(sed -n '/comments:/,/^[a-z_]*:/p' "$msg_file" | head -n -1 | tail -n +2)
        log_role "审查意见: $comments"

        # 任务会被放回 in-progress 状态，需要修改
        # 下一轮循环会处理
    fi
}

coder_handle_notification() {
    local msg_file="$1"

    local subject=$(grep "subject:" "$msg_file" | cut -d: -f2- | sed 's/^ *//')

    log_role "通知: $subject"
    acknowledge_message "$msg_file" "read"
}

# ============================================
# 主循环
# ============================================

coder_main_loop() {
    log_role "=============================================="
    log_role "Coder Agent 主循环启动"
    log_role "=============================================="

    local iteration=0

    while true; do
        iteration=$((iteration + 1))
        log_role "========== 第 $iteration 轮 =========="

        # 1. 更新心跳
        update_heartbeat "$AGENT_ID" "${AGENT_STATUS:-idle}" "${CURRENT_TASK:-}"

        # 2. 同步代码
        git_sync_pull

        # 3. 检查是否有未解决的冲突
        if [ -n "$CURRENT_TASK" ]; then
            local conflict_report=".agent/conflicts/${CURRENT_TASK}_*.yaml"
            for report in $conflict_report; do
                [ -e "$report" ] || continue
                if [ -f "$report" ]; then
                    local status=$(grep "^status:" "$report" | awk '{print $2}')
                    if [ "$status" = "pending" ]; then
                        wait_for_conflict_resolution "$report"
                    fi
                fi
            done
        fi

        # 4. 处理收件箱消息
        local unread=$(get_unread_messages "$AGENT_ID")
        if [ -n "$unread" ]; then
            for msg_file in $unread; do
                mark_message_read "$msg_file"
                coder_handle_message "$msg_file"
            done

            # 提交消息状态变更
            git add .agent/messages/ 2>/dev/null || true
            git commit -m "coder: 处理消息" 2>/dev/null || true
            git push origin main -q 2>/dev/null || true
        fi

        # 5. 如果没有当前任务，查找可用任务
        if [ -z "$CURRENT_TASK" ]; then
            local available=$(find_available_tasks "coder" 1)
            if [ -n "$available" ]; then
                local task_id=$(echo "$available" | head -1)
                log_role "发现可用任务: $task_id"

                if claim_task "$task_id" "$AGENT_ID"; then
                    export CURRENT_TASK="$task_id"

                    # 执行任务
                    if coder_execute_task "$task_id"; then
                        # 验证任务完成情况
                        if coder_verify_task_completion "$task_id"; then
                            # 提交代码
                            if coder_commit_changes "$task_id"; then
                                # 请求审查
                                coder_request_review "$task_id"
                            fi
                        else
                            log_error "任务验证失败，请检查是否创建了所需文件"
                            release_task "$task_id" "$AGENT_ID" "verification_failed"
                        fi
                    else
                        release_task "$task_id" "$AGENT_ID" "execution_failed"
                    fi

                    export CURRENT_TASK=""
                fi
            fi
        fi

        # 6. 处理需要修改的任务
        for task_file in .agent/tasks/in-progress/*.yaml; do
            [ -e "$task_file" ] || continue
            if [ -f "$task_file" ]; then
                local task_id=$(basename "$task_file" .yaml)
                local status=$(grep "^status:" "$task_file" | awk '{print $2}')

                if [ "$status" = "changes_requested" ]; then
                    log_role "处理需要修改的任务: $task_id"

                    # 获取所有审查意见（可能有多次驳回）
                    local comments=$(grep "rejection_reason:" "$task_file" | tail -1 | cut -d: -f2- | sed 's/^ *//')
                    local all_reviews=$(grep -A 5 "^review:" "$task_file" | tail -10)
                    log_role "审查意见: $comments"
                    log_role "历史审查: $all_reviews"

                    # 执行修改
                    export CURRENT_TASK="$task_id"
                    set_active "$task_id"

                    if coder_execute_task "$task_id"; then
                        # 验证修改是否完成
                        if coder_verify_task_completion "$task_id"; then
                            if coder_commit_changes "$task_id"; then
                                coder_request_review "$task_id"
                            fi
                        else
                            log_error "修改后仍未满足验收标准"
                            release_task "$task_id" "$AGENT_ID" "verification_failed"
                        fi
                    fi

                    export CURRENT_TASK=""
                fi
            fi
        done

        # 7. 提交心跳
        git add .agent/heartbeat/ 2>/dev/null || true
        git commit -m "heartbeat: $AGENT_ID (coder)" 2>/dev/null || true
        git push origin main -q 2>/dev/null || true

        # 8. 设置状态
        if [ -z "$CURRENT_TASK" ]; then
            set_idle
        fi

        # 9. 等待下一轮
        log_role "等待 ${CODER_POLL_INTERVAL}s..."
        sleep $CODER_POLL_INTERVAL
    done
}

# ============================================
# 入口
# ============================================

# 不在这里调用，由 agent-v0.2.sh 在加载完所有函数后调用
# coder_init
# coder_main_loop
