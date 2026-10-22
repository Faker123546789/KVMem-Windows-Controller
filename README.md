# KVMem Windows Controller / KVMem Windows 控制器

[简体中文](#简体中文) | [English](#english)

## 简体中文

这是一个面向 [KVMem](https://github.com/kvmem/kvmem) 本地推理后端的 Windows 控制器仓库。仓库保留现有的可视化控制器，并在此基础上提供 **KVMem v0.18 NInfer 控制器源码和参数说明**。

> 本项目是独立的第三方社区前端，不是 KVMem 官方仓库，也不代表 KVMem 上游作者。推理引擎、模型格式和上游许可证归各自作者所有。

### v0.18 包含什么

- WinForms 控制器：扫描 `.ninfer` 模型、配置 KV 预算、视觉、MTP 和采样参数。
- PowerShell 启动与停止入口，默认仅监听 `127.0.0.1`。
- 可自定义上下文、显存预算和视觉设置。
- 中英双语的安装、配置、隐私和故障排查说明。

### 不包含什么

本仓库**不包含模型权重、NInfer/llama.cpp 运行时、转换器二进制、Python 环境、日志、聊天记录、世界书、API 密钥或用户配置**。请从上游发布页获取与显卡架构匹配的 v0.18 运行包，并将 `.ninfer` 模型放在纯英文路径。模型和运行时体积大、许可独立，因此没有放进 Git 历史。

### 快速开始

1. 安装 PowerShell 7 和兼容 CUDA 13.2 的 NVIDIA 驱动。
2. 准备与 GPU 架构匹配的 `workers/ninfer/ninfer-kvmem-server.exe` 及 `.ninfer` 模型。
3. 在面板中选择自己的模型并设置显存预算，或通过命令行传入参数。
4. 检查参数，不启动服务：

```powershell
pwsh -NoProfile -File .\v0.18\Start-KVMem-v018.ps1 -Model 'D:\models\model.ninfer' -Port 18210 -VisionResidency resident -DryRun
```

5. 启动面板：

```powershell
pwsh -NoProfile -STA -File .\v0.18\KVMem-v018-ControlPanel.ps1
```

面板和 API 默认使用 `http://127.0.0.1:18210/v1`。具体安装步骤见 [Windows 安装说明](v0.18/docs/installation.md)，长篇角色扮演参数见 [配置指南](v0.18/docs/configuration.md)。

### OpenAI 兼容客户端

后端提供 OpenAI 兼容接口。用户可在自己的客户端中新建连接，并自行填写端口、模型 ID、上下文提示和回复上限；默认使用 `18210` 端口，实际模型 ID 以 `/v1/models` 返回值为准。仓库不附带第三方客户端配置、聊天、世界书或记忆数据。

### 视觉与性能

视觉默认可以使用 CPU；当转换产物包含视觉权重时，可切换为 GPU 常驻：

```powershell
pwsh -NoProfile -File .\v0.18\Start-KVMem-v018.ps1 -Model 'D:\models\model.ninfer' -Port 18210 -VisionResidency resident
```

`resident` 会把视觉权重保留在 GPU 上，降低重复图片首次处理延迟，但会增加显存占用。先确认模型确实包含视觉权重；缺少权重时使用 `-NoVision`，不要只修改 residency。

### 文档

- [安装与运行 / Installation](v0.18/docs/installation.md)
- [参数与长篇角色扮演配置 / Configuration](v0.18/docs/configuration.md)
- [RAM/SSD 分层 / Active KV tiering](v0.18/docs/active-kv-tiering.md)
- [故障排查 / Troubleshooting](v0.18/docs/troubleshooting.md)
- [隐私与发布边界 / Privacy and release scope](v0.18/docs/privacy.md)
- [本次变更 / Changes](v0.18/CHANGELOG.md)
- [v0.18 来源记录 / Provenance](v0.18/provenance/)

### 验证边界

PowerShell 语法检查、JSON 解析和仓库扫描只能证明发布内容可解析、未发现已知隐私模式，不能代替真实 GPU 加载、视觉推理、长上下文压力测试或客户端实机对话。发布前请在自己的模型和驱动环境完成一次启动、`/v1/models`、流式对话和停止服务验收。

### 许可证与致谢

控制器和本仓库新增脚本使用 [MIT License](LICENSE)。KVMem、NInfer、CUDA 组件和其他第三方组件按各自许可证使用，相关文本保留在 [`v0.18/licenses/`](v0.18/licenses/)；详细来源和构建信息见 [`v0.18/BUILD-INFO.json`](v0.18/BUILD-INFO.json)。感谢 KVMem、NInfer 及其社区分支的维护者和贡献者。

## English

This repository provides a Windows controller for the [KVMem](https://github.com/kvmem/kvmem) local inference backend. It keeps the existing visual controller and adds **KVMem v0.18 NInfer controller source and parameter documentation**.

> This is an independent community frontend, not an official KVMem repository. The inference engine, model format, and upstream licenses belong to their respective authors.

### What v0.18 adds

- A WinForms controller for `.ninfer` model discovery, KV budgets, vision, MTP, and sampling settings.
- PowerShell start/stop entry points that bind to `127.0.0.1` by default.
- Customizable context length, memory budgets, and vision settings.
- Bilingual installation, configuration, privacy, and troubleshooting documentation.

### What is not included

This repository **does not include model weights, NInfer/llama.cpp runtime binaries, converter binaries, Python environments, logs, chats, lorebooks, API keys, or user configuration**. Download the v0.18 runtime matching your GPU architecture from the upstream release and place the `.ninfer` model in an English-only path. Models and runtimes are large and separately licensed, so they are not stored in Git history.

### Quick start

1. Install PowerShell 7 and a CUDA 13.2-compatible NVIDIA driver.
2. Prepare `workers/ninfer/ninfer-kvmem-server.exe` for your GPU and a compatible `.ninfer` model.
3. Choose your model and memory budgets in the panel, or pass them on the command line.
4. Validate the launch arguments without starting the server:

```powershell
pwsh -NoProfile -File .\v0.18\Start-KVMem-v018.ps1 -Model 'D:\models\model.ninfer' -Port 18210 -VisionResidency resident -DryRun
```

5. Open the panel:

```powershell
pwsh -NoProfile -STA -File .\v0.18\KVMem-v018-ControlPanel.ps1
```

The panel and API use `http://127.0.0.1:18210/v1` by default. See [Installation](v0.18/docs/installation.md) and [Configuration](v0.18/docs/configuration.md) for details.

### OpenAI-compatible clients

The backend exposes an OpenAI-compatible endpoint. Users can create their own client connection and choose the port, model ID, context hint, and response limit; the default port is `18210`, and the actual model ID comes from `/v1/models`. The repository does not ship third-party client settings, chats, lorebooks, or memory data.

### Vision and performance

Vision can run on CPU by default. If the converted artifact contains vision weights, GPU residency is available:

```powershell
pwsh -NoProfile -File .\v0.18\Start-KVMem-v018.ps1 -Model 'D:\models\model.ninfer' -Port 18210 -VisionResidency resident
```

`resident` keeps vision weights on the GPU, reducing repeated image latency at the cost of VRAM. Confirm the artifact contains vision weights; use `-NoVision` when they are absent rather than changing only the residency flag.

### Documentation

- [Installation](v0.18/docs/installation.md)
- [Configuration](v0.18/docs/configuration.md)
- [Active KV tiering](v0.18/docs/active-kv-tiering.md)
- [Troubleshooting](v0.18/docs/troubleshooting.md)
- [Privacy and release scope](v0.18/docs/privacy.md)
- [Changes in this release](v0.18/CHANGELOG.md)
- [Provenance](v0.18/provenance/)

### Validation boundary

Parser checks, JSON parsing, and repository scans can show that the release is syntactically valid and that known privacy patterns are absent. They do **not** replace a real GPU load, vision request, long-context stress test, or client conversation. Before relying on this package, verify startup, `/v1/models`, streaming chat, and shutdown with your own model and driver.

### License and acknowledgments

The controller and new repository scripts are provided under the [MIT License](LICENSE). KVMem, NInfer, CUDA components, and other third-party components remain under their respective licenses; see [`v0.18/licenses/`](v0.18/licenses/) and [`v0.18/BUILD-INFO.json`](v0.18/BUILD-INFO.json). Thanks to the KVMem, NInfer, and community-branch maintainers and contributors.
