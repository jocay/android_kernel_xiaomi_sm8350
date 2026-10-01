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
| `boot-ksu-droidspaces-server.img` | + BBR / fq_codel（`server_net.config`） | 已验证：正常开机；BBR 与 fq_codel 生效 |

五个镜像的内核版本串都是 `5.4.302-qgki-g7ede20c8692e`，与官方一致。

SHA-256：
```
a460971bae8f13b1228228ae57b9cde969df18bcb94c47dc0a9087609d76a171  boot-stock-rebuild.img
2a047069ab16f85efb47b1a7e5fa7a568d71dd7740e300d00d2cbffd0800637d  boot-ksu-next.img
225d4070a3d902a4c91b891825f530def462f769c4f833cc7440acf1f6cbcfb9  boot-ksu-droidspaces.img
9a510a158a45de5944a7a7a89b5886d7af49129ab203631bc25a94b9194fab0e  boot-ksu-droidspaces-userns.img
97f6a4d8ecd4f6e9c78026eda9d0abac4db521c2a8f2d612fdaee41f7f1f6026  boot-ksu-droidspaces-server.img
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

以上两部分相对官方配置共多出 26 项：24 项来自两个片段及其依赖，2 项是主机探测项 `CC_CAN_LINK*`；没有任何官方选项被关闭或改值。第 4 点的网络片段另有增改，见下。除文档外，源码改动为 19 个文件、+437 / −99 行，其中 `build_boot.sh` 占大部分。

### 4. 服务器化（内核部分）
配置片段 `arch/arm64/configs/vendor/server_net.config`：TCP 拥塞控制默认改为 BBR（cubic 仍可切换），默认队列算法由 `pfifo_fast` 改为 fq_codel，同时内置 fq。`build_boot.sh` 默认合入。它把官方的 `DEFAULT_TCP_CONG="cubic"` 改成了 `"bbr"`，这是唯一一处改动官方选项取值的地方。

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

## 六、服务器化（运行时部分）：`android/venus_server/`

WiFi 驱动是 vendor 分区里的官方模块，温控由用户态服务决定，这些都不在 `boot.img` 里，所以做成了一个 KernelSU 模块，开机自动应用。可调项在 `config.sh`，开机日志在手机的 `/data/adb/modules/venus_server/boot.log`。

| 项目 | 做法 | 真机结果 |
|---|---|---|
| 温控降频 | 停掉小米的 `mi_thermald` 并清除它留下的限制 | 大核 2112 → 2419 MHz，超大核 2150 → 2841 MHz，GPU 限制解除 |
| CPU | 三个簇用 performance 调频，关闭深度空闲状态 | 生效 |
| 防休眠 | 关闭 Doze，持有唤醒锁 | 生效 |
| 充电上限 | LineageOS 充电控制，70%（系统只允许 70–100） | 生效 |
| WiFi | 关闭省电、强制高性能和低延迟模式，每 30 秒检查一次 | 省电已关 |
| TCP | BBR、fq_codel、加大缓冲、关闭空闲后慢启动、TFO | 生效（需本分支内核） |
| 联网检测与 NTP | 检测地址换成国内可达的，NTP 换成 `ntp.aliyun.com` | WiFi 由“部分连接”变为已验证，NTP 同步成功 |
| adb | 开机监听 TCP 5555，关闭授权 | 用另一台 adb 客户端（WSL 内，密钥不同）可直接连接，没有授权弹窗 |

几点说明：

- **降频全部来自 `mi_thermald`**：它在主板 15°C 时就已把大核和超大核限在硬件上限以下，39°C 起继续下压。
- **内核温区默认保留**（`DISABLE_KERNEL_PASSIVE_TRIPS=0`）：它们只在主板 78°C 或结温 108°C 以上才动作，是这台机器上仅有的过热保护，正常运行时不影响性能。
- **adb 免认证的代价**：能访问 5555 端口的人都能拿到 shell；Shell 在 KernelSU 里被授予 root 时，等同于拿到 root。只适合可信的局域网。
- **停掉 `mi_thermald` 后**，它按温度分级限制充电电流的逻辑也随之失效，充电芯片自身的电池温度保护不受影响。
- 模块 v1.0–v1.2 在真机上跑过；**v1.3（加入联网检测与 NTP 设置）尚未在真机上跑过开机流程**，其中的设置项本身已手动应用并验证。

打包与安装：
```bash
android/venus_server/pack.sh /tmp
adb push /tmp/venus_server-v1.3.zip /data/local/tmp/
adb shell su -c "ksud module install /data/local/tmp/venus_server-v1.3.zip"   # 重启后生效
```

---

## 七、如何复现

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

## 八、注意事项

- **`CONFIG_USER_NS` 的代价**：所有普通应用也能创建用户命名空间，Android 内核通常关闭它。它只为容器内运行 Docker 而开；不需要时删掉 `droidspaces.config` 最后一行重新编译。
- **官方系统升级后**：如果新版官方内核换了提交号，需要同步源码并修改 `build_boot.sh` 里的 `SCMVERSION`，脚本检测到不一致会直接报错。全量 CRC 基线也要用新的原版构建重新生成（`EXTRA_CONFIGS= SAVE_ABI_BASELINE=1 ./build_boot.sh`）。
- **ABI 检查的覆盖范围**：`vendor_boot` 之外的模块（WiFi、相机等）靠本地基线文件覆盖，这个文件不在仓库里；新克隆的环境需要先生成一次。
- **不要超出 `droidspaces.config` 的选项范围**：`CGROUP_DEVICE`、`CGROUP_PIDS` 等会改变内核结构体布局。
- **升级 KernelSU-Next 时**：重新检查它的 `kernel/Kbuild` 是否新增了编译期修改内核源码的 `sed`，并核对各挂钩函数的签名。
- **安全模式**：开机时连按三次音量下键可禁用所有 KernelSU 模块。
