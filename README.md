# llama.cpp (PrismML Extension for LM Studio)

> [!IMPORTANT]
> This repository provides **pre-compiled PrismML `llama.cpp` runtimes for LM Studio**, packaged as drop-in backend extensions for **Windows**. It allows you to **run PrismML Bonsai 1-bit / ternary GGUF models directly in LM Studio**, including models such as `*-PQ2_0.gguf` and `*-Q2_0_g64.gguf`.
>
> **Stock LM Studio `llama.cpp` runtimes do not include the custom PrismML kernels required by these ternary/Bonsai models.** If LM Studio cannot load a PrismML Bonsai model, use the corresponding PrismML runtime provided by this repository instead.
>
> **No compilation is required.** Download or copy the appropriate pre-built runtime, or run `setup-rocm-backend.ps1` to install the backend into `%USERPROFILE%\.lmstudio\extensions\backends\`.

<div align="center">

# llama.cpp (LM Studio Runtime - AMD & NVIDIA)

**Pre-built PrismML runtime packages for instant LM Studio integration**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows%20x64-lightgrey.svg)](../../releases)
[![Target](https://img.shields.io/badge/Target-LM%20Studio%20Extensions-purple.svg)](https://lmstudio.ai/)
[![Hardware](https://img.shields.io/badge/Hardware-AMD%20Radeon%20%2F%20NVIDIA%20RTX-red.svg)](../../releases)

[Releases](../../releases) &bull; [Request a Build](../../issues) &bull; [Upstream PrismML](https://github.com/PrismML-Eng/llama.cpp)

</div>

---

## Description

Standard LM Studio releases bundle upstream `llama.cpp` builds that do not include the custom low-bit quantization kernels required to execute PrismML's Bonsai ternary architectures. Attempting to load these models on stock runtimes causes load failures, NaN errors, or garbled output.

This branch introduces dedicated **AMD ROCm / HIP** acceleration for Windows, tuned for modern AMD Radeon graphics cards:
* **AMD Radeon RX 9000 Series (RDNA 4)**: Includes native support for **Radeon RX 9070 XT** and **RX 9070** (`gfx1201` / `gfx1200` targets).
* **AMD Radeon RX 7000 Series (RDNA 3)**: Supported via `gfx1100`, `gfx1101`, `gfx1102`, `gfx1150`, `gfx1151`.
* **Universal Vulkan Backend**: Zero-configuration fallback that works across any modern GPU vendor (AMD, Intel, NVIDIA).

It does not break, delete or overwrite existing LM Studio backends. It adds selectable runtimes in LM Studio settings.

---

## Supported Backends

| Backend | Platform | Target Devices / Architectures | Build / Tag | Status |
| :--- | :--- | :--- | :--- | :--- |
| **AMD ROCm / HIP** | Windows x64 | **AMD Radeon RX 9070 XT / 9000 (RDNA 4, gfx1201/gfx1200)**<br>AMD Radeon RX 7000 (RDNA 3, gfx1100-gfx1151)<br>AMD Radeon RX 6000 (RDNA 2, gfx1030) | `prism-b10809` | **Included on this branch** |
| **Vulkan (Universal)** | Windows x64 | AMD Radeon, Intel Arc, NVIDIA GeForce | `prism-b10809` | **Included on this branch** |
| **CUDA 13.3 (13.4)** | Windows x64 | NVIDIA RTX 30 / 40 / 50 Series | `prism-b10709` | Available in repository |
| **CPU / AVX2** | Windows x64 | Modern x86_64 CPUs | `prism-b10709` | Available in repository |

---

## Quick Start (No Git Clone Required!)

Your friend can install the entire backend **without installing Git or cloning this repository** simply by opening **PowerShell** and running this single command:

```powershell
irm https://raw.githubusercontent.com/zfzfg/llama.cpp-PrismML-Fork-LmStudio/feat/rocm-vulkan-rx9070xt/setup-rocm-backend.ps1 | iex
```

### Alternatively (If cloned locally):
Run the installer directly from this folder:
```powershell
.\setup-rocm-backend.ps1
```
*(To install only ROCm: `.\setup-rocm-backend.ps1 -Backend rocm` | To install only Vulkan: `.\setup-rocm-backend.ps1 -Backend vulkan`)*.


---

## Manual Installation

### 1. Copy to LM Studio Extensions
Copy the desired backend directory:
- `llama.cpp-prism-b10809-b3ebc47-bin-win-hip-radeon-x64-lm-studio` (ROCm / HIP)
- `llama.cpp-prism-b10809-b3ebc47-bin-win-vulkan-x64-lm-studio` (Vulkan)

Directly into LM Studio's backend extensions directory:
```text
C:\Users\<Username>\.lmstudio\extensions\backends\
```
> **Shortcut:** Press `Win + R`, paste `%USERPROFILE%\.lmstudio\extensions\backends`, and press Enter.

Your directory layout should look like this:
```text
C:\Users\<Username>\.lmstudio\extensions\backends\
├── llama.cpp-prism-b10809-b3ebc47-bin-win-hip-radeon-x64-lm-studio\
│   ├── backend-manifest.json
│   ├── display-data.json
│   ├── engine-protocol-server-artifacts.json
│   ├── llama-server.exe
│   ├── ggml-hip.dll
│   ├── rocblas.dll
│   ├── rocblas/
│   │   └── library/ (*_gfx1201.hsaco)
│   └── ...
└── llama.cpp-prism-b10809-b3ebc47-bin-win-vulkan-x64-lm-studio\
    └── ...
```

### 2. Activate in LM Studio
1. Start (or restart) **LM Studio**.
2. Open **Settings** (gear icon) and go to **Runtime**.
3. Under the **GGUF** section, select:
   ```text
   Prism ML AMD ROCm/HIP llama.cpp (Windows - RX 9070 XT / RDNA 4)
   ```
   *(Or select `Prism ML Vulkan llama.cpp (Windows - Universal / AMD Fallback)` if using Vulkan)*.
4. Load your PrismML Bonsai model (e.g. `Bonsai-8B-PQ2_0.gguf`) and set GPU offload to max!

---

## AMD Radeon RX 9070 XT Notes & Troubleshooting

### Target Architecture (`gfx1201`)
The Radeon RX 9070 XT is based on AMD's RDNA 4 (Navi 48) architecture, identified as `gfx1201` by LLVM and ROCm. The `backend-manifest.json` in this package includes `gfx1201` and `gfx1200` in `gpu.targets`, so LM Studio will accept the card.

### Driver Environment Variable Override
If LM Studio outputs `No supported ROCm GPUs found` on newer Windows Adrenalin driver versions:
1. Open Windows Start menu, type `Environment Variables`, and open **Edit the system environment variables**.
2. Under **User variables**, click **New**:
   - **Variable name**: `HSA_OVERRIDE_GFX_VERSION`
   - **Variable value**: `12.0.1`
3. Click OK and restart LM Studio.

### Vulkan Fallback
If your system encounters any ROCm driver conflicts on Windows, switch the Runtime in LM Studio to:
```text
Prism ML Vulkan llama.cpp (Windows - Universal / AMD Fallback)
```
Vulkan uses standard Windows graphics drivers without requiring the HIP/ROCm driver stack and fully supports PrismML ternary models.

---

## Credits

* PrismML fork and ternary kernels: [PrismML-Eng/llama.cpp](https://github.com/PrismML-Eng/llama.cpp)
* Base inference runtime: [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)
* Desktop environment: [LM Studio](https://lmstudio.ai/)
