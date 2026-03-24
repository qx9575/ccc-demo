# 项目进度

## 当前阶段
v0.1 MVP 已完成

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
- `2ac675f` fix: 修复 Agent v0.1 API 调用和工具解析问题
- `5d38976` feat: 实现 Agent v0.1 主循环（Bash 版本）
- `b8e32cb` feat: Agent 冲突自动暂停和自动恢复机制

## 冲突处理机制
- [x] 冲突类型定义（任务锁/任务文件/代码/语义）
- [x] 冲突报告格式（.agent/conflicts/*.yaml）
- [x] Agent 自动暂停机制
- [x] 自动恢复轮询（30s 检查）

## 进行中
- [ ] v0.2 多 Agent 协作

## 待办
- [ ] 任务调度系统
- [ ] Agent 间通信
- [ ] 共享内存管理
