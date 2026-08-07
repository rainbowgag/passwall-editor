# M5 防火墙与强制门户

## 职责范围

网络层的强制认证与拦截：未绑定无线设备的流量拦截、HTTP 跳转到认证门户、IPv6 防泄漏、DNS 域名（`bind.lan`）解析、服务启停与守护。这是“能不能上网”的真正执行层。

## 涉及文件

- `root/usr/share/passwall-device/firewall.sh`（nftables / iptables 规则）
- `root/usr/share/passwall-device/guard.sh`（5 秒守护：离线清理 + 规则集同步）
- `root/usr/share/passwall-device/portal-setup.sh`（DNS hosts/dnsmasq + nginx 强制门户）
- `root/etc/init.d/passwall-device`（procd 启停与 reload 触发器）
- `deploy/nginx-passwall-editor.conf`（本机反向代理参考）
- 调用的 `app.lua`：`prune_offline`(671)、`wifi_mac_list`(186)、`migrate`/`cleanup-acls` 等

## 防火墙（`firewall.sh`）

自动检测 `nft` 优先，否则用 iptables/ipset（兼容衍生固件）。

- **nft 方案**：建 `inet pwc_portal` 表，含 `allowed_macs`（已绑定+白名单）与 `wireless_macs` 两个 set；`portal_nat` 链把未认证无线设备的 80 端口重定向到本机，`portal_forward` 链直接 drop 未认证流量。
- **iptables 方案**：ipset `pwc_allowed`/`pwc_wireless`，nat `REDIRECT` 到 80，FORWARD 丢弃；IPv6 用 `ip6tables` 丢弃未认证，**已绑定无线设备也丢弃 IPv6** 以强制走 IPv4 代理防泄漏。
- `collect_macs()` 汇总 `binding(mac,state=active)` + `admin_macs` + `wifi-macs`（由 `app.lua wifi-macs` 实时探测 hostapd 在线无线客户端）。
- `setup` 建规则，`reload` 仅刷 set 元素，`stop` 清空。

## 守护（`guard.sh`）

- 每 5 秒：若服务未启用则跳过。
- 调用 `app.lua prune-offline` 清理离线设备（受 `offline_unbind_seconds` 控制，`0`=永久保留）。
- 计算 `passwall_device` 配置 + 在线无线 MAC 的指纹，检测 PassWall 实际代理是否在跑，按状态/指纹变化触发 `firewall.sh reload`；未代理时额外 `flush allowed_macs`（此时拦截策略随之切换）。

## 强制门户（`portal-setup.sh`）

- 写 `/www` 下的探测页（`generate_204`、`hotspot-detect.html`、`connecttest.txt`、`ncsi.txt` 等）重定向到门户。
- 用 UCI `dhcp.@dnsmasq[0].address` + `/tmp/dnsmasq.d` 双保险把 `bind.lan` 解析到 LAN IP；并写 `/etc/hosts` 带 `# PWC_BIND_LAN` 标记。
- 有 nginx 时生成 `/etc/nginx/conf.d/passwall-device.locations` 做 302 跳转。
- `stop()` 反向清理全部。

## init.d（`root/etc/init.d/passwall-device`）

- `start`/`reload`：`enabled=1` 时跑 `portal-setup.sh setup` + `firewall.sh setup`，procd 拉起 `guard.sh`。
- `stop`：`firewall.sh stop` + `portal-setup.sh stop`。
- `service_triggers`：`passwall_device network dhcp` 变更触发 reload。

## 常见改动点

- 换拦截网桥接口（改 `global.interface` 或各脚本里的默认 `br-lan`）。
- 改“是否丢弃已绑定设备 IPv6”（`firewall.sh` 的 ip6tables 两条 FORWARD）。
- 加新的探测页域名/路径（`portal-setup.sh` 的列表）。
- 改守卫周期或指纹算法（`guard.sh`）。
- 兼容新的衍生固件防火墙（`use_nft` 判定逻辑）。

## 在新对话中的开场白

> 本项目是 OpenWrt PassWall 设备口令插件，先读 `docs/reference.md` 再读 `docs/module-05-firewall-portal.md`（M5 防火墙与强制门户）。我要改的需求是：<描述拦截/跳转/守护改动>。相关源码是 `firewall.sh`、`guard.sh`、`portal-setup.sh` 与 `init.d/passwall-device`。
