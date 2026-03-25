# 项目进度

## 当前阶段
v0.2 多 Agent 协作已完成

## v0.2 多 Agent 协作完成情况
- [x] PM/Coder/Reviewer 三角色协作
- [x] 文件级消息传递（inbox/outbox）
- [x] 心跳监控（在线检测）
- [x] 任务状态机（pending → in-progress → review → completed）
- [x] 原子任务认领（锁机制）
- [x] Git 同步与冲突处理
- [x] 多模型支持（GLM/GPT/DeepSeek/Kimi）
- [x] Docker Compose 多容器部署
- [x] SSH 支持（Git push）

## v0.2 已测试功能
| 功能 | 状态 | 说明 |
|------|------|------|
| 任务认领 | ✅ | 原子锁机制正常 |
| 任务状态流转 | ✅ | pending→in-progress→review→completed |
| Agent 间消息 | ✅ | 消息发送/读取/确认 |
| 心跳监控 | ✅ | 30s 更新，离线检测 |
| Git 同步 | ✅ | pull/push/冲突重试 |
| 多模型 API | ✅ | GLM/GPT/DeepSeek/Kimi |
| Docker 部署 | ✅ | 三个容器同时运行 |

## v0.1 MVP 完成情况
- [x] GLM Provider（OpenAI 兼容接口）
- [x] QPS 限流重试机制（指数退避）
- [x] Git 同步（pull/push）
- [x] CLI 交互模式
- [x] 工具调用（file_read, file_write, shell_run）
- [x] Docker 镜像构建
- [x] Docker Compose 配置

## 已测试功能
| 功能 | 状态 | 说明 |
|------|------|------|
| chat 对话 | ✅ | GLM-5 正常响应 |
| file_read | ✅ | 读取文件成功 |
| file_write | ✅ | 写入文件成功 |
| shell_run | ✅ | 执行命令成功 |
| QPS 重试 | ✅ | 5s→10s→20s 指数退避 |
| Docker 构建 | ✅ | 23.2MB Alpine 镜像 |
| Docker Compose | ✅ | 容器正常运行 |
| 交互模式 | ✅ | attach/exec 均可用 |

## 文档
- [使用指南](../docs/usage.md) - Docker 命令详解、attach 原理、参数解析流程

## Git 提交记录
### v0.2
- `d23a2ee` review: 多 Agent 协作测试运行
- `0785523` chore: 任务认领流程修复
- 多次 Agent 自动提交（任务认领、状态流转、心跳更新）

### v0.1
- `2ac675f` fix: 修复 Agent v0.1 API 调用和工具解析问题
- `5d38976` feat: 实现 Agent v0.1 主循环（Bash 版本）
- `b8e32cb` feat: Agent 冲突自动暂停和自动恢复机制

## Bug 修复
### 2026-03-25 任务认领失败修复
**问题**: `find_available_tasks` 返回空任务 ID
**原因**: `git_sync_pull` 的日志输出污染了函数返回值
**解决**: 将日志输出重定向到 stderr (`>&2`)
**影响文件**: `scripts/agent-coordinator.sh`

### 2026-03-25 BusyBox 日期兼容
**问题**: Alpine 容器中 `date -Iseconds -d "+7200 seconds"` 不支持
**解决**: 添加 `get_iso_timestamp()` 和 `get_future_timestamp()` 辅助函数
**影响文件**: `scripts/agent-coordinator.sh`

### 2026-03-25 Docker SSH 支持
**问题**: 容器无法 Git push（缺少 SSH 客户端）
**解决**: Dockerfile 添加 `openssh-client`，docker-compose 挂载 `~/.ssh`
**影响文件**: `Dockerfile`, `docker-compose.yaml`

## 冲突处理机制
- [x] 冲突类型定义（任务锁/任务文件/代码/语义）
- [x] 冲突报告格式（.agent/conflicts/*.yaml）
- [x] Agent 自动暂停机制
- [x] 自动恢复轮询（30s 检查）

## 进行中
- [ ] v0.3 Python 版本（计划中）

## 待办
- [ ] 数据库持久化
- [ ] Web UI 界面
- [ ] 更多 LLM 模型支持
