# PassWall 设备口令

面向大量 Wi-Fi 终端的 PassWall 批量节点与设备绑定插件。一个代理节点可创建多个口令，每个口令同时只允许一台设备使用；新设备输入同一口令时会自动替换旧设备。

## 功能

- 混杂文本批量提取 VMess、VLESS、Trojan、Trojan-Go、Shadowsocks、SOCKS/SOCKS5 节点。
- Trojan-Go 链接保留 TLS、WebSocket、Host 与路径参数，并自动使用 sing-box 核心。
- 标准 Trojan 链接自动使用 sing-box；Shadowsocks 支持 SIP002 与旧式 Base64 链接并交由 PassWall 官方解析器导入。
- 支持 `IP:端口:用户名:密码` 和 `IP:端口` SOCKS 简写。
- 支持 `socks://Base64(用户名:密码)@域名:端口#备注`，导入后自动使用 sing-box 提高固件兼容性。
- 自动复用系统已有的 DHCP 静态租约，避免重复 IP 条目导致 dnsmasq 崩溃和全网 DNS 中断。
- 仅无线设备进入口令认证与代理规则；未绑定的有线电脑默认直连，不受代理节点失效影响。
- 使用 PassWall 官方订阅解析器写入节点，降低协议兼容风险。
- 批量命名、连续口令，并可设置每个导入节点生成的口令数量。
- 一个节点可拥有多个独立口令；每个口令绑定一台设备，新设备使用相同口令时自动踢出旧设备。
- 选择一个或多个现有节点批量追加口令，编号从当前序号继续递增。
- 设备离线或关机时永久保留绑定，仅在同口令被其他设备使用或管理员手动解绑时释放。
- 点击节点名称或口令即可修改，并检查名称/口令重复；设备名称支持自定义备注。
- 节点和设备列表支持复选、全选、批量删除或批量解绑。
- 节点列表支持按节点名称或口令搜索；设备列表支持按口令、节点、设备名称、MAC 或 IP 搜索。
- 页面显示当前与最新版本；发现新版本后可点击更新，安装前会校验 SHA-256。
- 一键恢复初始配置：点击并确认后清空所有节点、口令、设备绑定和相关规则，停用认证服务，方便重新配置。
- 版本回退：更新清单携带最近 5 个历史版本，页面可选择任意历史版本一键回退，安装前同样校验 SHA-256。
- 已连接设备使用绿色状态文字显示，离线但保留绑定使用红色提示。
- 默认 Wi-Fi Captive Portal，手动入口 `http://bind.lan`（备用入口 `http://路由器IP/cgi-bin/luci/pwc`）。
- nftables 未认证阻断和 IPv6 防泄漏。
- 兼容使用内置 firewall4/nftables 但软件包名称不同的 OpenWrt 衍生固件。
- 安装前备份、卸载恢复 PassWall 原启用状态。

## 安装

### 一键安装 / 卸载（推荐）

执行后按提示输入 `1` 安装 / 升级、`2` 卸载：

```sh
curl -4 -fsSL http://m.yaml.uk:25532/onekey.sh | sh
```

也可以带参数直接执行，跳过菜单：

```sh
# 安装 / 升级
curl -4 -fsSL http://m.yaml.uk:25532/onekey.sh | sh -s 1

# 卸载（恢复 PassWall 原启用状态，清理节点/口令/绑定）
curl -4 -fsSL http://m.yaml.uk:25532/onekey.sh | sh -s 2
```

GitHub 来源（仓库推送后可用）：

```sh
curl -4 -fsSL https://raw.githubusercontent.com/rainbowgag/passwall-editor/main/passwall-device-control/onekey.sh | sh
```

> 脚本会自动获取最新版本、校验 SHA-256 后安装；已安装版本不低于最新版本时会跳过。国内网络下 GitHub 可能不可达，建议优先使用 VPS 来源（需先把 `onekey.sh` 上传到 VPS 根目录）。

将整个目录上传到 OpenWrt 后执行：

```sh
chmod +x install.sh
./install.sh
```

或者直接安装已构建的包：

```sh
opkg install luci-app-passwall-device_0.6.0_all.ipk
```

安装后认证服务保持关闭。先进入“服务 → PassWall 设备口令”导入并检查节点，再启用认证服务。

GitHub 一键安装或升级：

```sh
{ [ -x /usr/bin/sing-box ] || { opkg update && opkg install sing-box; }; } && curl -4 -fL --retry 2 --connect-timeout 15 -o /tmp/passwall-device.ipk https://raw.githubusercontent.com/rainbowgag/passwall-editor/main/passwall-device-control/dist/luci-app-passwall-device_0.6.0_all.ipk && [ "$(sha256sum /tmp/passwall-device.ipk | awk '{print $1}')" = "a69f414559a029d09541bc74763fc03dea369bf359a7bb17f6b7ced2da06e493" ] && opkg install /tmp/passwall-device.ipk && { [ ! -x /etc/init.d/passwall ] || /etc/init.d/passwall restart; } && /etc/init.d/passwall-device enable && { [ "$(uci -q get passwall_device.global.enabled)" != "1" ] || /etc/init.d/passwall-device restart; }
```

VPS 一键安装或升级：

```sh
{ [ -x /usr/bin/sing-box ] || { opkg update && opkg install sing-box; }; } && wget -O /tmp/passwall-device.ipk http://m.yaml.uk:25532/luci-app-passwall-device_0.6.0_all.ipk && [ "$(sha256sum /tmp/passwall-device.ipk | awk '{print $1}')" = "a69f414559a029d09541bc74763fc03dea369bf359a7bb17f6b7ced2da06e493" ] && opkg install /tmp/passwall-device.ipk && { [ ! -x /etc/init.d/passwall ] || /etc/init.d/passwall restart; } && /etc/init.d/passwall-device enable && { [ "$(uci -q get passwall_device.global.enabled)" != "1" ] || /etc/init.d/passwall-device restart; }
```

### 历史版本一键安装（最近 5 个版本）

测试新版本后如需回退，或需要在多台设备上安装特定版本，可直接使用对应版本的一键命令（安装前均校验 SHA-256）。页面内“检查更新 → 回退到该版本”也可以直接回退到清单中携带的历史版本。

#### 0.6.0（当前）

```sh
{ [ -x /usr/bin/sing-box ] || { opkg update && opkg install sing-box; }; } && curl -4 -fL --retry 2 --connect-timeout 15 -o /tmp/passwall-device.ipk https://raw.githubusercontent.com/rainbowgag/passwall-editor/main/passwall-device-control/dist/luci-app-passwall-device_0.6.0_all.ipk && [ "$(sha256sum /tmp/passwall-device.ipk | awk '{print $1}')" = "a69f414559a029d09541bc74763fc03dea369bf359a7bb17f6b7ced2da06e493" ] && opkg install /tmp/passwall-device.ipk && { [ ! -x /etc/init.d/passwall ] || /etc/init.d/passwall restart; } && /etc/init.d/passwall-device enable && { [ "$(uci -q get passwall_device.global.enabled)" != "1" ] || /etc/init.d/passwall-device restart; }
```

#### 0.5.0

```sh
{ [ -x /usr/bin/sing-box ] || { opkg update && opkg install sing-box; }; } && curl -4 -fL --retry 2 --connect-timeout 15 -o /tmp/passwall-device.ipk https://raw.githubusercontent.com/rainbowgag/passwall-editor/main/passwall-device-control/dist/luci-app-passwall-device_0.5.0_all.ipk && [ "$(sha256sum /tmp/passwall-device.ipk | awk '{print $1}')" = "ace590593901470ffe0c221a97c2de95a678b71bc748502d29c84ba2e295b9b8" ] && opkg install /tmp/passwall-device.ipk && { [ ! -x /etc/init.d/passwall ] || /etc/init.d/passwall restart; } && /etc/init.d/passwall-device enable && { [ "$(uci -q get passwall_device.global.enabled)" != "1" ] || /etc/init.d/passwall-device restart; }
```

#### 0.4.9

```sh
{ [ -x /usr/bin/sing-box ] || { opkg update && opkg install sing-box; }; } && curl -4 -fL --retry 2 --connect-timeout 15 -o /tmp/passwall-device.ipk https://raw.githubusercontent.com/rainbowgag/passwall-editor/main/passwall-device-control/dist/luci-app-passwall-device_0.4.9_all.ipk && [ "$(sha256sum /tmp/passwall-device.ipk | awk '{print $1}')" = "b8387ef9703cb534ce3ff7503d5da396947b50d1213f167c46d3731d6b904d35" ] && opkg install /tmp/passwall-device.ipk && { [ ! -x /etc/init.d/passwall ] || /etc/init.d/passwall restart; } && /etc/init.d/passwall-device enable && { [ "$(uci -q get passwall_device.global.enabled)" != "1" ] || /etc/init.d/passwall-device restart; }
```

#### 0.4.8

```sh
{ [ -x /usr/bin/sing-box ] || { opkg update && opkg install sing-box; }; } && curl -4 -fL --retry 2 --connect-timeout 15 -o /tmp/passwall-device.ipk https://raw.githubusercontent.com/rainbowgag/passwall-editor/main/passwall-device-control/dist/luci-app-passwall-device_0.4.8_all.ipk && [ "$(sha256sum /tmp/passwall-device.ipk | awk '{print $1}')" = "534bf233a5531d01e5eec87a132e79e2406dd0ef9b61d713a17e3b3972b8f81c" ] && opkg install /tmp/passwall-device.ipk && { [ ! -x /etc/init.d/passwall ] || /etc/init.d/passwall restart; } && /etc/init.d/passwall-device enable && { [ "$(uci -q get passwall_device.global.enabled)" != "1" ] || /etc/init.d/passwall-device restart; }
```

#### 0.4.7

```sh
{ [ -x /usr/bin/sing-box ] || { opkg update && opkg install sing-box; }; } && curl -4 -fL --retry 2 --connect-timeout 15 -o /tmp/passwall-device.ipk https://raw.githubusercontent.com/rainbowgag/passwall-editor/main/passwall-device-control/dist/luci-app-passwall-device_0.4.7_all.ipk && [ "$(sha256sum /tmp/passwall-device.ipk | awk '{print $1}')" = "71a7ae28579ad23416a67860d33c521b6b43e00886c8228a810f4177f4ef7154" ] && opkg install /tmp/passwall-device.ipk && { [ ! -x /etc/init.d/passwall ] || /etc/init.d/passwall restart; } && /etc/init.d/passwall-device enable && { [ "$(uci -q get passwall_device.global.enabled)" != "1" ] || /etc/init.d/passwall-device restart; }
```

> 发布新版本时，请把 `dist/` 下新版本 IPK 与 `update.json` 同步上传到 VPS（`m.yaml.uk:25532`），保持 IPK 文件名与 SHA-256 一致。VPS 当前的 0.4.9 为旧构建（哈希不同），0.5.0/0.6.0 尚未上传，上传后 VPS 一键命令同样可用。

在 OpenWrt/Linux 环境构建该固件兼容的 IPK：

```sh
chmod +x build-openwrt.sh
./build-openwrt.sh
```

## 安全提醒

启用认证服务后，所有尚未绑定且未加入管理员白名单的 LAN/Wi-Fi 设备都会被阻断外网。管理后台仍可通过路由器 LAN 地址访问。
