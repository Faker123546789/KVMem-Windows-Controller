# Third-party notices

This repository's source files are an independent launcher and controller. They call the KVMem llama.cpp Windows runtime; they do not contain KVMem or llama.cpp implementation source.

The optional portable distribution contains the unmodified KVMem Windows x64 CUDA 13.2.86 runtime from [KVMem v0.16.0-rc3](https://github.com/kvmem/kvmem/releases/tag/v0.16.0-rc3). Its upstream package includes its own notices, source provenance, release notes, and SHA-256 manifest. Keep those files with the runtime. KVMem and llama.cpp components remain governed by the licenses in that package; the controller's MIT license does not relicense them.

The optional portable distribution also contains the unmodified PowerShell 7.6.7 for Windows x64 ZIP from Microsoft's [PowerShell release](https://github.com/PowerShell/PowerShell/releases/tag/v7.6.7). PowerShell is licensed separately under its upstream MIT license. The portable package retains PowerShell's license and notices alongside that runtime.

NVIDIA CUDA runtime components are distributed by the KVMem upstream package under NVIDIA's applicable redistribution terms and notices included by that package. This repository does not claim ownership of them.
