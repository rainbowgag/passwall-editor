#!/bin/sh

set -eu
MARKER=PWC_BIND_LAN
HOST=bind.lan
LAN_IP="$(uci -q get network.lan.ipaddr || echo 10.0.0.1)"
LAN_IP="${LAN_IP%%/*}"
CONF=/etc/nginx/conf.d/passwall-device.locations
DNS=/etc/dnsmasq.d/passwall-device.conf
TMP_DNS=/tmp/dnsmasq.d/passwall-device.conf
WWW_DIR=/www/pwc-portal
PORTAL_URL="http://$LAN_IP/cgi-bin/luci/pwc"
ADDR_HOSTS="$HOST"
HOSTS_MARKER="# PWC_BIND_LAN"

write_captive_files() {
	page='<html><head><meta http-equiv="refresh" content="0;url='"$PORTAL_URL"'"></head><body>redirect</body></html>'
	for path in generate_204 gen_204 hotspot-detect.html connecttest.txt ncsi.txt redirect success.txt; do
		printf '%s\n' "$page" > "/www/$path"
	done
	mkdir -p /www/library/test
	printf '%s\n' "$page" > /www/library/test/success.html
	# 兼容旧版本残留
	rm -rf "$WWW_DIR"
}

reg_dnsmasq() {
	# 通过 UCI address 列表注册，避免依赖 confdir
	for host in $ADDR_HOSTS; do
		uci -q delete "dhcp.@dnsmasq[0].address" >/dev/null 2>&1 || true
		break
	done
	for host in $ADDR_HOSTS; do
		already=""
		for addr in $(uci -q get "dhcp.@dnsmasq[0].address" 2>/dev/null || true); do
			[ "$addr" = "/$host/$LAN_IP" ] && already=1 && break
		done
		[ -z "$already" ] && uci -q add_list "dhcp.@dnsmasq[0].address=/$host/$LAN_IP" 2>/dev/null || true
	done
	uci -q commit dhcp || true
	# 主 dnsmasq 明确加载 /tmp/dnsmasq.d（conf-dir），双保险确保锚定生效
	mkdir -p /tmp/dnsmasq.d
	{
		for host in $ADDR_HOSTS; do
			printf 'address=/%s/%s\n' "$host" "$LAN_IP"
		done
	} > "$TMP_DNS"
	/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
}

reg_hosts() {
	# 部分 iStoreOS 定制 dnsmasq 不读 /etc/hosts 之外的锚定，写 /etc/hosts 双保险
	if ! grep -q "$HOSTS_MARKER" /etc/hosts 2>/dev/null; then
		printf '\n%s\n' "$HOSTS_MARKER" >> /etc/hosts
	fi
	sed -i "/$HOSTS_MARKER/d" /etc/hosts
	printf '%s\n' "$HOSTS_MARKER" >> /etc/hosts
	printf '%s %s\n' "$LAN_IP" "$ADDR_HOSTS" >> /etc/hosts
}

setup() {
	write_captive_files
	reg_hosts
	reg_dnsmasq

	if [ -d /etc/nginx ]; then
		mkdir -p /etc/nginx/conf.d
		cat > "$CONF" <<EOF
# $MARKER
if (\$host = $HOST) { return 302 $PORTAL_URL; }
location = /generate_204 { return 302 $PORTAL_URL; }
location = /gen_204 { return 302 $PORTAL_URL; }
location = /hotspot-detect.html { return 302 $PORTAL_URL; }
location = /library/test/success.html { return 302 $PORTAL_URL; }
location = /connecttest.txt { return 302 $PORTAL_URL; }
location = /ncsi.txt { return 302 $PORTAL_URL; }
EOF
		/etc/init.d/nginx reload >/dev/null 2>&1 || true
	fi
}

stop() {
	rm -f "$CONF"
	rm -f "$TMP_DNS"
	sed -i "/$HOSTS_MARKER/d" /etc/hosts
	sed -i "/^$LAN_IP bind\.lan /d" /etc/hosts
	rm -rf "$WWW_DIR"
	for path in generate_204 gen_204 hotspot-detect.html connecttest.txt ncsi.txt redirect success.txt; do
		rm -f "/www/$path"
	done
	rm -f /www/library/test/success.html
	rmdir /www/library/test 2>/dev/null || true
	# 移除 UCI address 锚定
	uci -q show "dhcp.@dnsmasq[0].address" 2>/dev/null | sed -n "s/.*='\(\/\(bind\.lan\|captive\.apple\.com\|connectivitycheck\.gstatic\.com\|www\.msftconnecttest\.com\|detectportal\.firefox\.com\|nmcheck\.gnome\.org\)\/.*\)'/\1/p" | while read -r addr; do
		uci -q del_list "dhcp.@dnsmasq[0].address=$addr" 2>/dev/null || true
	done
	uci -q commit dhcp || true
	/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
	[ -d /etc/nginx ] && /etc/init.d/nginx reload >/dev/null 2>&1 || true
}

case "${1:-setup}" in setup) setup;; stop) stop;; *) exit 1;; esac
