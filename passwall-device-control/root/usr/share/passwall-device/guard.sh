#!/bin/sh

last_state=""
last_fingerprint=""

while sleep 5; do
	[ "$(uci -q get passwall_device.global.enabled)" = "1" ] || continue
	/usr/share/passwall-device/app.lua prune-offline >/tmp/pwc-prune.log 2>&1 || true
	fingerprint="$({
		uci -q show passwall_device | grep -E '\.(mac|state|admin_macs)='
		/usr/share/passwall-device/app.lua wifi-macs 2>/dev/null | jsonfilter -e '@.macs[*]' 2>/dev/null
	} | sort | md5sum | cut -d ' ' -f 1)"
	if [ "$(uci -q get passwall.@global[0].enabled)" = "1" ] && \
	   [ "$(uci -q get passwall.@global[0].acl_enable)" = "1" ] && \
	   ps w | grep -Eq '[/](xray|sing-box).*[/]tmp/etc/passwall/acl/' && \
	   find /tmp/etc/passwall/acl -type f -name source_list -size +0c 2>/dev/null | grep -q .; then
		if [ "$last_state" != up ] || [ "$last_fingerprint" != "$fingerprint" ]; then
			/usr/share/passwall-device/firewall.sh reload >/dev/null 2>&1 || true
		fi
		last_state=up
		last_fingerprint="$fingerprint"
	else
		if [ "$last_state" != down ] || [ "$last_fingerprint" != "$fingerprint" ]; then
			/usr/share/passwall-device/firewall.sh reload >/dev/null 2>&1 || true
			nft flush set inet pwc_portal allowed_macs >/dev/null 2>&1 || true
		fi
		last_state=down
		last_fingerprint="$fingerprint"
	fi
done
