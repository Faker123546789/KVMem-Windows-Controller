# KVMem Windows Controller

A small Windows desktop controller for starting, stopping, and switching local GGUF models with the **KVMem llama.cpp** server. It provides a model picker, GGUF layer detection, context and KV cache controls, sampling defaults, an optional `mmproj` picker, and a built-in log viewer. Its OpenAI-compatible endpoint is intended for local clients such as SillyTavern.

This is an independent community launcher. It does not modify LM Studio or replace the upstream KVMem project.

## Quick start

For the portable, ready-to-run package, download the Windows x64 ZIP from the repository's **Releases** page, extract it, and double-click `Open-KVMem-Controller.bat`. The first launch verifies and unpacks its bundled KVMem runtime and portable PowerShell into the extracted folder. No administrator access is required. Keep the extracted folder together after setup.

Place GGUF files in the `models` folder to have them discovered automatically, or use **Browse GGUF** to select a model elsewhere. Model weights are intentionally not included in this repository or the portable package. Use only English characters in the path to the extracted package and any model you select.

## Requirements

- Windows 11 x64
- An NVIDIA driver compatible with the selected CUDA runtime
- Microsoft Visual C++ x64 runtime
- An NVIDIA GPU whose architecture is included in the runtime build
- A GGUF model stored locally

The portable package includes a private-to-this-folder PowerShell 7 runtime so the controller does not need a system-wide PowerShell installation. KVMem itself is kept in a separate `runtime` subfolder.

## SillyTavern / OpenAI-compatible clients

After the model status shows **Running**, use:

| Setting | Value |
|---|---|
| API type | OpenAI-compatible Chat Completions |
| Base URL | `http://127.0.0.1:18200/v1` |
| Model ID | `kvmem-current` |
| API key | Leave empty |

The server binds to the loopback interface. This address is a generic local-only default; it is not a public or LAN endpoint. Do not change the bind address to `0.0.0.0` unless you deliberately intend to expose the service to your network.

## Controls

- Scans a chosen model directory for GGUF files and filters the results by name.
- Reads the selected GGUF's architecture and maximum layer count for automatic GPU offload. Manual GPU layer selection is available.
- Provides adjustable context, KV precision, KVMem budgets, CPU and batch settings, Flash Attention, load mode, output length, temperature, Top-P, Top-K, Min-P, penalties, seed, and thinking mode.
- Supports a separately selected `mmproj` GGUF for compatible vision models.
- Reports start and stop failures in the window and opens recent runtime logs in a built-in viewer.
- Uses no model-specific default and does not copy or upload model files.

## Runtime and backend compatibility

This controller requires the **llama.cpp/GGUF** backend. Its portable package uses the upstream Windows x64 CUDA 13.2.86 runtime from [KVMem v0.16.0-rc3](https://github.com/kvmem/kvmem/releases/tag/v0.16.0-rc3), which includes the RTX 40 series `sm_89` target. The archive SHA-256 is `76e450bd9f84a43f61a2c2a1c742dc8b98a43f39b12f7e79cfa2043e5e456bec`.

Do not substitute the Windows v0.18 NInfer package: it is a different backend and does not provide this llama.cpp server. Check the [upstream release page](https://github.com/kvmem/kvm/releases) for current backend and package notes. The upstream project supplies and licenses its runtime separately; third-party notices are in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## Run from source

1. Install PowerShell 7 and download the upstream KVMem v0.16.0-rc3 Windows x64 CUDA runtime.
2. Extract the runtime so this folder contains `runtime/bin/llama-kvmem-server.exe` and `runtime/share/kvmem/ui`.
3. Put one or more models in `models`, or select any local `.gguf` in the controller.
4. Run `Open-KVMem-Controller.bat`.

You can also call `Start-KVMem.ps1` directly with a model path. See `Start-KVMem.ps1 -?` for supported arguments. The controller binds only to `127.0.0.1` and uses port `18200` by default.

## Privacy and safety

The repository contains only the controller and launcher source. It excludes the machine's runtime logs, backups, process files, model files, and local configuration. The portable ZIP bundles the upstream runtime but no model weights or machine-generated logs. `.gitignore` blocks common model, log, and secret files.

The launcher uses paths relative to its own folder. Its default model directory is `models`; it contains no account name, home directory, machine name, LAN address, SillyTavern URL, or model path. Local run logs stay under `codex/logs`.

## License

The controller and launcher source in this repository are offered under the MIT License. The separately identified KVMem runtime, PowerShell runtime, CUDA components, and other upstream materials remain under their respective licenses; see `THIRD-PARTY-NOTICES.md` and the bundled notices.
