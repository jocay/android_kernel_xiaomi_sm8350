# Xiaomi 11 (venus) LineageOS 23.2 内核源码与编译指南

本项目为 **小米 11（Xiaomi 11，设备代号：`venus`）** 的内核源码，适配 **LineageOS 23.2（基于 Android 16）**。

- **SoC 芯片平台**：Qualcomm Snapdragon 888 5G（SM8350 / Lahaina）
- **内核基准版本**：Linux 5.4.302-qgki (Android Common Kernel `android11-5.4`)
- **适用系统**：LineageOS 23.2 (Android 16.0.0) 官方及第三方构建

---

## 目录
- [一、准备工作与环境依赖](#一准备工作与环境依赖)
- [二、工具链准备](#二工具链准备)
- [三、一键快速编译（推荐）](#三一键快速编译推荐)
- [四、手动分步编译与打包](#四手动分步编译与打包)
- [五、刷机测试与回滚](#五刷机测试与回滚)
- [六、核心注意事项与避坑指南](#六核心注意事项与避坑指南重要)
- [七、内核定制与修改建议](#七内核定制与修改建议)

---

## 一、准备工作与环境依赖

推荐在 **Ubuntu 22.04 / 24.04 LTS**、**Debian 12** 或 **WSL2** 环境下进行编译。

在克隆本仓库的设备上，首先安装 Linux 内核构建所需的基础软件包与交叉编译工具：

```bash
sudo apt update
sudo apt install -y \
    build-essential \
    bc \
    bison \
    flex \
    libssl-dev \
    python3 \
    libelf-dev \
    gcc-aarch64-linux-gnu \
    gcc-arm-linux-gnueabi \
    git \
    curl \
    tar \
    cpio
```

---

## 二、工具链准备

Android 16 (LineageOS 23.2) 的内核构建采用了高版本的 Clang 以及 Android Boot Header v3 引导结构。
为保证编译出的内核与系统驱动（vendor modules）完美兼容，需要以下工具支持（默认建议存放于 `~/android/buildtools`）：

### 1. 编译器版本详细信息与下载链接

本项目实测并对齐的编译器为 **Google AOSP 官方预编译 Clang 21 (`clang-r563880c`)**：

| 参数项 | 详细信息 |
|---|---|
| **编译器版本字符串** | `Android (14054515, +pgo, +bolt, +lto, +mlgo, based on r563880c) clang version 21.0.0` |
| **LLVM Project 对应 Commit** | `5e96669f06077099aa41290cdb4c5e6fa0f59349` |
| **Android 构建编号 (Build ID)** | `14054515` (对应 LineageOS 23.2 / Android 16 平台工具链) |
| **官方 Git 仓库地址** | [platform/prebuilts/clang/host/linux-x86 (Google AOSP)](https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86) |
| **AOSP 官方预编译包直链 (tar.gz)** | `https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/tags/android-16.0.0_r4/clang-r563880c.tar.gz` |

#### 下载并解压命令：
```bash
mkdir -p ~/android/buildtools/clang-r563880c
curl -L "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/tags/android-16.0.0_r4/clang-r563880c.tar.gz" | tar -xz -C ~/android/buildtools/clang-r563880c
```

> **补充说明（备用工具链）**：  
> Android Common Kernel (ACK 5.4) 原生配置文件中指定的旧版工具链为 `clang-r416183b`（基于 LLVM 12.0.5 / Build 7284624）。  
> 仓库地址：[LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b (branch: lineage-20.0)](https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b)  
> 但在 LineageOS 23.2（Android 16）整机环境下，官方内核实际使用的是上述最新的 **`clang-r563880c`** 进行编译。为保证内核 banner、优化选项与符号表与官方系统 100% 对齐，**务必优先使用 `clang-r563880c`**。

### 2. Android 镜像打包与 AVB 签名工具
- **`mkbootimg` 源码库**：[LineageOS/android_system_tools_mkbootimg](https://github.com/LineageOS/android_system_tools_mkbootimg) (分支 `lineage-22.1` 或 `lineage-23.2`)
- **`avbtool` 源码库**：[LineageOS/android_external_avb](https://github.com/LineageOS/android_external_avb) (分支 `lineage-22.1` 或 `lineage-23.2`)

```bash
# 下载 mkbootimg (用于打包 Android boot 镜像)
git clone --depth 1 -b lineage-22.1 https://github.com/LineageOS/android_system_tools_mkbootimg ~/android/buildtools/mkbootimg

# 下载 avbtool (用于计算并追加 AVB Hash Footer)
git clone --depth 1 -b lineage-22.1 https://github.com/LineageOS/android_external_avb ~/android/buildtools/avb
```

> **提示**：如果使用自带的 `./build_boot.sh` 脚本，若检测到工具链目录不存在，脚本会自动下载配置，无需手动逐个操作。

---

## 三、一键快速编译（推荐）

在其他机器上拉取本源码后，如果只想直接编译出一个无改动或已修改好的可开机 `boot.img`：

1. **准备官方参考镜像**：
   下载最新的 LineageOS 23.2 官方 `boot.img`（用于提取官方 ramdisk 和引导签名元数据），放入源码上级目录的 `images` 文件夹中（即 `../images/boot.img`），或者通过环境变量指定：
   ```bash
   export IMAGES_DIR=/path/to/official/images
   ```

2. **执行一键构建脚本**：
   ```bash
   chmod +x build_boot.sh
   ./build_boot.sh
   ```

脚本执行流程：
- 自动校验主机环境与工具链（缺失则自动下载）。
- 合并小米 11 Venus 专属的 defconfig。
- 使用 Clang 并行编译内核目标 `Image`。
- 自动提取官方 ramdisk，使用 `mkbootimg` 进行打包。
- 使用 `avbtool` 注入 AVB Hash Footer 签名。
- 产物输出至：`out/boot.img`（大小严格对齐 192MB / 201,326,592 字节）。

---

## 四、手动分步编译与打包

如果你希望在 CI 环境构建，或者了解每一步细节：

### 1. 配置环境变量
```bash
export PATH=~/android/buildtools/clang-r563880c/bin:$PATH
export ARCH=arm64
export SUBARCH=arm64
export CC=clang
export LLVM=1
export LLVM_IAS=1
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
export TARGET_PRODUCT=venus
```

### 2. 合并并生成内核配置 (.config)
小米 11 在 LineageOS 上的完整 defconfig 由四个片段合并而成：
```bash
mkdir -p out/kernel_obj

# 合并 defconfig 片段
ARCH=arm64 ./scripts/kconfig/merge_config.sh -m -O out/kernel_obj \
    arch/arm64/configs/vendor/lahaina-qgki_defconfig \
    arch/arm64/configs/vendor/debugfs.config \
    arch/arm64/configs/vendor/xiaomi_QGKI.config \
    arch/arm64/configs/vendor/venus_QGKI.config

# 校验并补齐旧配置项
make O=out/kernel_obj olddefconfig
```

### 3. 编译内核二进制 (Image)
```bash
make -j$(nproc) O=out/kernel_obj Image
```
编译产物位于：`out/kernel_obj/arch/arm64/boot/Image`。

### 4. 解包官方 boot.img 提取 Ramdisk
```bash
mkdir -p out/official_boot_unpacked
python3 ~/android/buildtools/mkbootimg/unpack_bootimg.py \
    --boot_img /path/to/official/boot.img \
    --out out/official_boot_unpacked
```

### 5. 打包新 boot.img 并签署 AVB Footer
```bash
# 1. 打包 boot.img (Header Version 3)
python3 ~/android/buildtools/mkbootimg/mkbootimg.py \
    --header_version 3 \
    --kernel out/kernel_obj/arch/arm64/boot/Image \
    --ramdisk out/official_boot_unpacked/ramdisk \
    --os_version 16.0.0 \
    --os_patch_level 2026-09 \
    --pagesize 4096 \
    -o out/boot.img

# 2. 追加 AVB Hash Footer (保证 Bootloader 校验通过)
python3 ~/android/buildtools/avb/avbtool.py add_hash_footer \
    --image out/boot.img \
    --partition_size 201326592 \
    --partition_name boot \
    --algorithm NONE \
    --salt cb93777825c2a5eee97b68ae1c26213c92aa8f8138d549db04d1bebc9f2040c1 \
    --prop com.android.build.boot.os_version:16 \
    --prop com.android.build.boot.fingerprint:Xiaomi/lineage_venus/venus:16/BP4A.251205.006/1b809f17b8:userdebug/release-keys
```

---

## 五、刷机测试与回滚

### 1. 刷入新内核镜像
将小米 11 重启至 Fastboot 模式（关机状态下长按 `音量减 + 电源键`）：
```bash
fastboot flash boot out/boot.img
fastboot reboot
```

### 2. 官方原版回滚（遇异常时应急）
如果设备无法进入系统，重新进入 Fastboot 刷回官方镜像即可恢复：
```bash
fastboot flash boot /path/to/official/boot.img
fastboot reboot
```

---

## 六、核心注意事项与避坑指南（重要！）

### 1. 严防内核版本出现 `-dirty` 后缀（导致卡开机、触屏或WiFi失效）
- **原因**：Linux 内核默认开启了 `CONFIG_LOCALVERSION_AUTO=y`。编译时脚本会检查当前 Git 仓库。若存在未提交的修改或未追踪的新增文件，内核版本会自动由 `5.4.302-qgki-g7ede20c8692e` 变为 `5.4.302-qgki-g7ede20c8692e-dirty`。
- **后果**：小米 11 采用 Android 11+ GKI / QGKI 架构，触摸屏、DRM 显示、WiFi 等核心驱动以 `.ko` 模块形式存放在 `vendor_boot` 分区。一旦主内核版本带上 `-dirty`，内核加载模块时检查 **vermagic** 会判断版本不匹配而**拒绝加载驱动**，导致开机触屏失灵甚至卡米！
- **对策**：
  - 编译前务必确保 `git status` 是干净的（或在 commit 之后再编译）。
  - 可以检查编译输出的 `out/kernel_obj/include/config/kernel.release`，确保里面**没有** `-dirty` 后缀。

### 2. 必须使用同款 `clang-r563880c` 编译器
LineageOS 23.2（Android 16）官方整机构建使用的平台编译器是 `clang-r563880c`（LLVM 21.0.0）。切勿使用过旧的 Clang 12 或系统自带 GCC 编译，否则可能会遇到编译报错、内联汇编语法差异，或符号表与预编译驱动模块不兼容的问题。

### 3. 理解 Android Boot Header v3 结构
- 在高通骁龙 888 设备上：
  - `boot.img`：只包含未压缩内核 `Image` 和通用的 boot/recovery `ramdisk`。
  - `vendor_boot.img`：包含设备专有的 `dtb`（设备树二进制）、cmdline 启动参数以及 `vendor_ramdisk`（包含开机加载的 `.ko` 驱动）。
- 因此，对于常规的内核功能调整（如支持特定特性、调频调压、内建功能等），**只需要刷入重新打包的 `boot.img` 即可**。

### 4. 必须签署 AVB Hash Footer
直接使用 `mkbootimg` 生成的镜像只有 ~40MB，而分区的标准大小是 192MB（`201326592` 字节）。必须使用 `avbtool` 追加 `add_hash_footer`，将镜像填补至完整分区尺寸并注入 AVB 签名描述符，否则部分 Bootloader 会判定镜像损坏直接进入 Fastboot 救砖模式。

---

## 七、内核定制与修改建议

1. **添加驱动或修改配置**：
   - 可以在源码中直接修改代码。
   - 若要增加模块或配置项，可在 `arch/arm64/configs/vendor/venus_QGKI.config` 中追加 `CONFIG_XXXX=y` 或 `=m`。
2. **提交与编译流程**：
   - 修改代码 -> `git add . && git commit -m "feat: your change"` -> 运行 `./build_boot.sh` -> 刷入测试。
   - 始终保持 Commit 状态进行构建，确保 vermagic 版本号稳定。

---

## 八、KernelSU-Next（本分支 `lineage-23.2-ksu`）

本分支在 `lineage-23.2` 基础上内置了 [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next)（legacy 分支，手动挂钩模式）。

### 1. 获取源码
KernelSU-Next 以 submodule 形式放在 `KernelSU-Next/`，`drivers/kernelsu` 是指向它的软链接。它的版本号按自身仓库的提交数计算，**不能浅克隆**：
```bash
git clone -b lineage-23.2-ksu --recurse-submodules https://github.com/jocay/android_kernel_xiaomi_sm8350.git
# 已克隆的仓库：
git submodule update --init
```

### 2. 配置与编译
在第四节的四个 defconfig 片段之后追加 `arch/arm64/configs/vendor/kernelsu_next.config`（`CONFIG_KSU=y`、`CONFIG_KSU_MANUAL_HOOK=y`）。不追加的话 `CONFIG_KSU` 仍默认开启，但会落到不适用于 5.4 的 kprobes 模式。

本分支的 HEAD 不是官方提交，编译前需固定版本后缀，否则 vermagic 与 `vendor_boot` 中的官方模块不匹配（`build_boot.sh` 目前不会做这两步）：
```bash
echo "-g7ede20c8692e" > .scmversion
```

### 3. 不要给 `struct seccomp` 加字段
KernelSU 的 Kbuild 会在编译时向 `include/linux/seccomp.h` 的 `struct seccomp` 插入 `atomic_t filter_count;`，这会改变 `task_struct` 布局并破坏官方模块的 ABI。该文件中的注释用于阻止这一行为，请勿删除。

### 4. 使用
刷入 `boot.img` 后安装同版本的 KernelSU-Next 管理器。开机时连按三次音量下键进入安全模式（禁用所有模块）。
