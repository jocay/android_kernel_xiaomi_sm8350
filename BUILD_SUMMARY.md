# 小米 11（venus）内核编译总结

日期：2026-10-01
对应官方系统：`lineage-23.2-20260930-nightly-venus`（内核 `5.4.302-qgki-g7ede20c8692e`，补丁级别 2026-09）

本次在官方 LineageOS 23.2 内核源码上编出了可开机的内核，并集成了 KernelSU-Next 和 Droidspaces 容器支持。只替换 `boot.img`，`vendor_boot` 及 vendor 分区里的官方驱动模块保持不动。

---

## 一、结果

| 镜像（`out/` 下，未入库） | 内容 | 真机状态 |
|---|---|---|
| `boot-stock-rebuild.img` | 官方源码原样重编 | 已验证：正常开机 |
| `boot-ksu-next.img` | + KernelSU-Next | 已刷入使用，反馈正常 |
| `boot-ksu-droidspaces.img` | + Droidspaces（不含 `USER_NS`） | 已验证：正常开机；Droidspaces 检测仅 User namespaces 一项为黄色 |
| `boot-ksu-droidspaces-userns.img` | + `CONFIG_USER_NS` | 已验证：正常开机；Droidspaces 检测全部通过 |

四个镜像的内核版本串都是 `5.4.302-qgki-g7ede20c8692e`，与官方一致。

SHA-256：
```
a460971bae8f13b1228228ae57b9cde969df18bcb94c47dc0a9087609d76a171  boot-stock-rebuild.img
2a047069ab16f85efb47b1a7e5fa7a568d71dd7740e300d00d2cbffd0800637d  boot-ksu-next.img
225d4070a3d902a4c91b891825f530def462f769c4f833cc7440acf1f6cbcfb9  boot-ksu-droidspaces.img
9a510a158a45de5944a7a7a89b5886d7af49129ab203631bc25a94b9194fab0e  boot-ksu-droidspaces-userns.img
a15d4138df0cea05774b4d53592121327d536c08707fe1fde374e377af2baf46  boot.img（官方，回滚用）
```

---

## 二、编译环境

| 项目 | 值 |
|---|---|
| 主机 | WSL2，Ubuntu 26.04，24 线程 / 15 GB 内存 |
| 编译器 | AOSP `clang-r563880c`（Clang 21.0.0，build 14054515），与官方内核 banner 相同 |
| 打包工具 | AOSP `android-16.0.0_r4` 的 `mkbootimg`、`avbtool` 1.3.0 |
| 工具目录 | `~/android/tools`（`toolchains/`、`boot/`、`downloads/`） |
| 内核配置 | 官方 `boot.img` 内嵌配置（`CONFIG_IKCONFIG`）+ 配置片段 |
| 构建选项 | `LLVM=1 LLVM_IAS=1`，ThinLTO + CFI（沿用官方配置） |

增量之外的一次完整编译约 3–4 分钟。

---

## 三、分支与提交

| 分支 | 用途 |
|---|---|
| `lineage-23.2` | 官方源码 + 构建脚本与文档，编出来是无 root 的原版内核 |
| `lineage-23.2-ksu` | 在上面基础上加 KernelSU-Next 和 Droidspaces |

```
40d6e9a44 venus: droidspaces: enable user namespaces
670c3dd24 venus: enable Droidspaces container support
e808d6c6f Merge branch 'lineage-23.2' into lineage-23.2-ksu
811c50ebb build_boot.sh: pin the official release string and check module ABI   (lineage-23.2)
84b641213 venus: integrate KernelSU-Next (legacy, manual hooks)
937cbac33 docs: add build guide and one-click build script for Xiaomi 11 (venus)
```

---

## 四、做了哪些改动

### 1. 构建脚本 `build_boot.sh`
原脚本编出的内核无法加载官方驱动：`CONFIG_LOCALVERSION_AUTO` 会把本仓库的提交号写进版本串，而官方模块的 vermagic 要求 `-g7ede20c8692e`。重写后：

- 通过 `.scmversion` 固定版本后缀，编译后核对版本串，不一致就中止。
- 编译后核对官方 `vendor_boot` 模块依赖的每个符号 CRC；有本地基线（`out/baseline_crcs.txt`）时再比对全部导出符号。
- 内核配置、ramdisk、OS 版本、补丁级别、AVB 指纹都从官方 `boot.img` 实时读取，不再写死。
- 每次运行都重新生成 `.config`，用 `EXTRA_CONFIGS` 合入配置片段。
- 工具下载改为完成后再就位，中断不会留下半成品。

### 2. KernelSU-Next
- 以 submodule 引入，固定在 legacy 分支提交 `7eac8a17`（`v3.4.0-legacy` 之后 9 个提交），内核报告版本 33303。没有用 `v3.4.0-legacy` 标签，是因为标签之后才修掉管理器首次安装拿不到 root 的问题。
- 手动挂钩模式（`CONFIG_KSU_MANUAL_HOOK=y`）。挂钩点在 `fs/exec.c`、`fs/open.c`、`fs/stat.c`、`fs/read_write.c`、`kernel/reboot.c`、`drivers/input/input.c`。
- `fs/namespace.c` 补了 `path_umount()`。
- `include/linux/seccomp.h` 里加了一段注释，用来阻止 KernelSU 的 Kbuild 在编译时往 `struct seccomp` 插字段（那会改变 `task_struct` 布局）。

### 3. Droidspaces
- 配置片段 `arch/arm64/configs/vendor/droidspaces.config`：`SYSVIPC`、`POSIX_MQUEUE`、`IPC_NS`、`PID_NS`、`USER_NS`、`DEVTMPFS`，以及 NAT / UFW / Fail2ban / NixOS 用到的 netfilter 与 tmpfs 选项。
- `SYSVIPC`、`POSIX_MQUEUE` 新增的字段放进了 `task_struct`、`user_struct` 末尾的 `ANDROID_KABI_RESERVE` 槽位（`include/linux/sched.h`、`include/linux/sched/user.h`），原有字段偏移不变。

相对官方配置，最终 `.config` 共多出 26 项：24 项来自上面两个片段及其依赖，2 项是主机探测项 `CC_CAN_LINK*`；没有任何官方选项被关闭或改值。除文档外，源码改动为 19 个文件、+437 / −99 行，其中 `build_boot.sh` 占大部分。

---

## 五、校验

每个镜像出包前都通过了以下检查：

| 检查 | 结果 |
|---|---|
| 内核版本串 | `5.4.302-qgki-g7ede20c8692e`，与官方相同 |
| 官方 `vendor_boot` 模块（11 个）依赖的内核符号 CRC | 1058 个全部匹配 |
| 全部导出符号 CRC 对比原样重编的基线 | 13435 个全部不变 |
| `boot.img` 头部 | header v3、OS 16.0.0、补丁级别 2026-09，与官方相同 |
| AVB | `avbtool verify_image` 通过，指纹取自官方镜像 |
| ramdisk | 与官方逐字节相同 |
| 编译 | 0 错误；警告均来自原有代码（`binder.c`、`thermal_core.c`） |

KernelSU 的挂钩点另外通过反汇编确认：各系统调用入口确实调用到了对应的处理函数。

这些都是静态检查，只能说明模块能加载、镜像格式正确；功能是否正常以真机为准。

---

## 六、如何复现

```bash
git clone -b lineage-23.2-ksu --recurse-submodules https://github.com/jocay/android_kernel_xiaomi_sm8350.git
# 把同版本官方 boot.img、vendor_boot.img 放到 ../images/
./build_boot.sh                      # KernelSU-Next + Droidspaces
EXTRA_CONFIGS="kernelsu_next.config" ./build_boot.sh   # 只要 KernelSU-Next
EXTRA_CONFIGS= ./build_boot.sh       # 原版内核
```
产物为 `out/boot.img`。KernelSU-Next 的 submodule 不能浅克隆，它的版本号按提交数计算。

刷入与回滚：
```bash
fastboot flash boot out/boot.img
fastboot flash boot /path/to/official/boot.img    # 回滚
```
WSL2 里看不到手机，需要用 Windows 侧的 `fastboot`。

配套应用：KernelSU-Next 管理器 v3.4.0、Droidspaces v6.6.0。

---

## 七、注意事项

- **`CONFIG_USER_NS` 的代价**：所有普通应用也能创建用户命名空间，Android 内核通常关闭它。它只为容器内运行 Docker 而开；不需要时删掉 `droidspaces.config` 最后一行重新编译。
- **官方系统升级后**：如果新版官方内核换了提交号，需要同步源码并修改 `build_boot.sh` 里的 `SCMVERSION`，脚本检测到不一致会直接报错。全量 CRC 基线也要用新的原版构建重新生成（`EXTRA_CONFIGS= SAVE_ABI_BASELINE=1 ./build_boot.sh`）。
- **ABI 检查的覆盖范围**：`vendor_boot` 之外的模块（WiFi、相机等）靠本地基线文件覆盖，这个文件不在仓库里；新克隆的环境需要先生成一次。
- **不要超出 `droidspaces.config` 的选项范围**：`CGROUP_DEVICE`、`CGROUP_PIDS` 等会改变内核结构体布局。
- **升级 KernelSU-Next 时**：重新检查它的 `kernel/Kbuild` 是否新增了编译期修改内核源码的 `sed`，并核对各挂钩函数的签名。
- **安全模式**：开机时连按三次音量下键可禁用所有 KernelSU 模块。
