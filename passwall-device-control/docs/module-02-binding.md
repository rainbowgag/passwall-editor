# M2 设备绑定与认证

## 职责范围

设备在强制门户页输入口令后，把该设备（MAC）绑定到对应节点：创建 PassWall ACL、登记 DHCP 静态租约、踢出同口令旧设备，并刷新防火墙与 PassWall。同时负责认证服务的启用/停用开关。

## 涉及文件

- `app.lua`（绑定/解绑核心）
- `view/passwall_device/portal.htm`（设备认证页）
- `controller/passwall_device.lua` → `portal_login`、`api_toggle`
- `view/passwall_device/main.htm` → 服务状态与“启用/停用认证服务”按钮

## 核心函数（`app.lua` 行号）

| 函数 | 行号 | 作用 |
|------|------|------|
| `ip_to_mac` | 483 | 由客户端 IP 反查 MAC（ping + `ip neigh`） |
| `hostname_for` | 490 | 从 `/tmp/dhcp.leases` 取主机名 |
| `managed_acls_for_binding` | 499 | 找到该绑定名下的 PassWall ACL（含遗留 `PWC ` 标记） |
| `remove_binding` | 517 | 删 ACL、删 DHCP 租约、删绑定记录（解绑/踢出） |
| `ensure_dhcp` | 555 | 复用系统已有租约或新建静态租约 |
| `rate_state` | 744 | 绑定限速/限流状态（`/tmp/passwall-device-rate-*`） |
| `bind` | 754 | 主流程：校验口令→查 MAC→踢旧设备→建绑定+ACL→应用并回滚 |
| `toggle` | 830 | 开/关认证服务，重启/停止 init 服务 |

## 绑定主流程（`bind`）

1. 校验口令格式与长度；查找口令对应 `code` section。
2. `ip_to_mac` 反查 MAC；识别不到则报错（提示关闭随机 MAC）。
3. 若该 MAC 已有绑定或口令已被占用 → `remove_binding` 踢出旧设备。
4. 新建 `binding`（`state=pending`）+ PassWall ACL（`remarks`=`PWC <hostname> <mac>`，`tcp_node` 指向节点，`use_block_list=1`）。
5. 强制 `passwall.@global[0].enabled=1`、`acl_enable=1`、`client_proxy=0`（未绑定的有线设备保持直连）。
6. `ensure_dhcp` 登记静态租约，commit 后 `dnsmasq reload`、`firewall.sh reload`、`passwall restart`。
7. 若 passwall 应用失败 → 回滚（删绑定+ACL），设备保持断网并返回错误。
8. 成功后置 `state=active`，清除限速状态。

## 认证门户

- 入口域名 `bind.lan`（备用 `http://路由器IP/cgi-bin/luci/pwc`）。
- `portal.htm` POST 到 `/pwc/login`，用 `REMOTE_ADDR` 作为 ip，`code` 作为口令。
- 跳转成功后会重定向到 `http://connectivitycheck.gstatic.com/generate_204` 让系统检测网络已通。

## 常见改动点

- 改认证成功后的跳转/检测页。
- 改绑定触发的 ACL 默认参数（`tcp_proxy_mode`、`filter_proxy_ipv6`、`use_block_list` 等，见 `bind` 内 `c:set(PW, acl, ...)` 段）。
- 改“同一口令是否允许踢旧设备”或“是否允许一设备绑定多口令”。
- 改认证页文案/样式（`portal.htm`）。

## 在新对话中的开场白

> 本项目是 OpenWrt PassWall 设备口令插件，先读 `docs/reference.md` 再读 `docs/module-02-binding.md`（M2 设备绑定与认证）。我要改的需求是：<描述绑定/认证相关改动>。相关源码是 `app.lua` 的 `bind`/`remove_binding`/`ensure_dhcp`/`toggle`，以及 `portal.htm`。
