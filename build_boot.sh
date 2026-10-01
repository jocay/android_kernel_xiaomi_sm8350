#!/usr/bin/env bash
# ==============================================================================
# Xiaomi 11 (venus) LineageOS 23.2 (Android 16) Kernel & Boot.img Build Script
# ==============================================================================
#
# Only boot.img is rebuilt; the prebuilt modules in the official vendor_boot
# and vendor images stay in place. The kernel therefore has to keep the
# official release string (vermagic) and exported-symbol CRCs, and the script
# refuses to produce an image when either one drifts.
#
# Environment:
#   TOOLS            tool root (default ~/android/tools), laid out as
#                    toolchains/clang-r563880c, boot/mkbootimg, boot/avb,
#                    downloads/. Missing tools are downloaded.
#   IMAGES_DIR       official images (default ../images); boot.img is
#                    required, vendor_boot.img enables the module ABI check.
#   EXTRA_CONFIGS    space-separated config fragments (paths, or names under
#                    arch/arm64/configs/vendor) merged over the official
#                    config. Default: the optional fragments present in the
#                    tree. Set it empty for a stock build.
#   SCMVERSION       release suffix of the official kernel.
#   SAVE_ABI_BASELINE=1  record this build's symbol CRCs as the baseline that
#                    later builds are compared against (use on a stock build).
#   JOBS             parallel jobs (default: all cores).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS="${TOOLS:-$HOME/android/tools}"
IMAGES_DIR="${IMAGES_DIR:-$ROOT_DIR/../images}"
SCMVERSION="${SCMVERSION:--g7ede20c8692e}"
JOBS="${JOBS:-$(nproc)}"

AOSP_TAG="android-16.0.0_r4"
AOSP_URL="https://android.googlesource.com/platform"
CLANG_DIR="$TOOLS/toolchains/clang-r563880c"
MKBOOTIMG_DIR="$TOOLS/boot/mkbootimg"
AVB_DIR="$TOOLS/boot/avb"

CONFIG_DIR="$ROOT_DIR/arch/arm64/configs/vendor"
OPTIONAL_CONFIGS="kernelsu_next.config droidspaces.config"

OUT_DIR="$ROOT_DIR/out"
KERNEL_OBJ="$OUT_DIR/kernel_obj"
UNPACK_DIR="$OUT_DIR/official_boot_unpacked"
VENDOR_BOOT_DIR="$OUT_DIR/official_vendor_boot_unpacked"
OFFICIAL_CONFIG="$OUT_DIR/official_kernel.config"
ABI_BASELINE="${ABI_BASELINE:-$OUT_DIR/baseline_crcs.txt}"
BOOT_IMG_OUT="$OUT_DIR/boot.img"
OFFICIAL_BOOT="$IMAGES_DIR/boot.img"
OFFICIAL_VENDOR_BOOT="$IMAGES_DIR/vendor_boot.img"

echo "=================================================================="
echo " Building Kernel & Boot Image for Xiaomi 11 (venus) - LineageOS 23.2"
echo "=================================================================="

for cmd in make bc bison flex python3 curl tar cpio gzip aarch64-linux-gnu-gcc; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: Required command '$cmd' is missing." >&2
        echo "Install dependencies: sudo apt install -y build-essential bc bison flex libssl-dev python3 libelf-dev gcc-aarch64-linux-gnu curl tar cpio" >&2
        exit 1
    fi
done
if [[ ! -f "$OFFICIAL_BOOT" ]]; then
    echo "Error: official boot.img not found at $OFFICIAL_BOOT" >&2
    echo "Place the official images there or set IMAGES_DIR=/path/to/images" >&2
    exit 1
fi

# fetch_tool <archive name> <url> <destination> <file that proves it is complete>
# The archive is downloaded and unpacked next to its final location and only
# moved into place when complete, so an interrupted run leaves nothing behind
# that a later run would mistake for a finished install.
fetch_tool() {
    local name=$1 url=$2 dest=$3 marker=$4
    local archive="$TOOLS/downloads/$name.tar.gz"
    [[ -e "$dest/$marker" ]] && return 0
    echo "Fetching $name ..."
    mkdir -p "$TOOLS/downloads" "$(dirname "$dest")"
    if [[ ! -f "$archive" ]]; then
        curl -fL --retry 3 --connect-timeout 30 "$url" -o "$archive.part"
        mv "$archive.part" "$archive"
    fi
    rm -rf "$dest" "$dest.tmp"
    mkdir -p "$dest.tmp"
    tar -xzf "$archive" -C "$dest.tmp"
    mv "$dest.tmp" "$dest"
}

echo "=== [1/6] Checking tools in $TOOLS ==="
fetch_tool clang-r563880c \
    "$AOSP_URL/prebuilts/clang/host/linux-x86/+archive/refs/tags/$AOSP_TAG/clang-r563880c.tar.gz" \
    "$CLANG_DIR" bin/clang
fetch_tool "mkbootimg-$AOSP_TAG" \
    "$AOSP_URL/system/tools/mkbootimg/+archive/refs/tags/$AOSP_TAG.tar.gz" \
    "$MKBOOTIMG_DIR" mkbootimg.py
fetch_tool "avb-$AOSP_TAG" \
    "$AOSP_URL/external/avb/+archive/refs/tags/$AOSP_TAG.tar.gz" \
    "$AVB_DIR" avbtool.py

export PATH="$CLANG_DIR/bin:$PATH"
echo "Using compiler: $(clang --version | head -n 1)"

MAKE_ARGS=(
    -C "$ROOT_DIR" O="$KERNEL_OBJ" ARCH=arm64 SUBARCH=arm64
    CC=clang LLVM=1 LLVM_IAS=1
    CLANG_TRIPLE=aarch64-linux-gnu-
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
    TARGET_PRODUCT=venus
)

# Everything taken from the official images is re-read on every run, so a
# replaced boot.img can never be mixed with stale leftovers.
echo "=== [2/6] Reading the official boot image ==="
mkdir -p "$OUT_DIR"
rm -rf "$UNPACK_DIR"
python3 "$MKBOOTIMG_DIR/unpack_bootimg.py" --boot_img "$OFFICIAL_BOOT" --out "$UNPACK_DIR" > "$OUT_DIR/official_boot_info.txt"
AVB_INFO="$(python3 "$AVB_DIR/avbtool.py" info_image --image "$OFFICIAL_BOOT")"
OS_VERSION="$(sed -n 's/^os version: //p' "$OUT_DIR/official_boot_info.txt")"
OS_PATCH_LEVEL="$(sed -n 's/^os patch level: //p' "$OUT_DIR/official_boot_info.txt")"
PARTITION_SIZE="$(stat -c%s "$OFFICIAL_BOOT")"
SALT="$(sed -n 's/^ *Salt: *//p' <<<"$AVB_INFO")"
AVB_OS_VERSION="$(sed -n "s/^ *Prop: com.android.build.boot.os_version -> '\(.*\)'$/\1/p" <<<"$AVB_INFO")"
FINGERPRINT="$(sed -n "s/^ *Prop: com.android.build.boot.fingerprint -> '\(.*\)'$/\1/p" <<<"$AVB_INFO")"
OFFICIAL_RELEASE="$(grep -a -m1 -o 'Linux version [0-9][^ ]*' "$UNPACK_DIR/kernel" | awk '{print $3}')"
echo "Official kernel: $OFFICIAL_RELEASE, OS $OS_VERSION, patch level $OS_PATCH_LEVEL"
if [[ "$OFFICIAL_RELEASE" != *"$SCMVERSION" ]]; then
    echo "Error: official kernel release '$OFFICIAL_RELEASE' does not end with '$SCMVERSION'." >&2
    echo "The official image is from another kernel commit; set SCMVERSION to its -g<hash> suffix" >&2
    echo "and make sure this source tree matches that commit." >&2
    exit 1
fi

echo "=== [3/6] Preparing Kernel Configuration ==="
# Regenerated on every run so config edits are never silently ignored.
# Base: the config embedded in the official kernel (CONFIG_IKCONFIG).
mkdir -p "$KERNEL_OBJ"
echo "$SCMVERSION" > "$ROOT_DIR/.scmversion"
if "$ROOT_DIR/scripts/extract-ikconfig" "$UNPACK_DIR/kernel" > "$OFFICIAL_CONFIG.tmp"; then
    mv "$OFFICIAL_CONFIG.tmp" "$OFFICIAL_CONFIG"
    CONFIGS=("$OFFICIAL_CONFIG")
else
    rm -f "$OFFICIAL_CONFIG.tmp"
    echo "Warning: no config embedded in the official kernel; merging the venus defconfigs instead." >&2
    CONFIGS=("$CONFIG_DIR/lahaina-qgki_defconfig" "$CONFIG_DIR/debugfs.config"
             "$CONFIG_DIR/xiaomi_QGKI.config" "$CONFIG_DIR/venus_QGKI.config")
fi
if [[ -z "${EXTRA_CONFIGS+set}" ]]; then
    EXTRA_CONFIGS=""
    for f in $OPTIONAL_CONFIGS; do
        [[ -f "$CONFIG_DIR/$f" ]] && EXTRA_CONFIGS+=" $f"
    done
fi
EXTRA=()
for f in $EXTRA_CONFIGS; do
    [[ -f "$f" ]] || f="$CONFIG_DIR/$f"
    [[ -f "$f" ]] || { echo "Error: config fragment $f not found" >&2; exit 1; }
    EXTRA+=("$f")
done
echo "Base: ${CONFIGS[*]##*/}  Extra: ${EXTRA[*]##*/}"
ARCH=arm64 "$ROOT_DIR/scripts/kconfig/merge_config.sh" -m -O "$KERNEL_OBJ" \
    "${CONFIGS[@]}" "${EXTRA[@]}" > /dev/null
make "${MAKE_ARGS[@]}" olddefconfig
for f in "${EXTRA[@]}"; do
    while read -r opt; do
        grep -qxF "$opt" "$KERNEL_OBJ/.config" || {
            echo "Error: $opt from ${f##*/} did not survive olddefconfig" >&2; exit 1; }
    done < <(grep -E '^CONFIG_' "$f")
done

echo "=== [4/6] Compiling Kernel Image with $JOBS jobs ==="
make -j"$JOBS" "${MAKE_ARGS[@]}" Image

KERNEL_IMAGE="$KERNEL_OBJ/arch/arm64/boot/Image"
RELEASE="$(cat "$KERNEL_OBJ/include/config/kernel.release")"
echo "Kernel release: $RELEASE ($(stat -c%s "$KERNEL_IMAGE") bytes)"
if [[ "$RELEASE" != "$OFFICIAL_RELEASE" ]]; then
    echo "Error: kernel release '$RELEASE' differs from the official '$OFFICIAL_RELEASE';" >&2
    echo "the prebuilt vendor modules would refuse to load." >&2
    exit 1
fi

# The prebuilt modules are matched against exported-symbol CRCs
# (CONFIG_MODVERSIONS), so no CRC a module relies on may change.
echo "=== [5/6] Checking module ABI ==="
llvm-nm "$KERNEL_OBJ/vmlinux" | awk '$3 ~ /^__crc_/ {print substr($3, 7), $1}' | sort > "$OUT_DIR/current_crcs.txt"
if [[ -f "$OFFICIAL_VENDOR_BOOT" ]]; then
    rm -rf "$VENDOR_BOOT_DIR"
    python3 "$MKBOOTIMG_DIR/unpack_bootimg.py" --boot_img "$OFFICIAL_VENDOR_BOOT" --out "$VENDOR_BOOT_DIR" > /dev/null
    mkdir "$VENDOR_BOOT_DIR/ramdisk"
    { gzip -dc "$VENDOR_BOOT_DIR/vendor_ramdisk" 2>/dev/null || lz4 -dc "$VENDOR_BOOT_DIR/vendor_ramdisk"; } \
        | (cd "$VENDOR_BOOT_DIR/ramdisk" && cpio -id --quiet '*.ko' 2>/dev/null)
    python3 - "$OUT_DIR/current_crcs.txt" "$VENDOR_BOOT_DIR/ramdisk" <<'EOF'
import pathlib, struct, subprocess, sys, tempfile

crcs = {}
for line in open(sys.argv[1]):
    name, crc = line.split()
    crcs[name] = int(crc, 16)

modules = sorted(pathlib.Path(sys.argv[2]).rglob("*.ko"))
if not modules:
    sys.exit("Error: no modules found in the official vendor_boot ramdisk")
checked = bad = 0
with tempfile.NamedTemporaryFile() as tmp:
    for mod in modules:
        subprocess.run(["llvm-objcopy", "-O", "binary", "--only-section=__versions",
                        str(mod), tmp.name], check=True)
        data = pathlib.Path(tmp.name).read_bytes()
        # struct modversion_info { unsigned long crc; char name[56]; }
        for off in range(0, len(data), 64):
            crc = struct.unpack_from("<Q", data, off)[0]
            name = data[off + 8:off + 64].split(b"\0")[0].decode()
            if name not in crcs:
                continue  # exported by another module, not by vmlinux
            checked += 1
            if crcs[name] != crc:
                bad += 1
                print(f"  {mod.name}: {name} wants {crc:#x}, kernel has {crcs[name]:#x}",
                      file=sys.stderr)
if bad:
    sys.exit(f"Error: {bad} symbol CRCs differ from what the official vendor_boot modules "
             "expect; they would fail to load.")
print(f"vendor_boot: {checked} symbol CRCs used by {len(modules)} official modules all match")
EOF
else
    echo "Warning: $OFFICIAL_VENDOR_BOOT not found, skipping the vendor_boot module check." >&2
fi
if [[ -n "${SAVE_ABI_BASELINE:-}" ]]; then
    cp "$OUT_DIR/current_crcs.txt" "$ABI_BASELINE"
    echo "Saved $(wc -l < "$ABI_BASELINE") symbol CRCs as baseline: $ABI_BASELINE"
elif [[ -f "$ABI_BASELINE" ]]; then
    comm -23 "$ABI_BASELINE" "$OUT_DIR/current_crcs.txt" > "$OUT_DIR/abi_breaks.txt"
    if [[ -s "$OUT_DIR/abi_breaks.txt" ]]; then
        echo "Error: $(wc -l < "$OUT_DIR/abi_breaks.txt") exported symbols changed or vanished vs $ABI_BASELINE" >&2
        echo "(see $OUT_DIR/abi_breaks.txt); modules in the vendor partitions would fail to load." >&2
        exit 1
    fi
    echo "baseline: all $(wc -l < "$ABI_BASELINE") symbol CRCs unchanged"
else
    echo "Note: no CRC baseline at $ABI_BASELINE, so modules outside vendor_boot are not covered."
    echo "      Create one from a stock build: EXTRA_CONFIGS= SAVE_ABI_BASELINE=1 $0"
fi

echo "=== [6/6] Packaging boot.img & Adding AVB Hash Footer ==="
python3 "$MKBOOTIMG_DIR/mkbootimg.py" \
    --header_version 3 \
    --kernel "$KERNEL_IMAGE" \
    --ramdisk "$UNPACK_DIR/ramdisk" \
    --os_version "$OS_VERSION" \
    --os_patch_level "$OS_PATCH_LEVEL" \
    --pagesize 4096 \
    -o "$BOOT_IMG_OUT"

python3 "$AVB_DIR/avbtool.py" add_hash_footer \
    --image "$BOOT_IMG_OUT" \
    --partition_size "$PARTITION_SIZE" \
    --partition_name boot \
    --algorithm NONE \
    --salt "$SALT" \
    --prop "com.android.build.boot.os_version:$AVB_OS_VERSION" \
    --prop "com.android.build.boot.fingerprint:$FINGERPRINT"

echo "=================================================================="
echo " SUCCESS! Boot image generated at: $BOOT_IMG_OUT"
echo " Size: $(stat -c%s "$BOOT_IMG_OUT") bytes"
echo " To flash:"
echo "   fastboot flash boot $BOOT_IMG_OUT"
echo " To restore official boot:"
echo "   fastboot flash boot $OFFICIAL_BOOT"
echo "=================================================================="
