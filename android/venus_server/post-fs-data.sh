#!/system/bin/sh
# Runs before adbd starts, so adbd picks these properties up on its first start.
MODDIR=${0%/*}
. "$MODDIR/config.sh"

# adbd only honours ro.adb.secure=0 on debuggable builds or with an unlocked
# bootloader (ro.boot.verifiedbootstate=orange); this device is unlocked.
[ "$ADB_NO_AUTH" = 1 ] && resetprop -n ro.adb.secure 0

# Not a persist.* property on purpose: removing the module restores USB-only.
[ -n "$ADB_TCP_PORT" ] && resetprop -n service.adb.tcp.port "$ADB_TCP_PORT"

exit 0
