# Privacy and Release Scope / 隐私与发布边界

[简体中文](#简体中文) | [English](#english)

## 简体中文

公开仓库只应包含可复用的控制器代码、许可、来源记录和通用文档。以下内容不得提交：

- 用户名、主机名、邮箱、Windows SID、GPU UUID 和本机绝对路径。
- API key、token、Cookie、密码、私钥、`.env` 和凭据配置。
- 模型权重、`.ninfer`、`.gguf`、运行时 EXE/DLL、转换器 Python 环境和下载缓存。
- 第三方客户端的聊天、世界书、角色卡、记忆数据库、导入文件和截图。
- Codex 任务日志、stdout/stderr、进程号、性能原始数据和临时脚本。

发布前应在隔离目录扫描：

```powershell
rg -n -i '(C:\\Users|D:\\AI|api[_-]?key|bearer|password|secret|private key|token)' .
```

这只是模式扫描，不是隐私审计。看到匹配项应逐项判断是第三方许可证中的示例、公开标识，还是实际用户数据。提交前再检查 `git status`、`git diff --cached --stat` 和暂存区文件清单。

## English

A public repository should contain reusable controller code, licenses, provenance, and general documentation only. Never commit:

- Usernames, hostnames, email addresses, Windows SIDs, GPU UUIDs, or machine-local absolute paths.
- API keys, tokens, cookies, passwords, private keys, `.env` files, or credential stores.
- Model weights, `.ninfer`/`.gguf` files, runtime EXE/DLL files, converter Python environments, or download caches.
- Third-party client chats, lorebooks, character cards, memory databases, imports, or screenshots.
- Codex task logs, stdout/stderr, process IDs, raw performance data, or temporary scripts.

Before publishing, scan the isolated staging tree:

```powershell
rg -n -i '(C:\\Users|D:\\AI|api[_-]?key|bearer|password|secret|private key|token)' .
```

This is a pattern scan, not a privacy audit. Review every match to distinguish third-party license examples and public identifiers from real user data. Also inspect `git status`, `git diff --cached --stat`, and the staged file list.
