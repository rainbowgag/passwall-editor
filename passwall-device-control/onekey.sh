#!/bin/sh
# PassWall 设备口令 - 一键安装/卸载脚本（兼容 busybox sh）
# 用法（交互菜单）:
#   curl -4 -fsSL <脚本URL> | sh
# 用法（直接指定）:
#   sh onekey.sh 1   # 安装/升级
#   sh onekey.sh 2   # 卸载

set -u

PKG="luci-app-passwall-device"
if [ -n "${PW_UPDATE_URLS:-}" ]; then
	UPDATE_SOURCES="$PW_UPDATE_URLS"
else
	UPDATE_SOURCES="https://raw.githubusercontent.com/rainbowgag/passwall-editor/main/passwall-device-control/update.json
http://m.yaml.uk:25532/update.json"
fi

say() { printf '%s\n' "$*"; }

fetch_manifest() {
	for u in $UPDATE_SOURCES; do
		curl -4 -fsSL --connect-timeout 5 --max-time 12 "$u" -o /tmp/pw-update.json 2>/dev/null && return 0
	done
	return 1
}

# busybox 环境没有 jq，用 sed 提取 JSON 首个字段
jget() {
	sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" /tmp/pw-update.json 2>/dev/null | head -n1
}

installed_version() {
	opkg list-installed 2>/dev/null | awk '/^luci-app-passwall-device /{print $3}'
}

# 版本比较：$1 >= $2（x.y.z 三段数字）
ver_ge() {
	a1="$(echo "$1" | cut -d. -f1)"; a2="$(echo "$1" | cut -d. -f2)"; a3="$(echo "$1" | cut -d. -f3)"
	b1="$(echo "$2" | cut -d. -f1)"; b2="$(echo "$2" | cut -d. -f2)"; b3="$(echo "$2" | cut -d. -f3)"
	[ "${a1:-0}" -gt "${b1:-0}" ] && return 0
	[ "${a1:-0}" -lt "${b1:-0}" ] && return 1
	[ "${a2:-0}" -gt "${b2:-0}" ] && return 0
	[ "${a2:-0}" -lt "${b2:-0}" ] && return 1
	[ "${a3:-0}" -ge "${b3:-0}" ] && return 0
	return 1
}

do_install() {
	say "==> 获取最新版本信息..."
	fetch_manifest || { say "获取更新信息失败，请检查路由器网络"; return 1; }
	VERSION="$(jget version)"
	IPK_URL="$(jget ipk_url)"
	SHA256="$(jget sha256)"
	[ -n "$VERSION" ] && [ -n "$IPK_URL" ] && [ -n "$SHA256" ] || { say "更新清单不完整"; return 1; }
	say "    最新版本: $VERSION"
	cur="$(installed_version)"
	if [ -n "$cur" ] && ver_ge "$cur" "$VERSION"; then
		say "当前已安装 $cur，不低于清单版本 $VERSION，无需重复安装"
		return 0
	fi
	say "==> 下载安装包..."
	curl -4 -fsSL --connect-timeout 8 --max-time 120 "$IPK_URL" -o /tmp/pw.ipk || { say "安装包下载失败"; return 1; }
	ACTUAL="$(sha256sum /tmp/pw.ipk 2>/dev/null | awk '{print $1}')"
	[ "$ACTUAL" = "$SHA256" ] || { say "SHA-256 校验失败，已拒绝安装"; rm -f /tmp/pw.ipk; return 1; }
	say "==> 安装 $PKG ..."
	opkg install /tmp/pw.ipk || { rm -f /tmp/pw.ipk; say "安装失败"; return 1; }
	rm -f /tmp/pw.ipk
	say "==> 启动服务..."
	{ [ ! -x /etc/init.d/passwall ] || /etc/init.d/passwall restart >/dev/null 2>&1; } || true
	/etc/init.d/passwall-device enable >/dev/null 2>&1 || true
	[ "$(uci -q get passwall_device.global.enabled)" != "1" ] || /etc/init.d/passwall-device restart >/dev/null 2>&1 || true
	say "完成。请进入 LuCI：服务 → PassWall 设备口令"
	say "安装后认证服务默认关闭，先导入节点并检查口令，再启用认证服务。"
}

do_uninstall() {
	say "==> 卸载 $PKG ..."
	opkg remove "$PKG"
	say "完成。已恢复 PassWall 原启用状态，相关节点/口令/绑定已清理。"
}

choice=""
[ $# -ge 1 ] && choice="$1"
if [ -z "$choice" ]; then
	say ""
	say "============ PassWall 设备口令 ============"
	cur="$(installed_version)"
	if [ -n "$cur" ]; then say "当前已安装版本: $cur"; else say "当前未安装"; fi
	say "  1) 安装 / 升级"
	say "  2) 卸载"
	say "============================================"
	printf "请输入 1 或 2 后回车: "
	read -r choice < /dev/tty 2>/dev/null || read -r choice || choice=""
fi

case "$choice" in
	1) do_install ;;
	2) do_uninstall ;;
	*) say "无效输入，请重新运行并输入 1 或 2"; exit 1 ;;
esac
