# M7 打包、安装与卸载

## 职责范围

把 `root/` 目录打包成 OpenWrt ipk；提供直接目录安装/卸载脚本；opkg 的 postinst/prerm 控制脚本；安装/卸载时的 PassWall 状态备份与恢复、以及历史数据迁移清理。

## 涉及文件

- `build-openwrt.sh`（构建 ipk）
- `install.sh` / `uninstall.sh`（直接目录安装/卸载）
- `package/CONTROL/control`（ipk 元信息/依赖）
- `package/CONTROL/postinst`（安装后处理）
- `package/CONTROL/prerm`（卸载前处理）
- `app.lua`：`migrate_codes`(584)、`migrate_acls`(629)、`cleanup_acls`(718)
- `VERSION`（构建读版本号）

## 构建（`build-openwrt.sh`）

1. 读 `VERSION`，输出 `dist/luci-app-passwall-device_<VERSION>_all.ipk`。
2. 把 `package/CONTROL/` 打包成 `control.tar.gz`，`root/` 打包成 `data.tar.gz`，配合 `debian-binary`(2.0) 打成一个 ipk。
3. 关键处理：`data/etc/config/passwall_device` 复制为 `data/usr/share/passwall-device/default-config`（作为全新安装默认配置），原配置文件不进 data。
4. 统一修正各文件权限位。

## 安装（`install.sh` 与 `postinst`）

两者思路一致：

- 校验 root、存在 `/etc/config/passwall`、有 nft。
- 备份 `/etc/config/{passwall,dhcp,passwall_device}` 到 `/root/passwall-device-backup-<stamp>`。
- 记录 PassWall 安装前的 `enabled`/`acl_enable` 到 `passwall_device.global.previous_*`。
- 拷贝 `root/`；保留已有 `passwall_device` 配置（install.sh 用临时文件回拷）。
- 运行 `app.lua migrate` 做历史数据迁移。
- `enable` 服务、清 LuCI 缓存、重启 rpcd/nginx。

## 卸载（`uninstall.sh` 与 `prerm`）

- 先备份，再停用并 disable 服务。
- 删除本插件创建的所有 `passwall.acl_rule`、`passwall.nodes`（通过 `passwall_device` 的 node/binding 索引）、`dhcp.pwc_*` 租约。
- 用 `previous_passwall_enabled`/`previous_acl_enable` **恢复 PassWall 原启用状态**。
- `prerm` 还会先跑 `app.lua cleanup-acls` 清理遗留 ACL，再删配置与文件；非 `upgrade` 时才执行。
- 清理 LuCI 缓存并重启 passwall/dnsmasq/nginx。

## 迁移与清理（`app.lua`）

- `migrate_codes`(584)：历史口令结构迁移。
- `migrate_acls`(629)：把旧 ACL 迁移到新绑定结构（安装时调用）。
- `cleanup_acls`(718)：删除不再被引用的托管 ACL（卸载时调用）。

## 常见改动点

- 加/改 ipk 依赖（`package/CONTROL/control` 的 `Depends`）。
- 改备份路径或备份内容（`install.sh`/`uninstall.sh`）。
- 改权限位（三个地方都改：build、install、postinst）。
- 改卸载时对 PassWall 的恢复策略。

## 在新对话中的开场白

> 本项目是 OpenWrt PassWall 设备口令插件，先读 `docs/reference.md` 再读 `docs/module-07-packaging.md`（M7 打包、安装与卸载）。我要改的需求是：<描述打包/安装/卸载改动>。相关源码是 `build-openwrt.sh`、`install.sh`、`uninstall.sh`、`package/CONTROL/{control,postinst,prerm}`。
