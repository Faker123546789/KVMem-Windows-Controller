# Troubleshooting / 故障排查

[简体中文](#简体中文) | [English](#english)

## 简体中文

### 面板打开后卡死

1. 用 PowerShell 7 直接运行 `pwsh -STA -File .\KVMem-v018-ControlPanel.ps1`，查看是否有未处理异常。
2. 确认模型目录存在，且扫描目录中没有正在写入的超大文件。
3. 先关闭面板，再检查有无残留 `ninfer-kvmem-server.exe`；不要按进程名误杀用户自己启动的服务。
4. 用 `scripts\windows\start-ninfer.ps1 -DryRun` 单独验证参数，并指定模型路径与端口，区分界面问题和后端问题。

### 端口被占用

```powershell
Get-NetTCPConnection -LocalPort 18210 -State Listen |
  Select-Object LocalAddress,LocalPort,OwningProcess
```

确认进程属于本版本后再停止；`Stop-KVMem-v018.ps1` 只匹配本目录 worker 路径和端口，不应被当作通用的强制杀进程工具。

### 启动失败或立即退出

检查模型是否为 `.ninfer`、GPU 编号是否存在、驱动是否支持运行包、`Budget/Reserve/Prefill` 是否对齐，以及视觉和 MTP 权重是否真的存在。缺少视觉权重时追加 `-NoVision`；缺少 MTP 权重时使用 `-MtpDrafts 0`。

### API 能访问但没有回复

先用 `/v1/models` 确认模型 ID，再做最小的流式 Chat Completions。若短请求正常、长篇请求失败，记录实际 prompt token、`Context`、`Budget`、`Reserve` 和系统 RAM/VRAM 余量，不要仅凭报错猜测是模型记忆问题。

### 视觉首字很慢

确认请求确实包含图片、模型确实带视觉权重，并比较 CPU 与 `resident`。如果 `resident` 导致 OOM，就恢复 CPU 或降低 `VisionTokens`。视觉请求的输出 token 预算和文本请求共享服务端资源，不能用一次冷请求的耗时代表稳定性能。

## English

### Panel appears frozen

1. Run `pwsh -STA -File .\KVMem-v018-ControlPanel.ps1` directly and inspect unhandled exceptions.
2. Confirm the model directory exists and is not being written by a large copy.
3. Close the panel and check for a leftover `ninfer-kvmem-server.exe`; do not kill unrelated services by process name.
4. Validate arguments separately with `scripts\windows\start-ninfer.ps1 -DryRun`, including an explicit model path and port, to distinguish UI from backend failures.

### Port already in use

```powershell
Get-NetTCPConnection -LocalPort 18210 -State Listen |
  Select-Object LocalAddress,LocalPort,OwningProcess
```

Confirm ownership before stopping it. `Stop-KVMem-v018.ps1` matches this directory's worker path and port; do not treat it as a generic process killer.

### Server fails or exits immediately

Check the `.ninfer` extension, GPU index, driver/runtime compatibility, `Budget/Reserve/Prefill` alignment, and whether vision/MTP weights exist. Add `-NoVision` when vision weights are absent and use `-MtpDrafts 0` when MTP weights are absent.

### API responds but chat does not

Confirm the model ID through `/v1/models`, then send a minimal streaming Chat Completions request. If short requests work and long requests fail, record the actual prompt tokens, `Context`, `Budget`, `Reserve`, system RAM, and VRAM headroom. Do not infer “bad memory” from the error alone.

### Vision first token is slow

Confirm the request contains an image and the artifact contains vision weights, then compare CPU and `resident`. If `resident` causes OOM, return to CPU or lower `VisionTokens`. Vision and text requests share server resources; one cold request is not a stable performance measurement.
