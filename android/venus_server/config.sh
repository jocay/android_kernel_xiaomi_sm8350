# Tunables for the Venus Server Tuning module. Edit, then reboot.
# On the device: /data/adb/modules/venus_server/config.sh

# --- Thermal -----------------------------------------------------------------
# 1: stop mi_thermald, Xiaomi's daemon that caps CPU/GPU frequency by board
#    temperature (it caps the big cores even when the phone is cold).
#    This also drops its temperature-based charging-current steps; the
#    charger's own battery temperature protection is not affected.
DISABLE_MI_THERMALD=1

# 1: also disable the kernel's own thermal zones (the "*-step" ones). They
#    only act at 78 C board / 108 C junction and above, so they cost nothing in
#    normal operation and are the last protection if the cooler fails.
#    Leave at 0 unless you accept losing that.
DISABLE_KERNEL_PASSIVE_TRIPS=0

# --- CPU ---------------------------------------------------------------------
# cpufreq governor for all clusters: performance | schedutil
CPU_GOVERNOR=performance
# 1: disable the deep idle state (C1, ~0.5 ms wake-up) so cores answer
#    interrupts faster. Raises idle power draw.
DISABLE_DEEP_IDLE=1

# --- Power management --------------------------------------------------------
# 1: disable doze / app standby idle modes and hold a wakelock so the system
#    never suspends with the screen off.
STAY_AWAKE=1
# Stop charging at this percentage (70-100, LineageOS charging control).
# Empty: leave the system setting alone.
CHARGE_LIMIT=70

# --- Network -----------------------------------------------------------------
# 1: keep Wi-Fi out of power save and in low-latency mode.
WIFI_LOW_LATENCY=1
# 1: apply TCP settings (BBR and fq_codel when the kernel has them, larger
#    buffers, no slow start after idle, TCP Fast Open).
NET_TUNING=1

# --- Connectivity check and time ---------------------------------------------
# Android decides whether a network "has internet" by fetching these URLs, and
# its defaults (Google) are not fully reachable from mainland China, so Wi-Fi
# shows as having no internet. Empty CONNECTIVITY_CHECK_HOST: leave the system
# defaults alone.
CONNECTIVITY_CHECK_HOST=connectivitycheck.platform.hicloud.com
CONNECTIVITY_CHECK_FALLBACKS="http://connect.rom.miui.com/generate_204,http://wifi.vivo.com.cn/generate_204,http://www.google.cn/generate_204"
# NTP server (the default time.android.com is unreachable there too).
# Empty: leave the system default alone.
NTP_SERVER=ntp.aliyun.com

# --- adb ---------------------------------------------------------------------
# TCP port adbd listens on at every boot. Empty: USB only.
ADB_TCP_PORT=5555
# 1: accept any adb client without authorization (USB and TCP).
#    Anyone who can reach the port gets a shell, and root if Shell is granted
#    root in KernelSU. Only for a trusted network.
ADB_NO_AUTH=1
