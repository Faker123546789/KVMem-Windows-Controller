# Active KV RAM/SSD Tiering / 活跃 KV 的 RAM/SSD 分层

[中文](#中文) | [English](#english)

## 中文

两个后端共用 `kvmem/` 中的原生字节存储、配额、文件 I/O 和任务队列。
推理、GPU 页池、逻辑 token 位置、mean-K 检索和状态 checkpoint 仍由后端负责。
完整 K/V（包括量化 scale 和 MTP KV）都可以离开 RAM；活跃 mean-K 留在 RAM。
本次实测范围与性能未验收项见 [验收记录](https://github.com/kvmem/kvmem-llama.cpp/blob/938c2f1968b0283e7d7dd143918a9f3ff866dd4d/docs/active-kv-tiering-validation-20261010.md)；
分阶段历史见 [实现计划](https://github.com/kvmem/kvmem-llama.cpp/blob/938c2f1968b0283e7d7dd143918a9f3ff866dd4d/docs/active-kv-tiering-plan.md)。

## 使用与预算

两种 worker 使用相同的三个参数：

```text
--kvmem-host-mib H --kvmem-disk-path PATH --kvmem-disk-mib D
```

统一 Windows 启动器对应 `-HostMiB H -DiskPath PATH -DiskMiB D`。
不配置磁盘时使用公共 RAM 存储。目录和正数磁盘预算必须同时存在；启动器只指定
DiskPath 时采用其默认 D。llama 的旧在线 NVMe/旧会话磁盘参数与公共 SSD 不能混用。

H 限制本 worker 所有活跃和非活跃历史的原生 KV 驻留字节及预留。
D 限制仍被持有的文件区间，包括原生 KV、闲置状态附件和未发布写入目的。
H/D 都不是进程 RSS 限制：mean-K、状态、传输暂存、元数据和操作系统文件缓存另计。
启动多个 worker 时，各进程有自己的账户和文件。

H 至少要容纳并发原生工作集及必要的换页空间。增加 D 不能补偿不足的活动窗口。
适配器还会保留交换余量；历史不能占满全部 H+D 后再借用不计费的缓冲区。
目录中的文件只在当前进程内有效，最后一个所有者释放后删除，不提供重启恢复。

## 活动历史与非活动历史

同一份原生 KV 只有一套记录所有权。历史从活动变为闲置时移动所有权，保留既有的
RAM/SSD 位置；恢复时只读取实际选中的内容，不再生成一份全量 KV 冷快照。
闲置 GDN、统计等附件可另外写入同一 D，恢复仍遵循本后端的精确前缀和状态规则。
历史目录决定淘汰谁，公共存储决定哪些不可变字节从 H 下沉到 D。

写入先取得目的配额，完成后才发布新副本、释放旧副本。读租约会保留内容及其配额，
即使原会话已删除。磁盘满、读取失败或取消都不能提前丢弃唯一有效副本。
碎片化可能使一个连续记录无法分配，即使剩余总字节足够；此时明确拒绝，不超配。

SSD 区间保留按地址排列的目录，并用独立的 `(大小, 地址)` 空闲索引选择最小可用块，
不逐条扫描已占用历史。释放时合并相邻空闲区间；每个占用区间保留一个可复用的
索引节点，保证释放不申请内存。拆分所需节点申请失败会回滚，不改变原区间或配额。

小记录换出按最多 256 KiB、64 条记录打包，相邻文件区间合并写入，遇到间隔则拆开。
每条记录仍独立持有和释放磁盘区间。H 至少为 512 KiB 时优先留出 256 KiB 打包余量；
实际打包缓冲与原 RAM 副本同时计入 H。余量不足或记录较大时使用单条写入，完整 H
仍可用于必要的工作集。整批写入成功后才发布，失败保留全部原 RAM 副本；不等待凑批。

## 并发接入

ninfer 的单引擎调度线程提交有界 CPU I/O 任务，等待中的 lane 让出计算机会；
完成后由引擎检查会话版本并执行 GPU 搬运和发布。llama 独立 lane 可以等待文件 I/O，
但等待期间不能持有共享 GPU 锁或会话目录锁。两者使用相同的存储所有权和失败规则。
公共文件读写不持有全局存储策略锁，同一记录由自己的锁保护。

排队取消可撤销，已开始的 I/O 必须排空；在此之前保留源、目的和暂存额度。
存储 worker 不执行 GPU API，不拥有需要 CUDA 析构的对象，也不发布会话状态。
单请求 I/O 失败在安全边界结束该请求，不能清空其他 lane 的资源。

## 新推理后端的最小适配步骤

1. 描述原生 K/V 的层、页、plane、stride 和有效 token；把量化附属数据一起计入记录。
   公共层保存不透明字节，不重新量化，也不改变原始位置。
2. 每个 worker 建立一个 `HostKvStorage`，RAM 和 SSD 两种配置用同一条所有权路径。
   捕获尚未完成的记录保持可写，GPU 完成之后再 `seal()`。
3. 同步读取使用 `HostKvLease`；排队任务先持有 `HostKvSource`，复制时再取得短租约。
   修改有读者的内容时使用新记录，避免破坏已排队任务看到的版本。
4. 在既有引擎安全边界接入 prepare / wait / publish。绑定会话 generation 和内容版本，
   只有目的完整有效时才能更新 GPU 视图。纯 RAM 快路不需要新增文件任务。
5. 非活动历史移动同一批记录；仅把引擎状态附件交给共享 `SpillFile`。
   将 `BudgetExceeded` 与 `TransferFailed` 映射到本后端的请求失败处理。
6. 先通过 RAM 原生字节/输出及性能对照，再测试强制 SSD、闲置恢复、取消、满盘与
   热冷并发。保留原引擎二进制，分别记录 RAM 回归和真实 SSD 成本。

接口见 [公共内存契约](https://github.com/kvmem/kvmem-llama.cpp/blob/938c2f1968b0283e7d7dd143918a9f3ff866dd4d/docs/memory-backend-contract.md)；适配参考
[llama adapter](https://github.com/kvmem/kvmem-llama.cpp/blob/938c2f1968b0283e7d7dd143918a9f3ff866dd4d/src/adapter/llama-memory-kvmem.cpp) 和
[ninfer 窗口/历史存储](https://github.com/kvmem/kvmem-llama.cpp/blob/938c2f1968b0283e7d7dd143918a9f3ff866dd4d/backends/patches/ninfer-kvmem.patch)。
公共层测试不依赖 GPU；Windows 和 Linux 使用同一契约及不同的偏移文件 I/O 实现。
具体平台是否完成原生 GPU 验收，应以验收记录为准。

## English

Both backends share the native byte store, quotas, file I/O, and task queue in
`kvmem/`. Inference, GPU page pools, logical token positions, mean-K retrieval, and
state checkpoints remain backend responsibilities. Complete K/V records, including
quantization scales and MTP KV, can leave RAM; active mean-K remains in RAM.
See the [validation record](https://github.com/kvmem/kvmem-llama.cpp/blob/938c2f1968b0283e7d7dd143918a9f3ff866dd4d/docs/active-kv-tiering-validation-20261010.md)
for tested scope and outstanding performance work, and the
[implementation plan](https://github.com/kvmem/kvmem-llama.cpp/blob/938c2f1968b0283e7d7dd143918a9f3ff866dd4d/docs/active-kv-tiering-plan.md)
for staged history.

### Usage and budgets

Both workers accept the same three options:

```text
--kvmem-host-mib H --kvmem-disk-path PATH --kvmem-disk-mib D
```

The unified Windows launcher exposes `-HostMiB H -DiskPath PATH -DiskMiB D`.
Without disk configuration, storage uses shared RAM. A disk directory and a
positive disk budget must both be present; specifying only `DiskPath` in the
launcher uses its default D. Legacy llama online-NVMe/session-disk options cannot
be mixed with this shared SSD store.

H limits resident native KV bytes and reservations across active and inactive
history for this worker. D limits retained file extents, including native KV,
inactive state attachments, and unpublished write destinations. Neither H nor D
limits process RSS: mean-K, state, transfer staging, metadata, and OS file caches
consume additional memory. Each worker process has separate accounts and files.

H must fit the concurrent native working set and required paging headroom.
Increasing D cannot compensate for an undersized active window. Adapters reserve
swap headroom; history cannot fill H+D and then borrow unaccounted buffers.
Files are valid only within the current process and are deleted when their last
owner releases them; this is not restart recovery.

### Active and inactive history

Each native KV record has one ownership chain. Moving history to idle transfers
ownership while preserving RAM/SSD placement. Restoration reads only selected
content rather than creating another complete cold KV snapshot. Idle GDN and
statistics attachments may also use D; restoring them still follows the backend's
exact-prefix and state rules. The history directory chooses what to evict, while
shared storage chooses which immutable bytes move from H to D.

A write first acquires destination quota, then publishes the completed copy and
releases the old one. Read leases retain content and quota even after the original
session is deleted. Disk-full, read-failure, and cancellation paths must preserve
the sole valid copy. Fragmentation may reject a contiguous record despite enough
total free bytes; the store reports failure instead of exceeding quota.

SSD storage keeps an address-ordered extent directory plus a separate
`(size, address)` free index for best-fit selection. Freeing coalesces adjacent
extents. Each occupied extent retains a reusable index node so release does not
allocate memory. If allocation for a split fails, the operation rolls back without
changing extents or quota.

Small-record eviction packs up to 256 KiB or 64 records, merging adjacent file
writes and splitting at gaps. Each record still independently owns and releases
its extent. When H is at least 512 KiB, storage prefers 256 KiB of packing headroom;
both the packing buffer and original RAM copy count against H. Insufficient
headroom or large records use individual writes, leaving H available for essential
working data. A batch publishes only after every write succeeds; failure preserves
all original RAM copies. The system does not wait to fill a batch.

### Concurrent integration

The NInfer single-engine scheduler submits bounded CPU I/O tasks; waiting lanes
yield compute opportunities. The engine checks session versions before GPU
transfer and publication. Independent llama lanes may wait for file I/O without
holding shared GPU or session-directory locks. Both use identical ownership and
failure rules. Shared file operations do not hold a global storage-policy lock;
each record has its own lock.

Queued work may be cancelled; started I/O must drain while retaining source,
destination, and staging quota. Storage workers do not call GPU APIs, own objects
requiring CUDA destruction, or publish session state. A request-level I/O failure
ends that request at a safe boundary without clearing other lanes' resources.

### Minimum adapter steps for a new inference backend

1. Describe native K/V layers, pages, planes, strides, and valid tokens. Include
   quantization metadata in each record. Shared storage keeps opaque bytes without
   requantizing or changing original positions.
2. Create one `HostKvStorage` per worker. RAM and SSD use the same ownership path.
   Incomplete captured records remain writable; call `seal()` after GPU completion.
3. Use `HostKvLease` for synchronous reads. Queued tasks retain `HostKvSource`
   first and acquire short leases when copying. Create a new record when changing
   data that already has readers, preserving queued readers' versions.
4. Integrate prepare/wait/publish at existing engine-safe boundaries. Bind session
   generation and content version; update GPU views only after the destination is
   complete. The RAM-only fast path needs no additional file tasks.
5. Move the same records for inactive history; put only engine-state attachments
   in shared `SpillFile`. Map `BudgetExceeded` and `TransferFailed` to backend
   request-failure handling.
6. First validate RAM native bytes, output, and performance; then test forced SSD,
   idle restore, cancellation, disk-full, and mixed hot/cold concurrency. Retain
   the original engine binary and record RAM regressions separately from real SSD
   costs.

See the [shared memory contract](https://github.com/kvmem/kvmem-llama.cpp/blob/938c2f1968b0283e7d7dd143918a9f3ff866dd4d/docs/memory-backend-contract.md),
[llama adapter](https://github.com/kvmem/kvmem-llama.cpp/blob/938c2f1968b0283e7d7dd143918a9f3ff866dd4d/src/adapter/llama-memory-kvmem.cpp),
and [NInfer window/history patch](https://github.com/kvmem/kvmem-llama.cpp/blob/938c2f1968b0283e7d7dd143918a9f3ff866dd4d/backends/patches/ninfer-kvmem.patch).
Shared-store tests do not need a GPU. Windows and Linux use the same contract with
different positional file-I/O implementations. Consult the validation record for
each platform's actual native-GPU acceptance status.
