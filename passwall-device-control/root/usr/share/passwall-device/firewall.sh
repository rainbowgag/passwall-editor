#!/bin/sh

set -eu
CONFIG=passwall_device
TABLE=pwc_portal

use_nft() {
	command -v nft >/dev/null 2>&1 || return 1
	[ -x /etc/init.d/fw4 ] && return 0
	nft list tables 2>/dev/null | grep -q "inet fw4" && return 0
	return 1
}

collect_macs() {
	macs="/tmp/passwall-device-macs.$$"
	wifi_macs="/tmp/passwall-device-wifi-macs.$$"
	: > "$macs"
	: > "$wifi_macs"
	for section in $(uci -q show "$CONFIG" | sed -n "s/^$CONFIG\.\([^.=]*\)=binding$/\1/p"); do
		mac="$(uci -q get "$CONFIG.$section.mac" || true)"
		state="$(uci -q get "$CONFIG.$section.state" || true)"
		[ "$state" = active ] && echo "$mac" | grep -Eq '^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$' && echo "$mac" >> "$macs" || true
	done
	uci -q get "$CONFIG.global.admin_macs" 2>/dev/null | tr ' ' '\n' | while read -r mac; do
		echo "$mac" | grep -Eq '^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$' && echo "$mac" >> "$macs" || true
	done
	/usr/share/passwall-device/app.lua wifi-macs 2>/dev/null | jsonfilter -e '@.macs[*]' 2>/dev/null | while read -r mac; do
		echo "$mac" | grep -Eq '^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$' && echo "$mac" >> "$wifi_macs" || true
	done
}

nft_setup() {
	iface="$(uci -q get $CONFIG.global.interface || echo br-lan)"
	rules="/tmp/passwall-device-nft.$$"
	cat > "$rules" <<EOF
table inet $TABLE {
	set allowed_macs { type ether_addr; flags interval; }
	set wireless_macs { type ether_addr; flags interval; }
	chain portal_nat {
		type nat hook prerouting priority dstnat; policy accept;
		iifname "$iface" ether saddr @wireless_macs ether saddr != @allowed_macs tcp dport 80 redirect to :80
	}
	chain portal_forward {
		type filter hook forward priority filter; policy accept;
		iifname "$iface" ether saddr @wireless_macs ether saddr != @allowed_macs counter drop
	}
}
EOF
	nft delete table inet "$TABLE" >/dev/null 2>&1 || true
	nft -f "$rules"
	rm -f "$rules"
	nft_reload_set
}

nft_reload_set() {
	nft list table inet "$TABLE" >/dev/null 2>&1 || return 0
	collect_macs
	rules="/tmp/passwall-device-set.$$"
	{
		echo "flush set inet $TABLE allowed_macs"
		sort -u "$macs" | while read -r mac; do [ -n "$mac" ] && echo "add element inet $TABLE allowed_macs { $mac }"; done
		echo "flush set inet $TABLE wireless_macs"
		sort -u "$wifi_macs" | while read -r mac; do [ -n "$mac" ] && echo "add element inet $TABLE wireless_macs { $mac }"; done
	} > "$rules"
	nft -f "$rules"
	rm -f "$macs" "$wifi_macs" "$rules"
}

nft_stop() {
	nft delete table inet "$TABLE" >/dev/null 2>&1 || true
}

ipt_setup() {
	iface="$(uci -q get $CONFIG.global.interface || echo br-lan)"
	ipt_stop
	ipset create pwc_allowed hash:mac 2>/dev/null || ipset flush pwc_allowed
	ipset create pwc_wireless hash:mac 2>/dev/null || ipset flush pwc_wireless
	# 未绑定无线设备：HTTP 重定向到路由器门户，其余流量在 FORWARD 丢弃
	iptables -t nat -I PREROUTING 1 -i "$iface" -m set --match-set pwc_wireless src \
		-m set ! --match-set pwc_allowed src -p tcp --dport 80 -j REDIRECT --to-ports 80
	iptables -I FORWARD 1 -i "$iface" -m set --match-set pwc_wireless src \
		-m set ! --match-set pwc_allowed src -j DROP
	# IPv6：未绑定无线设备直接拦截，避免手机走 IPv6 绕过门户
	if command -v ip6tables >/dev/null 2>&1; then
		ip6tables -I FORWARD 1 -i "$iface" -m set --match-set pwc_wireless src \
			-m set ! --match-set pwc_allowed src -j DROP
		# 已绑定设备同样丢弃 IPv6，强制走 IPv4 代理，避免 IPv6 直连被墙/绕代理
		ip6tables -I FORWARD 2 -i "$iface" -m set --match-set pwc_wireless src \
			-m set --match-set pwc_allowed src -j DROP
	fi
	ipt_reload_set
}

ipt_reload_set() {
	ipset list pwc_allowed >/dev/null 2>&1 || return 0
	collect_macs
	ipset flush pwc_allowed
	ipset flush pwc_wireless
	sort -u "$macs" | while read -r mac; do [ -n "$mac" ] && ipset add pwc_allowed "$mac" 2>/dev/null || true; done
	sort -u "$wifi_macs" | while read -r mac; do [ -n "$mac" ] && ipset add pwc_wireless "$mac" 2>/dev/null || true; done
	rm -f "$macs" "$wifi_macs"
}

ipt_stop() {
	iptables -t nat -D PREROUTING -i "$(uci -q get $CONFIG.global.interface || echo br-lan)" \
		-m set --match-set pwc_wireless src -m set ! --match-set pwc_allowed src \
		-p tcp --dport 80 -j REDIRECT --to-ports 80 2>/dev/null || true
	iptables -D FORWARD -i "$(uci -q get $CONFIG.global.interface || echo br-lan)" \
		-m set --match-set pwc_wireless src -m set ! --match-set pwc_allowed src -j DROP 2>/dev/null || true
	if command -v ip6tables >/dev/null 2>&1; then
		ip6tables -D FORWARD -i "$(uci -q get $CONFIG.global.interface || echo br-lan)" \
			-m set --match-set pwc_wireless src -m set ! --match-set pwc_allowed src -j DROP 2>/dev/null || true
		ip6tables -D FORWARD -i "$(uci -q get $CONFIG.global.interface || echo br-lan)" \
			-m set --match-set pwc_wireless src -m set --match-set pwc_allowed src -j DROP 2>/dev/null || true
	fi
	ipset destroy pwc_allowed 2>/dev/null || true
	ipset destroy pwc_wireless 2>/dev/null || true
}

case "${1:-setup}" in
	setup)
		if use_nft; then nft_setup; else ipt_setup; fi
		;;
	reload)
		if use_nft; then nft_reload_set; else ipt_reload_set; fi
		;;
	stop)
		if use_nft; then nft_stop; else ipt_stop; fi
		;;
	*)
		exit 1
		;;
esac
