# Git 提交规范

提交消息格式：

```
<type>(<task-id>): <subject>

<body>

Related: <task-id>
Files: <changed-files>
Tests: <test-status>

Co-Authored-By: <agent-id>
```

## 提交类型

| 类型 | 说明 | 触发关键词 |
|------|------|-----------|
| feat | 新功能 | 默认 |
| fix | Bug 修复 | 修复、fix、bug |
| refactor | 重构 | 重构、refactor |
| docs | 文档 | 文档、doc、readme |
| test | 测试 | 测试、test |
| chore | 构建/工具 | - |

## 类型判断规则

根据任务标题关键词自动判断提交类型：

- 包含 "修复"、"fix"、"bug" -> `fix`
- 包含 "重构"、"refactor" -> `refactor`
- 包含 "文档"、"doc"、"readme" -> `docs`
- 包含 "测试"、"test" -> `test`
- 其他情况 -> `feat`

## 提交示例

```
feat(task-006): 实现数组工具函数

完成任务 task-006：
- 创建 src/array_utils.py 模块
- 实现 flatten() 展平嵌套列表
- 实现 unique() 列表去重保序

Related: task-006
Files: src/array_utils.py, tests/test_array_utils.py
Tests: passed (12/12)

Co-Authored-By: coder-agent-1
```
