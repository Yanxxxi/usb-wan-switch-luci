#!/bin/sh

set -eu

if [ "$(id -u)" != "0" ]; then
	echo "Run this on OpenWrt as root." >&2
	exit 1
fi

if [ ! -f files/root/f50-wan-switch.sh ]; then
	echo "Run this script from the unpacked f50-wan-switch-luci-export directory." >&2
	exit 1
fi

stamp="$(date +%Y%m%d-%H%M%S)"
backup="/root/f50-wan-switch-luci-backup-$stamp.tgz"

tar czf "$backup" \
	/root/f50-wan-switch.sh \
	/usr/lib/lua/luci/controller/wan_switch.lua \
	/usr/lib/lua/luci/model/cbi/wan_switch.lua \
	/usr/lib/lua/luci/view/wan_switch/status.htm \
	2>/dev/null || true

mkdir -p /root
mkdir -p /usr/lib/lua/luci/controller
mkdir -p /usr/lib/lua/luci/model/cbi
mkdir -p /usr/lib/lua/luci/view/wan_switch

cp files/root/f50-wan-switch.sh /root/f50-wan-switch.sh
cp files/usr/lib/lua/luci/controller/wan_switch.lua /usr/lib/lua/luci/controller/wan_switch.lua
cp files/usr/lib/lua/luci/model/cbi/wan_switch.lua /usr/lib/lua/luci/model/cbi/wan_switch.lua
cp files/usr/lib/lua/luci/view/wan_switch/status.htm /usr/lib/lua/luci/view/wan_switch/status.htm

chmod 755 /root/f50-wan-switch.sh
chmod 644 /usr/lib/lua/luci/controller/wan_switch.lua
chmod 644 /usr/lib/lua/luci/model/cbi/wan_switch.lua
chmod 644 /usr/lib/lua/luci/view/wan_switch/status.htm

rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
/etc/init.d/uhttpd reload 2>/dev/null || true

echo "Installed LuCI plugin and campus/USB switch script."
echo "Backup: $backup"
echo ""
echo "Next steps:"
echo "  1. Make sure /etc/config/network has interface 'usb' on device 'usb0'."
echo "     See examples/network-f50.conf."
echo "  2. Add network 'usb' into your existing wan firewall zone."
echo "     See examples/firewall-wan-zone-snippet.conf."
echo "  3. Merge examples/mwan3.conf into /etc/config/mwan3."
echo "     The default_rule should use campus_only during daytime."
echo "  4. Add examples/crontab.root into root crontab."
echo "  5. Create /root/cumt/login.sh yourself and chmod +x it."
echo ""
echo "LuCI entry: Services -> 校园网/随身WiFi切换"
