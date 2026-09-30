#!/usr/bin/env bash
# ==============================================================================
# Xiaomi 11 (venus) LineageOS 23.2 (Android 16) Kernel & Boot.img Build Script
# ==============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDTOOLS_DIR="${BUILDTOOLS_DIR:-$HOME/android/buildtools}"
CLANG_DIR="${BUILDTOOLS_DIR}/clang-r563880c"
MKBOOTIMG_DIR="${BUILDTOOLS_DIR}/mkbootimg"
AVB_DIR="${BUILDTOOLS_DIR}/avb"

# Official image reference directory
IMAGES_DIR="${IMAGES_DIR:-$ROOT_DIR/../images}"

OUT_DIR="${ROOT_DIR}/out"
KERNEL_OBJ="${OUT_DIR}/kernel_obj"
BOOT_IMG_OUT="${OUT_DIR}/boot.img"
RAMDISK_FILE="${OUT_DIR}/official_boot_unpacked/ramdisk"

JOBS="${JOBS:-$(nproc)}"

echo "=================================================================="
echo " Building Kernel & Boot Image for Xiaomi 11 (venus) - LineageOS 23.2"
echo "=================================================================="

# Check host dependencies
for cmd in make bc bison flex python3 aarch64-linux-gnu-gcc; do
    if ! command -v "${cmd}" &>/dev/null; then
        echo "Error: Required command '${cmd}' is missing." >&2
        echo "Install dependencies: sudo apt install -y build-essential bc bison flex libssl-dev python3 libelf-dev gcc-aarch64-linux-gnu" >&2
        exit 1
    fi
done

# Step 1: Check Toolchain
echo "=== [1/5] Checking Toolchain in ${BUILDTOOLS_DIR} ==="
if [ ! -d "${CLANG_DIR}/bin" ]; then
    echo "Clang not found. Downloading clang-r563880c..."
    mkdir -p "${CLANG_DIR}"
    curl -L "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/tags/android-16.0.0_r4/clang-r563880c.tar.gz" | tar -xz -C "${CLANG_DIR}"
fi

if [ ! -f "${MKBOOTIMG_DIR}/mkbootimg.py" ]; then
    echo "mkbootimg not found. Downloading mkbootimg..."
    git clone --depth 1 -b lineage-22.1 https://github.com/LineageOS/android_system_tools_mkbootimg "${MKBOOTIMG_DIR}" 2>&1 || \
    git clone --depth 1 https://github.com/LineageOS/android_system_tools_mkbootimg "${MKBOOTIMG_DIR}"
fi

if [ ! -f "${AVB_DIR}/avbtool.py" ]; then
    echo "avbtool not found. Downloading avb..."
    git clone --depth 1 -b lineage-22.1 https://github.com/LineageOS/android_external_avb "${AVB_DIR}" 2>&1 || \
    git clone --depth 1 https://github.com/LineageOS/android_external_avb "${AVB_DIR}"
fi

export PATH="${CLANG_DIR}/bin:${PATH}"
echo "Using compiler: $(clang --version | head -n 1)"

# Step 2: Kernel Configuration
echo "=== [2/5] Preparing Kernel Configuration ==="
mkdir -p "${KERNEL_OBJ}"
if [ ! -f "${KERNEL_OBJ}/.config" ]; then
    if [ -f "${OUT_DIR}/official_kernel.config" ]; then
        echo "Using extracted official .config"
        cp "${OUT_DIR}/official_kernel.config" "${KERNEL_OBJ}/.config"
    else
        echo "Merging defconfigs for venus..."
        ARCH=arm64 "${ROOT_DIR}/scripts/kconfig/merge_config.sh" -m -O "${KERNEL_OBJ}" \
            "${ROOT_DIR}/arch/arm64/configs/vendor/lahaina-qgki_defconfig" \
            "${ROOT_DIR}/arch/arm64/configs/vendor/debugfs.config" \
            "${ROOT_DIR}/arch/arm64/configs/vendor/xiaomi_QGKI.config" \
            "${ROOT_DIR}/arch/arm64/configs/vendor/venus_QGKI.config"
    fi
    make O="${KERNEL_OBJ}" ARCH=arm64 CC=clang LLVM=1 LLVM_IAS=1 TARGET_PRODUCT=venus olddefconfig
fi

# Step 3: Compile Kernel Image
echo "=== [3/5] Compiling Kernel Image with ${JOBS} jobs ==="
make -j"${JOBS}" O="${KERNEL_OBJ}" ARCH=arm64 CC=clang LLVM=1 LLVM_IAS=1 \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
    TARGET_PRODUCT=venus Image

KERNEL_IMAGE="${KERNEL_OBJ}/arch/arm64/boot/Image"
if [ ! -f "${KERNEL_IMAGE}" ]; then
    echo "Error: Kernel Image failed to build!" >&2
    exit 1
fi
echo "Kernel Image built successfully: $(ls -lh "${KERNEL_IMAGE}" | awk '{print $5}')"

# Step 4: Extract Official Ramdisk
echo "=== [4/5] Preparing Boot Ramdisk ==="
if [ ! -f "${RAMDISK_FILE}" ]; then
    if [ ! -f "${IMAGES_DIR}/boot.img" ]; then
        echo "Error: Reference official boot.img not found at ${IMAGES_DIR}/boot.img" >&2
        echo "Please place the official boot.img in ${IMAGES_DIR}/ or set IMAGES_DIR=/path/to/images" >&2
        exit 1
    fi
    mkdir -p "${OUT_DIR}/official_boot_unpacked"
    python3 "${MKBOOTIMG_DIR}/unpack_bootimg.py" \
        --boot_img "${IMAGES_DIR}/boot.img" \
        --out "${OUT_DIR}/official_boot_unpacked"
fi

# Step 5: Pack boot.img & Add AVB Hash Footer
echo "=== [5/5] Packaging boot.img & Adding AVB Hash Footer ==="
python3 "${MKBOOTIMG_DIR}/mkbootimg.py" \
    --header_version 3 \
    --kernel "${KERNEL_IMAGE}" \
    --ramdisk "${RAMDISK_FILE}" \
    --os_version 16.0.0 \
    --os_patch_level 2026-09 \
    --pagesize 4096 \
    -o "${BOOT_IMG_OUT}"

python3 "${AVB_DIR}/avbtool.py" add_hash_footer \
    --image "${BOOT_IMG_OUT}" \
    --partition_size 201326592 \
    --partition_name boot \
    --algorithm NONE \
    --salt cb93777825c2a5eee97b68ae1c26213c92aa8f8138d549db04d1bebc9f2040c1 \
    --prop com.android.build.boot.os_version:16 \
    --prop com.android.build.boot.fingerprint:Xiaomi/lineage_venus/venus:16/BP4A.251205.006/1b809f17b8:userdebug/release-keys

echo "=================================================================="
echo " SUCCESS! Boot image generated at: ${BOOT_IMG_OUT}"
echo " Size: $(ls -lh "${BOOT_IMG_OUT}" | awk '{print $5}') ($(stat -c%s "${BOOT_IMG_OUT}") bytes)"
echo " To flash:"
echo "   fastboot flash boot ${BOOT_IMG_OUT}"
echo " To restore official boot:"
echo "   fastboot flash boot ${IMAGES_DIR}/boot.img"
echo "=================================================================="
