#!/bin/sh

set -eu
CONFIG=passwall_device
TABLE=pwc_portal

setup() {
	iface="$(uci -q get $CONFIG.global.interface || echo br-lan)"
	rules="/tmp/passwall-device-nft.$$"
	cat > "$rules" <<EOF
table inet $TABLE {
	set allowed_macs { type ether_addr; flags interval; }
	set wireless_macs { type ether_addr; flags interval; }
	chain portal_nat {
		type nat hook prerouting priority dstnat - 5; policy accept;
		iifname "$iface" ether saddr @wireless_macs ether saddr != @allowed_macs tcp dport 80 redirect to :80
	}
	chain portal_forward {
		type filter hook forward priority filter - 5; policy accept;
		iifname "$iface" ether saddr @wireless_macs ether saddr @allowed_macs meta nfproto ipv6 counter drop
		iifname "$iface" ether saddr @wireless_macs ether saddr != @allowed_macs counter drop
	}
}
EOF
	if [ "${PWC_NFT_CHECK:-0}" = "1" ]; then nft -c -f "$rules"; rc=$?; rm -f "$rules"; return "$rc"; fi
	nft delete table inet "$TABLE" >/dev/null 2>&1 || true
	nft -f "$rules"
	rm -f "$rules"
	reload_set
}

reload_set() {
	nft list table inet "$TABLE" >/dev/null 2>&1 || return 0
	macs="/tmp/passwall-device-macs.$$"
	wifi_macs="/tmp/passwall-device-wifi-macs.$$"
	rules="/tmp/passwall-device-set.$$"
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
	{
		echo "flush set inet $TABLE allowed_macs"
		sort -u "$macs" | while read -r mac; do [ -n "$mac" ] && echo "add element inet $TABLE allowed_macs { $mac }"; done
		echo "flush set inet $TABLE wireless_macs"
		sort -u "$wifi_macs" | while read -r mac; do [ -n "$mac" ] && echo "add element inet $TABLE wireless_macs { $mac }"; done
	} > "$rules"
	nft -f "$rules"
	rm -f "$macs" "$wifi_macs" "$rules"
}

stop() { nft delete table inet "$TABLE" >/dev/null 2>&1 || true; }

case "${1:-setup}" in setup) setup;; reload) reload_set;; stop) stop;; *) exit 1;; esac
