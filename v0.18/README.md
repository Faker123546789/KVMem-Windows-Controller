# KVMem v0.18 NInfer for Windows / Windows 版 KVMem v0.18 NInfer

[简体中文](#简体中文) | [English](#english)

## 简体中文

这里是 KVMem v0.18 的控制器与配置源码目录。它面向 NInfer v3 `.ninfer` 模型，支持 Windows 10/11 x64、PowerShell 7、NVIDIA RTX 30/40/50。运行包、模型和转换器不属于本目录。

### 目录说明

| 路径 | 用途 |
|---|---|
| `Start-KVMem-v018.ps1` | 命令行启动入口 |
| `Stop-KVMem-v018.ps1` | 只停止由本入口匹配到的 NInfer 进程 |
| `KVMem-v018-ControlPanel.ps1` | WinForms 控制面板 |
| `Open-KVMem-v018-*.vbs/.bat` | 双击入口 |
| `scripts/windows/` | 参数校验、进程启动和兼容性辅助脚本 |
| OpenAI 兼容接口 | 用户在自己的客户端中自行配置连接 |
| `provenance/` | 不含本机路径的构建和兼容性证据 |

### 启动与配置

控制面板可扫描 `.ninfer` 模型、选择视觉常驻模式，并保存长篇参数。请在面板中自行选择模型、填写参数并保存本地配置。

```powershell
pwsh -NoProfile -STA -File .\KVMem-v018-ControlPanel.ps1
```

命令行也可以使用相同参数。上下文和 KV 预算应根据模型、显存与实际测试自行设置：

```powershell
# 1. 确认 GPU
nvidia-smi -L

# 2. 仅检查启动参数，不启动服务
pwsh -NoProfile -File .\Start-KVMem-v018.ps1 -Model 'D:\models\model.ninfer' -Port 18210 -VisionResidency resident -DryRun
```

就绪后检查 `http://127.0.0.1:18210/v1/models`。外层 `Start-KVMem-v018.ps1` 的默认端口为 18210，可通过 `-Port` 自定义。详细的安装、参数、视觉与停止步骤见 [安装说明](docs/installation.md) 和 [配置指南](docs/configuration.md)。

### 已知边界

- `.ninfer` 是必需格式；普通 GGUF 需要先转换。
- 中文路径在历史上存在兼容问题，发布包和模型应使用纯英文路径。
- 视觉 `resident` 需要模型带视觉权重，并会增加显存占用。
- 本目录没有 `workers/`、`models/` 或 `converter/`，它们需要从上游或你自己的构建获取。
- 静态检查不是 GPU 推理验收，长上下文和视觉仍需实机测试。
- 本仓库不附带第三方客户端配置；聊天、世界书、角色卡和记忆数据均由用户自行管理。

## English

This directory contains the KVMem v0.18 controller and configuration source. It targets NInfer v3 `.ninfer` models on Windows 10/11 x64, PowerShell 7, and NVIDIA RTX 30/40/50 GPUs. Runtime binaries, models, and converter assets are not part of this directory.

### Layout

| Path | Purpose |
|---|---|
| `Start-KVMem-v018.ps1` | Command-line launcher |
| `Stop-KVMem-v018.ps1` | Stops only the matching NInfer process |
| `KVMem-v018-ControlPanel.ps1` | WinForms control panel |
| `Open-KVMem-v018-*.vbs/.bat` | Double-click entry points |
| `scripts/windows/` | Argument validation, process launch, and compatibility helpers |
| OpenAI-compatible endpoint | Configure a client connection in your own application |
| `provenance/` | Build and compatibility evidence without machine-local paths |

### Launch and configuration

The panel can scan `.ninfer` models, select vision residency, and save long-roleplay settings. Choose your model, adjust parameters, and save settings locally in the panel.

```powershell
pwsh -NoProfile -STA -File .\KVMem-v018-ControlPanel.ps1
```

The command line accepts the same parameters. Choose the context and KV budgets according to your model, VRAM, and runtime checks:

```powershell
# 1. Inspect the GPU
nvidia-smi -L

# 2. Validate arguments without launching
pwsh -NoProfile -File .\Start-KVMem-v018.ps1 -Model 'D:\models\model.ninfer' -Port 18210 -VisionResidency resident -DryRun
```

After startup, check `http://127.0.0.1:18210/v1/models`. The outer `Start-KVMem-v018.ps1` defaults to port 18210; pass `-Port` to customize it. See [Installation](docs/installation.md) and [Configuration](docs/configuration.md) for the full process.

### Known boundaries

- `.ninfer` is required; ordinary GGUF files must be converted first.
- English-only paths remain the safe choice for the runtime and model.
- Vision `resident` requires vision weights in the artifact and consumes additional VRAM.
- `workers/`, `models/`, and `converter/` are intentionally absent and must come from upstream or your own build.
- Static checks are not GPU inference validation; long-context and vision behavior still require a real test.
- This repository ships no third-party client settings; users manage their own chats, lorebooks, character cards, and memory data.
