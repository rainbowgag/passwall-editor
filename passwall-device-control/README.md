# PassWall 设备口令

面向大量 Wi-Fi 终端的 PassWall 批量节点与设备绑定插件。每个口令对应一个代理节点；同一口令可供多台设备同时使用，每台设备拥有独立 ACL 并走同一个代理出口。

## 首版功能

- 混杂文本批量提取 VMess、VLESS、SOCKS/SOCKS5 节点。
- 支持 `IP:端口:用户名:密码` 和 `IP:端口` SOCKS 简写。
- 使用 PassWall 官方订阅解析器写入节点，降低协议兼容风险。
- 批量命名、连续口令、节点与设备列表。
- 同一节点与口令支持多设备共享、主动换绑、解绑断网、删除节点时批量迁移。
- 无线设备持续离线 60 秒后自动解绑该设备，不影响使用相同口令的其他设备。
- 点击节点名称或口令即可修改，并检查名称/口令重复；设备名称支持自定义备注。
- 节点和设备列表支持复选、全选、批量删除或批量解绑。
- 页面显示当前与最新版本；发现新版本后可点击更新，安装前会校验 SHA-256。
- 已连接设备使用绿色状态文字显示，离线等待解绑使用红色提示。
- 默认 Wi-Fi Captive Portal，手动入口 `http://bind.lan`（备用入口 `http://路由器IP/cgi-bin/luci/pwc`）。
- nftables 未认证阻断和 IPv6 防泄漏。
- 安装前备份、卸载恢复 PassWall 原启用状态。

## 安装

将整个目录上传到 OpenWrt 后执行：

```sh
chmod +x install.sh
./install.sh
```

或者直接安装已构建的包：

```sh
opkg install luci-app-passwall-device_0.3.0_all.ipk
```

安装后认证服务保持关闭。先进入“服务 → PassWall 设备口令”导入并检查节点，再启用认证服务。

GitHub 一键安装或升级：

```sh
curl -4 -fL --retry 2 --connect-timeout 15 -o /tmp/passwall-device.ipk https://raw.githubusercontent.com/rainbowgag/passwall-editor/main/passwall-device-control/dist/luci-app-passwall-device_0.3.0_all.ipk && [ "$(sha256sum /tmp/passwall-device.ipk | awk '{print $1}')" = "8b3d0fecbb2209b90880a67b200572999b27b769fea88f8b80ab6781c6540923" ] && opkg install /tmp/passwall-device.ipk && /etc/init.d/passwall restart && /etc/init.d/passwall-device restart
```

VPS 一键安装或升级：

```sh
wget -O /tmp/passwall-device.ipk http://m.yaml.uk:25532/luci-app-passwall-device_0.3.0_all.ipk && [ "$(sha256sum /tmp/passwall-device.ipk | awk '{print $1}')" = "8b3d0fecbb2209b90880a67b200572999b27b769fea88f8b80ab6781c6540923" ] && opkg install /tmp/passwall-device.ipk && /etc/init.d/passwall restart && /etc/init.d/passwall-device restart
```

在 OpenWrt/Linux 环境构建该固件兼容的 IPK：

```sh
chmod +x build-openwrt.sh
./build-openwrt.sh
```

## 安全提醒

启用认证服务后，所有尚未绑定且未加入管理员白名单的 LAN/Wi-Fi 设备都会被阻断外网。管理后台仍可通过路由器 LAN 地址访问。
