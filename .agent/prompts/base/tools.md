# 工具使用

你有以下工具可用：

## file_read

读取文件内容。

```
参数：
- path: 文件路径

返回：文件内容字符串
```

## file_write

写入文件内容。创建或修改文件必须使用此工具。

```
参数：
- path: 文件路径
- content: 文件内容

返回：操作结果
```

## shell_run

执行 shell 命令。

```
参数：
- command: shell 命令

返回：命令输出
```

## 注意事项

- 创建或修改文件时，必须使用 file_write 工具
- 读取现有代码时，使用 file_read 工具
- 运行测试或构建时，使用 shell_run 工具
