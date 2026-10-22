# Configuration / 配置指南

[简体中文](#简体中文) | [English](#english)

## 简体中文

### 自定义后端参数

在面板中自行选择 `.ninfer` 模型、GPU 和端口，并根据显存与实际负载设置参数。配置由用户保存在本地，仓库不附带预设文件。

| 参数 | 用途 |
|---|---|
| `Context` | 最大上下文 token 数，包含输入与输出空间 |
| `Budget` / `Reserve` | GPU KV 工作集预算 / 生成预留 |
| `Prefill` / `MaxTokens` | 预填充块大小 / 默认单次回复 token 上限 |
| `HostMiB` | 受管 KV 的 RAM 预算，不是进程总内存上限 |
| `SinkTokens` / `RecentTokens` | 保留开头和最近上下文的窗口 |
| `KvType` | KV 数据类型；需符合后端能力 |
| `VisionResidency` / `VisionTokens` | 视觉权重所在设备 / 图片合并 token 上限 |
| `MtpDrafts` | MTP 草稿数量；未确认模型包含 MTP 权重时保持为 0 |

`Budget` 和 `Reserve` 必须按 64 对齐，`Prefill` 按 128 对齐，且 `Prefill <= Reserve`、`Budget + Reserve <= Context`。sink 和 recent 按页取整后的总量不得超过 `Budget`。启动前用 `-DryRun` 检查最终参数。

### 视觉设置

仅在模型已包含视觉权重时启用视觉。`cpu` 使用系统内存和 CPU 编码；`resident` 将视觉权重保留在 GPU，降低视觉编码延迟，同时增加显存占用。图片缓存命中是另一项后端机制，不能把 GPU 常驻等同于缓存命中。

保持相同图片和输出预算，分别记录冷请求与重复请求的首字时间、总耗时和显存峰值，再根据结果调整参数。降低图片 token 上限会改变输入细节，应由用户根据用途决定。

### 自定义客户端连接

在自己的 OpenAI 兼容客户端中创建连接，填写后端的实际地址与端口。默认地址为 `http://127.0.0.1:18210/v1`；通过 `/v1/models` 获取模型 ID。连接名称、认证、上下文提示、采样和回复上限由用户自行设置。

客户端提交的全部提示词与输出预留共同受 `Context` 限制。不要将上下文容量或 GPU KV 预算等同于完整无损记忆。

## English

### Configure the backend

Choose your `.ninfer` model, GPU, and port in the panel, then set parameters according to VRAM and workload. Users save settings locally; the repository includes no preset files.

| Parameter | Purpose |
|---|---|
| `Context` | Maximum context tokens, including room for input and output |
| `Budget` / `Reserve` | GPU KV working-set budget / generation reserve |
| `Prefill` / `MaxTokens` | Prefill chunk size / default reply token limit |
| `HostMiB` | Managed KV RAM budget, not a total process memory limit |
| `SinkTokens` / `RecentTokens` | Windows preserving opening and recent context |
| `KvType` | KV data type, subject to backend support |
| `VisionResidency` / `VisionTokens` | Vision weight residency / merged image-token limit |
| `MtpDrafts` | MTP draft count; keep at 0 until MTP weights are confirmed |

Align `Budget` and `Reserve` to 64, and `Prefill` to 128. Require `Prefill <= Reserve` and `Budget + Reserve <= Context`. Page-rounded sink and recent windows must fit within `Budget`. Inspect the final arguments with `-DryRun` before starting.

### Configure vision

Enable vision only when the artifact contains vision weights. `cpu` uses system memory and CPU encoding; `resident` keeps weights on the GPU to reduce encoding latency while consuming more VRAM. Image-cache hits are a separate backend mechanism; GPU residency does not imply a cache hit.

Keep the image and output budget fixed, then record cold and repeated requests, first-token time, total time, and VRAM peak before tuning. Lowering the image-token limit changes input detail and should be a deliberate user choice.

### Configure the client connection

Create a connection in your OpenAI-compatible client using the backend's actual address and port. The default is `http://127.0.0.1:18210/v1`; obtain the model ID from `/v1/models`. Users choose the connection name, authentication, context hint, sampling, and response limit.

All submitted prompts and the output allowance share the `Context` limit. Context capacity and GPU KV budget do not guarantee lossless recall.
