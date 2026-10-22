# Changes / 更新记录

2026-10-22 - Community Windows controller update / Windows 社区控制器更新

## 简体中文

这些修改属于 Windows 控制器，不代表上游推理引擎发布了新版本。

### 修复界面卡顿

- 将 `/v1/models` 探测移到 C# 后台 `Task`，HTTP 超时为 2 秒，避免在界面线程等待网络响应。
- 通过 100 毫秒 UI 定时器读取已完成结果；服务和转换任务状态每 2 秒刷新。
- 区分运行中、端口已监听但仍加载、已停止和状态未知，并在窗口关闭时释放探测客户端和定时器。
- 此修复针对服务探测阻塞；模型扫描、文件读取和转换仍需分别验收。

### 视觉与参数

- 将 `VisionResidency`、`VisionTokens` 从配置传递到启动器和后端，并在面板保存配置时保留。
- 支持 `resident` GPU 视觉常驻和图片 token 上限设置；模型必须包含视觉权重，常驻会增加显存占用。
- 控制器默认关闭 MTP 草稿；当 `MtpDrafts=0` 时，启动器同时关闭默认的自适应 MTP 和 n-gram 草稿，避免不兼容参数组合。
- 启动前校验模型扩展名、GPU 索引、预算对齐、`Prefill <= Reserve`、`Budget + Reserve <= Context` 和端口占用。

### 启停、接口与文档

- 新增 `v0.18/` 控制面板、启动/停止入口及 Windows 辅助脚本，保留既有根目录控制器。
- 默认仅监听 `127.0.0.1`，外层入口默认端口为 `18210`，可通过 `-Port` 自定义。
- 停止脚本按 worker 的完整路径和端口匹配进程，避免影响其他运行实例。
- OpenAI 兼容客户端的连接名称、地址、模型 ID、上下文和回复上限由用户自行配置。
- 修正文档中外层启动器的视觉参数用法：通过 `-VisionResidency` 选择设备，通过 `-NoVision` 禁用。
- 增加中英双语的 README、安装、参数、故障排查和第三方说明。

### 验证边界

本次发布检查 PowerShell 语法、JSON、参数约束、文档引用和文件清单。未在发布副本中重新完成 GPU 加载、视觉推理或长上下文实机验收；运行时、模型和转换器需另行准备。

## English

These changes concern the Windows controller, not a new upstream inference-engine release.

### Fix panel stalls

- Move `/v1/models` probes into a C# background `Task` with a two-second HTTP timeout, avoiding network waits on the UI thread.
- Consume completed results through a 100 ms UI timer; refresh service and conversion status every two seconds.
- Distinguish running, listening-but-loading, stopped, and unknown states; dispose the probe client and timer when the window closes.
- This addresses service-probe blocking; model scans, file reads, and conversions require separate acceptance checks.

### Vision and parameters

- Forward `VisionResidency` and `VisionTokens` from saved settings to the launcher and backend, and retain them when saving panel settings.
- Support GPU-resident vision and an image-token limit. Vision weights are required, and residency consumes additional VRAM.
- Disable MTP drafts by default in the controller. When `MtpDrafts=0`, the launcher also disables default adaptive MTP and n-gram drafts to avoid incompatible combinations.
- Check model extension, GPU index, budget alignment, `Prefill <= Reserve`, `Budget + Reserve <= Context`, and port availability before launch.

### Lifecycle, endpoint, and documentation

- Add the `v0.18/` panel, start/stop entry points, and Windows helpers while keeping the existing root controller.
- Bind to `127.0.0.1` by default; the outer launcher defaults to port `18210` and accepts a custom `-Port`.
- Match the worker's full executable path and port when stopping, avoiding interference with other instances.
- Let users choose their OpenAI-compatible client connection name, address, model ID, context, and response limit.
- Correct the outer launcher's documented vision options: choose residency with `-VisionResidency`, or disable vision with `-NoVision`.
- Add bilingual READMEs, installation, configuration, troubleshooting, and third-party notices.

### Validation boundary

Release checks cover PowerShell syntax, JSON, parameter constraints, documentation references, and the file list. GPU loading, vision inference, and long-context acceptance have not been repeated in this release copy; runtimes, models, and converters are supplied separately.
