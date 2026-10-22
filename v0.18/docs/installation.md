# Installation / 安装说明

[简体中文](#简体中文) | [English](#english)

## 简体中文

### 1. 前置条件

- Windows 10/11 x64。
- PowerShell 7，而不是仅依赖 Windows PowerShell 5.1。
- NVIDIA 驱动支持 CUDA 13.2；使用与显卡架构匹配的 RTX 30/40/50 v0.18 运行包。
- 模型必须是 NInfer v3 `.ninfer`，并且包含文本推理所需权重。
- 运行包、模型和输出路径尽量只使用英文、数字、短横线和下划线。

### 2. 恢复运行目录

Git 仓库只保存控制器和说明。将上游 v0.18 运行包解压到本目录，或者在独立目录中准备以下结构，将本目录的控制器脚本放在该目录中：

```text
v0.18/
├─ workers/
│  └─ ninfer/
│     └─ ninfer-kvmem-server.exe
├─ model.ninfer
├─ Start-KVMem-v018.ps1
├─ Stop-KVMem-v018.ps1
└─ KVMem-v018-ControlPanel.ps1
```

`models/`、`workers/`、`converter/` 已被 `.gitignore` 排除。不要把模型或运行时提交到仓库。

### 3. 先做 DryRun

以下命令只解析参数，不启动进程，也不会写入模型文件：

```powershell
pwsh -NoProfile -File .\Start-KVMem-v018.ps1 -Model 'D:\models\model.ninfer' -Port 18210 -VisionResidency resident -DryRun
```

如果报错，优先检查模型扩展名、GPU 编号、预算对齐、端口占用和视觉权重。`Budget + Reserve` 必须不超过 `Context`。

### 4. 启动和验证

```powershell
pwsh -NoProfile -File .\Start-KVMem-v018.ps1 -Model 'D:\models\model.ninfer' -Port 18210 -VisionResidency resident
```

另开一个 PowerShell 检查服务：

```powershell
Invoke-RestMethod 'http://127.0.0.1:18210/v1/models' | ConvertTo-Json -Depth 6
```

确认模型 ID 后，再做一次流式对话和一次带图片的请求。最后在运行启动器的终端按 `Ctrl+C`，或执行：

```powershell
pwsh -NoProfile -File .\Stop-KVMem-v018.ps1
```

并确认端口已释放：

```powershell
Get-NetTCPConnection -LocalPort 18210 -State Listen -ErrorAction SilentlyContinue
```

### 5. 双击入口

`Open-KVMem-v018-Panel.vbs` 使用 `%ProgramFiles%\PowerShell\7\pwsh.exe`。如果 PowerShell 7 安装在非标准位置，直接使用 `pwsh` 命令行启动，或先修正 VBS 路径。请在面板中自行选择模型并保存本地参数。

## English

### 1. Prerequisites

- Windows 10/11 x64.
- PowerShell 7, not Windows PowerShell 5.1 alone.
- A CUDA 13.2-compatible NVIDIA driver and the RTX 30/40/50 v0.18 runtime matching your GPU.
- A NInfer v3 `.ninfer` artifact containing the required text weights.
- English-only paths for the runtime, model, and output whenever possible.

### 2. Restore the runtime

Git contains only the controller and documentation. Extract the upstream v0.18 runtime here, or prepare this layout in a separate directory and point the launcher at it:

```text
v0.18/
├─ workers/
│  └─ ninfer/
│     └─ ninfer-kvmem-server.exe
├─ model.ninfer
├─ Start-KVMem-v018.ps1
├─ Stop-KVMem-v018.ps1
└─ KVMem-v018-ControlPanel.ps1
```

`models/`, `workers/`, and `converter/` are ignored by Git. Do not commit weights or runtime binaries.

### 3. Start with a dry run

This validates arguments without launching a process or writing to the model:

```powershell
pwsh -NoProfile -File .\Start-KVMem-v018.ps1 -Model 'D:\models\model.ninfer' -Port 18210 -VisionResidency resident -DryRun
```

If it fails, check the model extension, GPU index, budget alignment, port ownership, and vision weights. `Budget + Reserve` must not exceed `Context`.

### 4. Launch and verify

```powershell
pwsh -NoProfile -File .\Start-KVMem-v018.ps1 -Model 'D:\models\model.ninfer' -Port 18210 -VisionResidency resident
```

In another PowerShell window:

```powershell
Invoke-RestMethod 'http://127.0.0.1:18210/v1/models' | ConvertTo-Json -Depth 6
```

After confirming the model ID, send one streaming chat request and one image request. Stop with `Ctrl+C` in the launcher terminal or with:

```powershell
pwsh -NoProfile -File .\Stop-KVMem-v018.ps1
```

Then verify that the port is released:

```powershell
Get-NetTCPConnection -LocalPort 18210 -State Listen -ErrorAction SilentlyContinue
```

### 5. Double-click entry points

`Open-KVMem-v018-Panel.vbs` expects `%ProgramFiles%\PowerShell\7\pwsh.exe`. If PowerShell 7 is elsewhere, launch through `pwsh` or correct the VBS path. Choose your model and save your settings locally in the panel.
