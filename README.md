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
为保证编译出的内核与系统驱动（vendor modules）完美兼容，需要以下工具支持（默认建议存放于 `~/android/tools`）：

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
mkdir -p ~/android/tools/toolchains/clang-r563880c
curl -L "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/tags/android-16.0.0_r4/clang-r563880c.tar.gz" | tar -xz -C ~/android/tools/toolchains/clang-r563880c
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
git clone --depth 1 -b lineage-22.1 https://github.com/LineageOS/android_system_tools_mkbootimg ~/android/tools/boot/mkbootimg

# 下载 avbtool (用于计算并追加 AVB Hash Footer)
git clone --depth 1 -b lineage-22.1 https://github.com/LineageOS/android_external_avb ~/android/tools/boot/avb
```

> **提示**：如果使用自带的 `./build_boot.sh` 脚本，工具缺失时脚本会自动从 AOSP（`android-16.0.0_r4`）下载这三样工具，无需手动逐个操作。

---

## 三、一键快速编译（推荐）

在其他机器上拉取本源码后，如果只想直接编译出一个无改动或已修改好的可开机 `boot.img`：

1. **准备官方参考镜像**：
   把与手机当前系统同一版本的 LineageOS 23.2 官方 `boot.img` 和 `vendor_boot.img` 放入源码上级目录的 `images` 文件夹中（即 `../images/`），或者通过环境变量指定：
   ```bash
   export IMAGES_DIR=/path/to/official/images
   ```
   `boot.img` 必需（提供内核配置、ramdisk 和引导签名元数据）；`vendor_boot.img` 可选，有它才能做模块 ABI 检查。

2. **执行一键构建脚本**：
   ```bash
   ./build_boot.sh
   ```

脚本执行流程：
- 校验主机环境；工具缺失时自动下载到 `~/android/tools`（可用 `TOOLS=` 指定）。
- 从官方 `boot.img` 读取内核配置（`CONFIG_IKCONFIG`）、ramdisk、OS 版本、补丁级别和 AVB 指纹，每次运行都重新读取。
- 以官方配置为基础，合并 `EXTRA_CONFIGS` 指定的配置片段，每次运行都重新生成 `.config`。
- 把版本后缀固定为官方内核的 `-g7ede20c8692e`（写入 `.scmversion`），编译 `Image`。
- 校验版本串与官方一致，并核对官方 `vendor_boot` 模块依赖的每个符号 CRC。任一不符即中止，不产出镜像。
- 用 `mkbootimg` 打包并用 `avbtool` 追加 AVB Hash Footer，输出 `out/boot.img`（大小等于官方 `boot.img`）。

`vendor_boot` 之外的模块（WiFi、相机等位于 vendor 分区）不在上述检查范围内。要覆盖它们，先用未改动的源码生成一份全量基线，之后每次编译都会与它比对：
```bash
EXTRA_CONFIGS= SAVE_ABI_BASELINE=1 ./build_boot.sh
```

---

## 四、手动分步编译与打包

如果你希望在 CI 环境构建，或者了解每一步细节：

### 1. 配置环境变量
```bash
export PATH=~/android/tools/toolchains/clang-r563880c/bin:$PATH
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
python3 ~/android/tools/boot/mkbootimg/unpack_bootimg.py \
    --boot_img /path/to/official/boot.img \
    --out out/official_boot_unpacked
```

### 5. 打包新 boot.img 并签署 AVB Footer
```bash
# 1. 打包 boot.img (Header Version 3)
python3 ~/android/tools/boot/mkbootimg/mkbootimg.py \
    --header_version 3 \
    --kernel out/kernel_obj/arch/arm64/boot/Image \
    --ramdisk out/official_boot_unpacked/ramdisk \
    --os_version 16.0.0 \
    --os_patch_level 2026-09 \
    --pagesize 4096 \
    -o out/boot.img

# 2. 追加 AVB Hash Footer (保证 Bootloader 校验通过)
python3 ~/android/tools/boot/avb/avbtool.py add_hash_footer \
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

### 1. 内核版本串必须与官方完全一致（否则卡开机、触屏或WiFi失效）
- **原因**：Linux 内核默认开启了 `CONFIG_LOCALVERSION_AUTO=y`，版本串末尾是当前 Git 提交号。官方内核是 `5.4.302-qgki-g7ede20c8692e`；本仓库的任何提交都不是 `7ede20c8692e`，有未提交改动时还会再多一个 `-dirty`。
- **后果**：小米 11 采用 Android 11+ GKI / QGKI 架构，触摸屏、DRM 显示、WiFi 等核心驱动以 `.ko` 模块形式存放在 `vendor_boot` 等分区。版本串不同，内核加载模块时检查 **vermagic** 会**拒绝加载驱动**，导致开机触屏失灵甚至卡米！
- **对策**：
  - 在源码根目录写入 `.scmversion`（已被 `.gitignore` 忽略），内核会直接采用它而不再读取 Git 状态。`build_boot.sh` 会自动写入：
    ```bash
    echo "-g7ede20c8692e" > .scmversion
    ```
  - 检查 `out/kernel_obj/include/config/kernel.release`，应当正好是 `5.4.302-qgki-g7ede20c8692e`。
  - 官方镜像换成基于其他内核提交的版本后，需要同步源码并改用新的后缀（`SCMVERSION=-g<新提交号>`）。

### 1.1 不能改变导出符号的 CRC
官方内核开启了 `CONFIG_MODVERSIONS`，模块加载时还会逐个核对所用内核符号的 CRC。改动 `task_struct` 等结构体布局、或开启会改变这些结构体的配置项，都会让预编译模块加载失败。`build_boot.sh` 编译后会自动检查。

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
   - 若要增加配置项，新建一个配置片段（如 `arch/arm64/configs/vendor/my.config`），用 `EXTRA_CONFIGS="my.config" ./build_boot.sh` 合入。脚本以官方 `boot.img` 内嵌的配置为基础，直接改 `venus_QGKI.config` 不会生效。
2. **编译流程**：
   - 修改代码 -> 运行 `./build_boot.sh` -> 刷入测试。是否已提交不影响版本串。

---

## 八、KernelSU-Next（分支 `lineage-23.2-ksu`）

本分支在 `lineage-23.2` 基础上内置了 [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next)（legacy 分支，手动挂钩模式）。

### 1. 获取源码
KernelSU-Next 以 submodule 形式放在 `KernelSU-Next/`，`drivers/kernelsu` 是指向它的软链接。它的版本号按自身仓库的提交数计算，**不能浅克隆**：
```bash
git clone -b lineage-23.2-ksu --recurse-submodules https://github.com/jocay/android_kernel_xiaomi_sm8350.git
# 已克隆的仓库：
git submodule update --init
```

### 2. 配置与编译
直接运行 `./build_boot.sh`。脚本会自动合入 `arch/arm64/configs/vendor/kernelsu_next.config`（`CONFIG_KSU=y`、`CONFIG_KSU_MANUAL_HOOK=y`）。要编译不带 KernelSU 的内核：
```bash
EXTRA_CONFIGS= ./build_boot.sh
```
手动编译时必须自己合入这个片段：`CONFIG_KSU` 默认开启，不指定 `CONFIG_KSU_MANUAL_HOOK=y` 会落到不适用于 5.4 的 kprobes 模式。

### 3. 不要给 `struct seccomp` 加字段
KernelSU 的 Kbuild 会在编译时向 `include/linux/seccomp.h` 的 `struct seccomp` 插入 `atomic_t filter_count;`，这会改变 `task_struct` 布局并破坏官方模块的 ABI。该文件中的注释用于阻止这一行为，请勿删除。

### 4. 使用
刷入 `boot.img` 后安装同版本的 KernelSU-Next 管理器。开机时连按三次音量下键进入安全模式（禁用所有模块）。

---

## 九、Droidspaces 容器支持

本分支同时开启了 [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) 所需的内核特性，按其文档中的 “GKI” 方案集成（本机是 5.4 + 预编译 vendor 模块，适用该方案而非 “non-GKI”）。

- **配置片段**：`arch/arm64/configs/vendor/droidspaces.config`，`build_boot.sh` 会自动合入。主要是 `SYSVIPC`、`POSIX_MQUEUE`、`IPC_NS`、`PID_NS`、`DEVTMPFS`，以及容器内 NAT / UFW / Fail2ban / NixOS 用到的 netfilter 与 tmpfs 选项。
- **kABI 处理**：`SYSVIPC` 和 `POSIX_MQUEUE` 会分别给 `task_struct`、`user_struct` 增加字段。`include/linux/sched.h` 与 `include/linux/sched/user.h` 把这些字段放进结构体末尾预留的 `ANDROID_KABI_RESERVE` 槽位，原有字段的偏移不变。
- **不要超出该片段的范围**：例如 `CGROUP_DEVICE`、`CGROUP_PIDS` 会改变 cgroup 相关结构体，破坏官方模块的 ABI。
- **`CONFIG_USER_NS` 默认未开启**：它能消除容器内 Docker 的 “unsafe procfs” 报错，但会允许所有普通应用创建用户命名空间，Android 内核出于安全考虑一直关闭它。已验证开启后 ABI 不变，需要时取消片段末尾那一行的注释即可。

刷入后安装 Droidspaces 应用并授予 root，在 **设置 -> Requirements -> Check Requirements** 中确认内核支持情况，或执行 `su -c droidspaces check`。
