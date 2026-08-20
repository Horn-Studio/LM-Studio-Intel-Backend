# LM-Studio-Intel-Backend

为 LM Studio Windows提供两个自定义 llama.cpp 后端，目标硬件：**Intel Arc A770**。

| 后端 | 引擎名 | 说明 |
|---|---|---|
| SYCL | `llama.cpp-win-x86_64-sycl-avx2@2.29.1` | Intel oneAPI SYCL / Level Zero。提示处理 ~215 tok/s，生成 ~44 tok/s，加载 ~4s |
| OpenVINO | `llama.cpp-win-x86_64-openvino-avx2@2.29.1` | OpenVINO 2026.3 GPU 插件。提示处理 ~660 tok/s，生成 ~10 tok/s，加载 ~28s（图编译） |

两者都是 llama.cpp 官方 b10516 预编译二进制（GitHub Releases），运行时完全自包含（SYCL 包带 oneAPI 运行时，OpenVINO 包带完整 OpenVINO 2026.3 运行时）——**运行不需要安装任何额外组件**。

## 目录结构

```
LM-Studio-Patch/
├── install.ps1                      # 一键安装脚本
├── backends/
│   ├── llama.cpp-win-x86_64-sycl-avx2-2.29.1/       # SYCL 后端（完整）
│   └── llama.cpp-win-x86_64-openvino-avx2-2.29.1/   # OpenVINO 后端（完整）
└── build/
    ├── shim/                        # 启动器工程（C/C++ 源码 + 编译脚本 + 产物）
    │   ├── shim.c / shim.cpp        # 源码（两版等价，/TP 编译）
    │   ├── build-shim.bat / build-shim-cpp.bat
    │   ├── llama-server-shim.exe    # C 编译产物
    │   └── llama-server-shim-cpp.exe# C++ 编译产物（OpenVINO 后端当前使用）
    ├── python/llama_server_shim.py  # Python 版 shim（参考实现，已弃用：进程清理不可靠）
    └── release/                     # 官方预编译压缩包（升级时重新解压替换）
        ├── llama-b10516-bin-win-sycl-x64.zip
        └── llama-b10516-bin-win-openvino-2026.3-x64.zip
```

## 安装

```powershell
cd D:\LM-Studio-Patch
.\install.ps1 -Force                 # 一键安装 + 默认选中 OpenVINO 引擎
.\install.ps1 -SelectEngine sycl     # 安装后选中 SYCL
.\install.ps1 -SelectEngine none     # 只安装，不改引擎选择
```

脚本会自动：停掉正在运行的 llama-server（避免文件锁）→ 复制两个后端 → 校验文件完整 → 通过 lms CLI 列出/选中引擎。
LM Studio 运行中也能装（它会实时监视 backends 文件夹），装完即可在lms无头模式或打开了开发者选项的设置中发现

## 为什么 OpenVINO 后端需要一个 shim？

OpenVINO 2026 的 `ov::Core::get_available_devices()` 返回的设备名带索引（`GPU.0`、`GPU.1`），
而 llama.cpp 的 ggml-openvino 后端用精确字符串 `"GPU"` 匹配 → 永远不命中 → 静默回退 CPU。
（诊断依据：官方 pip openvino 包枚举出 `['CPU','GPU.0','GPU.1']`，其中 GPU.0 = Arc A770，GPU.1 = NVIDIA CMP 40HX（？为什么这里会出现n卡））

shim 设置 `GGML_OPENVINO_DEVICE=GPU.0` 环境变量 → 启动真正的 `llama-server-real.exe`（参数/stdio 原样透传，退出码透传）。
Job Object（KILL_ON_JOB_CLOSE）保证 LM Studio 结束 shim 时子进程一起退出。

**OpenVINO后端目前极其不稳定，我只有第一次加载成功后就再也没能够成功卸载到GPU，这不是我的问题（应该？），这个Windows后端本来就很烂**

## 关于 LM Studio 显示 "Vulkan"

LM Studio 检测库闭源，无可得知，通过查看 GPU 框架枚举只有 `Unknown/Shell/ROCm/CUDA/OpenCl/Metal/Vulkan`，没有 SYCL/OpenVINO。
所以清单里 `gpu.framework` 写 `Vulkan`（否则引擎根本不会被识别），实际计算路径是 SYCL/Level Zero 或 OpenVINO。
硬件页里 A770 显示 "(Vulkan)" 是 LM Studio 的能力检测标签，不影响实际后端。

## 从源码重建（可选）

1. **shim**（需要 VS2022 Build Tools + MSVC）：
   ```
   cd build\shim
   build-shim-cpp.bat    # 产出 llama-server-shim-cpp.exe，改名 llama-server.exe 放进后端目录
   ```
2. **llama.cpp 本体**（升级后端时）：
   - 下载新版官方预编译包（GitHub Releases 里找 `*-bin-win-sycl-x64.zip` / `*-bin-win-openvino-2026.3-x64.zip`），解压替换后端目录中的同名文件
   - 如需 OpenVINO 从源码编译：`pip install openvino`（`install.ps1 -InstallOvtk`）提供开发头文件/CMake 配置，然后
     `cmake -B build -DGGML_OPENVINO=ON -DOpenVINO_DIR=<pip 包 cmake 目录>`
   - 版本号必须是 semver（如 2.29.1），且要同步改 `backend-manifest.json` 里的 version 并重命名文件夹

- OpenVINO 后端每次加载模型都要重新编译图（~28s），b10516 的编译缓存对拆分图至少在我的环境上不生效（且会浪费 173MB/次，已禁用）
