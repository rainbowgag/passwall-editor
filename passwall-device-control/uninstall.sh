#!/bin/sh

set -eu
[ "$(id -u)" = "0" ] || { echo "请使用 root 运行卸载脚本" >&2; exit 1; }

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/root/passwall-device-uninstall-backup-$STAMP"
mkdir -p "$BACKUP"
cp -p /etc/config/passwall "$BACKUP/passwall" 2>/dev/null || true
cp -p /etc/config/dhcp "$BACKUP/dhcp" 2>/dev/null || true
cp -p /etc/config/passwall_device "$BACKUP/passwall_device" 2>/dev/null || true

/etc/init.d/passwall-device stop >/dev/null 2>&1 || true
/etc/init.d/passwall-device disable >/dev/null 2>&1 || true

if [ -f /etc/config/passwall_device ]; then
	for section in $(uci -q show passwall_device | sed -n 's/^passwall_device\.\([^.=]*\)=binding$/\1/p'); do
		acl="$(uci -q get passwall_device.$section.acl_id || true)"
		[ -n "$acl" ] && uci -q delete "passwall.$acl" || true
	done
	for section in $(uci -q show passwall_device | sed -n 's/^passwall_device\.\([^.=]*\)=node$/\1/p'); do
		node="$(uci -q get passwall_device.$section.passwall_id || true)"
		[ -n "$node" ] && uci -q delete "passwall.$node" || true
	done
	for section in $(uci -q show dhcp | sed -n 's/^dhcp\.\(pwc_[^.=]*\)=host$/\1/p'); do uci -q delete "dhcp.$section" || true; done
	previous_enabled="$(uci -q get passwall_device.global.previous_passwall_enabled || echo 0)"
	previous_acl="$(uci -q get passwall_device.global.previous_acl_enable || echo 0)"
	uci set passwall.@global[0].enabled="$previous_enabled"
	uci set passwall.@global[0].acl_enable="$previous_acl"
	uci commit passwall
	uci commit dhcp
fi

rm -f /etc/init.d/passwall-device
rm -rf /usr/share/passwall-device /usr/lib/lua/luci/controller/passwall_device.lua /usr/lib/lua/luci/view/passwall_device
rm -f /usr/share/rpcd/acl.d/luci-app-passwall-device.json /etc/config/passwall_device
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache /tmp/luci-*
/etc/init.d/passwall restart >/dev/null 2>&1 || true
/etc/init.d/dnsmasq reload >/dev/null 2>&1 || true
/etc/init.d/nginx reload >/dev/null 2>&1 || true

echo "卸载完成，卸载前配置备份：$BACKUP"

