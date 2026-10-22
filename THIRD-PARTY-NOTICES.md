# Third-party notices / 第三方声明

## 中文

本仓库的控制器和启动脚本是独立的社区前端。根目录旧版调用 KVMem llama.cpp 后端；新增 `v0.18/` 目录调用 NInfer 后端。仓库不包含这些推理引擎的实现代码、模型或二进制运行包。

旧版可选便携包使用 KVMem v0.16.0-rc3 的 Windows x64 CUDA 13.2.86 运行时，以及微软 PowerShell 7.6.7 x64 ZIP。它们按各自上游许可证使用；运行时自带的声明、来源、更新说明和校验清单应随包保留。控制器的 MIT 许可证不重新授权这些第三方组件。

v0.18 目录保留上游 KVMem、NInfer、CUDA 及其依赖的许可证和历史来源文本，见 [`v0.18/licenses/`](v0.18/licenses/) 和 [`v0.18/BUILD-INFO.json`](v0.18/BUILD-INFO.json)。这些上游原文为法律和来源记录，不作为本仓库当前功能说明，不改写为翻译后的许可证。

NVIDIA CUDA 组件应遵守其适用的再分发条款。本仓库不宣称拥有第三方组件的版权，也不代表上游作者。

## English

This repository's source files are an independent launcher and controller. They call the KVMem llama.cpp Windows runtime; they do not contain KVMem or llama.cpp implementation source.

The optional portable distribution contains the unmodified KVMem Windows x64 CUDA 13.2.86 runtime from [KVMem v0.16.0-rc3](https://github.com/kvmem/kvmem/releases/tag/v0.16.0-rc3). Its upstream package includes its own notices, source provenance, release notes, and SHA-256 manifest. Keep those files with the runtime. KVMem and llama.cpp components remain governed by the licenses in that package; the controller's MIT license does not relicense them.

The optional portable distribution also contains the unmodified PowerShell 7.6.7 for Windows x64 ZIP from Microsoft's [PowerShell release](https://github.com/PowerShell/PowerShell/releases/tag/v7.6.7). PowerShell is licensed separately under its upstream MIT license. The portable package retains PowerShell's license and notices alongside that runtime.

NVIDIA CUDA runtime components are distributed by the KVMem upstream package under NVIDIA's applicable redistribution terms and notices included by that package. This repository does not claim ownership of them.

The added `v0.18/` directory targets the NInfer backend. It retains upstream license
and historical provenance text in [`v0.18/licenses/`](v0.18/licenses/) and
[`v0.18/BUILD-INFO.json`](v0.18/BUILD-INFO.json), without bundling engine binaries or
models. These upstream originals are legal and historical records, not current
feature documentation; their license wording is preserved rather than replaced
with translations. The root legacy controller continues to target llama.cpp.
