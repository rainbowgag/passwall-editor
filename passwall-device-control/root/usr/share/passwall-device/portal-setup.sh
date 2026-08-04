#!/bin/sh

set -eu
MARKER=PWC_BIND_LAN
HOST=bind.lan
LAN_IP="$(uci -q get network.lan.ipaddr || echo 10.0.0.1)"
LAN_IP="${LAN_IP%%/*}"
CONF=/etc/nginx/conf.d/passwall-device.locations
DNS=/etc/dnsmasq.d/passwall-device.conf

setup() {
	mkdir -p /etc/nginx/conf.d /etc/dnsmasq.d
	printf 'address=/%s/%s\n' "$HOST" "$LAN_IP" > "$DNS"
	cat > "$CONF" <<EOF
# $MARKER
if (\$host = $HOST) { return 302 http://$LAN_IP/cgi-bin/luci/pwc; }
location = /generate_204 { return 302 http://$LAN_IP/cgi-bin/luci/pwc; }
location = /gen_204 { return 302 http://$LAN_IP/cgi-bin/luci/pwc; }
location = /hotspot-detect.html { return 302 http://$LAN_IP/cgi-bin/luci/pwc; }
location = /library/test/success.html { return 302 http://$LAN_IP/cgi-bin/luci/pwc; }
location = /connecttest.txt { return 302 http://$LAN_IP/cgi-bin/luci/pwc; }
location = /ncsi.txt { return 302 http://$LAN_IP/cgi-bin/luci/pwc; }
EOF
	/etc/init.d/dnsmasq reload >/dev/null 2>&1 || true
	/etc/init.d/nginx reload >/dev/null 2>&1 || true
}

stop() {
	rm -f "$CONF" "$DNS"
	/etc/init.d/dnsmasq reload >/dev/null 2>&1 || true
	/etc/init.d/nginx reload >/dev/null 2>&1 || true
}

case "${1:-setup}" in setup) setup;; stop) stop;; *) exit 1;; esac
