#!/bin/sh

set -eu
SOURCE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

[ "$(id -u)" = "0" ] || { echo "请使用 root 运行安装脚本" >&2; exit 1; }
[ -f /etc/config/passwall ] || { echo "未检测到 PassWall" >&2; exit 1; }
[ -x /usr/sbin/nft ] || { echo "当前系统缺少 nftables" >&2; exit 1; }

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/root/passwall-device-backup-$STAMP"
mkdir -p "$BACKUP"
cp -p /etc/config/passwall "$BACKUP/passwall"
cp -p /etc/config/dhcp "$BACKUP/dhcp"
[ -f /etc/config/passwall_device ] && cp -p /etc/config/passwall_device "$BACKUP/passwall_device" || true

previous_enabled="$(uci -q get passwall.@global[0].enabled || echo 0)"
previous_acl="$(uci -q get passwall.@global[0].acl_enable || echo 0)"
EXISTING_CONFIG=""
if [ -f /etc/config/passwall_device ]; then
	EXISTING_CONFIG="/tmp/passwall_device.install.$$"
	cp -p /etc/config/passwall_device "$EXISTING_CONFIG"
fi

cp -a "$SOURCE_DIR/root/." /
[ -n "$EXISTING_CONFIG" ] && { cp -p "$EXISTING_CONFIG" /etc/config/passwall_device; rm -f "$EXISTING_CONFIG"; }
chmod 755 /etc/init.d/passwall-device /usr/share/passwall-device/*.sh /usr/share/passwall-device/app.lua
chmod 644 /usr/lib/lua/luci/controller/passwall_device.lua /usr/lib/lua/luci/view/passwall_device/*.htm /usr/share/rpcd/acl.d/luci-app-passwall-device.json /usr/share/passwall-device/VERSION
uci -q get passwall_device.global.previous_passwall_enabled >/dev/null || uci set passwall_device.global.previous_passwall_enabled="$previous_enabled"
uci -q get passwall_device.global.previous_acl_enable >/dev/null || uci set passwall_device.global.previous_acl_enable="$previous_acl"
uci commit passwall_device
/usr/share/passwall-device/app.lua migrate >/tmp/pwc-migrate.log 2>&1 || true
/etc/init.d/passwall-device enable
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache /tmp/luci-*
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/nginx reload >/dev/null 2>&1 || true

echo "安装完成，配置备份：$BACKUP"
echo "请进入 LuCI：服务 -> PassWall 设备口令"
echo "认证服务默认保持关闭，请先导入节点并确认口令后再启用。"
