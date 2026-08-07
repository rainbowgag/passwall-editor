# 共享参考：数据模型与接口

这份文档记录各模块都依赖的**数据结构、命令行接口和 HTTP 路由**。改动任何模块前先对照这里，避免破坏其它模块的约定。

## UCI 配置：`passwall_device`

配置文件 `root/etc/config/passwall_device`，类型为 `config` 的 section 由安装/迁移逻辑管理。

### `global`（全局开关）

| 键 | 默认 | 说明 |
|----|------|------|
| `enabled` | `0` | 认证服务总开关（`1` 启用） |
| `interface` | `br-lan` | 门户/拦截作用的网桥接口 |
| `portal_host` | `bind.lan` | 认证入口域名 |
| `code_start` / `code_width` / `code_prefix` | `1`/`3`/`''` | 自动口令起始编号、位数、前缀 |
| `next_code_number` | — | 自动口令编号游标（`create_codes` 更新） |
| `health_interval` | `30` | 健康检查间隔（当前未在 guard 中强用） |
| `offline_unbind_seconds` | `0` | 离线自动解绑秒数（`0`=永久保留，`prune_offline` 使用） |
| `previous_passwall_enabled` / `previous_acl_enable` | — | 安装前 PassWall 状态快照，卸载时恢复 |
| `admin_macs` | — | 管理员白名单 MAC（绕过认证） |

### `node`（本插件托管节点的元信息）

每个托管 PassWall 节点对应一条。键：`passwall_id`（对应 `passwall.nodes` 的 section 名）、`remarks`、`created_at`、健康测试记录 `last_test_at`/`last_reachable`/`last_exit_ip`/`last_test_message`。

### `code`（口令）

键：`node_id`（所属 PassWall 节点）、`value`（口令文本）、`created_at`。同一节点可多条。

### `binding`（设备绑定）

键：`mac`、`ip`、`hostname`（系统名）、`remark`（自定义备注，可空）、`node_id`、`code_id`、`code`（冗余口令）、`acl_id`（PassWall ACL section 名）、`state`（`pending`/`active`）、`wireless`、`bound_at`。

### `passwall` 侧的托管数据

- `passwall.nodes`：由导入写入的真实节点；本插件以 `passwall_id` 关联。
- `passwall.acl_rule`：每条绑定生成一条 ACL，`remarks` 前缀 `PWC `，含 `pwc_managed`/`pwc_binding_id` 标记。
- `dhcp`：每个绑定 MAC 生成静态租约 `dhcp.pwc_<mac>`（复用已有租约，避免 dnsmasq 崩溃）。

## `app.lua` 命令行动作（IPC）

`lua /usr/share/passwall-device/app.lua <action> [arg...]`，输出一行 JSON。完整动作见文件末尾分发块（约 `app.lua:1131`）。

| 动作 | 参数 | 主要函数 | 归属模块 |
|------|------|----------|----------|
| `status` | — | `list_status` | M3 |
| `extract` | 临时文件 | `extract_links` | M1 |
| `import` | path,prefix,start,code_prefix,code_start,code_width,code_count | `import_nodes` | M1 |
| `bind` | ip,code | `bind` | M2 |
| `toggle` | 0/1 | `toggle` | M2 |
| `wifi-macs` | — | `wifi_mac_list` | M2/M5 |
| `update-node` / `update-code` / `update-binding` | id,value | 对应 update_* | M3 |
| `add-codes` | id_text,count | `add_codes` | M3/M1 |
| `delete-codes` | id_text | `delete_codes` | M3 |
| `delete-node(s)` | id_text,replacement | `delete_nodes` | M3 |
| `unbind(-many)` | id_text | `unbind_many` | M3 |
| `test-node` | node_id | `test_node` | M4 |
| `check-update` / `install-update` | — | 对应函数 | M6 |
| `migrate` | — | `migrate_acls` | M7 |
| `prune-offline` | — | `prune_offline` | M5 |
| `cleanup-acls` | — | `cleanup_acls` | M7 |

## 控制器 HTTP 路由（LuCI）

`controller/passwall_device.lua` 定义单级 API 入口（`entry({...}).leaf=true`），避免 iStoreOS 的 “Access Violation”。主页面基址：`/admin/services/passwall_device`。

| 路由 | 参数（formvalue） | 转发动作 |
|------|------------------|----------|
| `GET  status` | — | `status` |
| `POST import` | links,prefix,start,code_prefix,code_start,code_width,code_count | `import` |
| `POST toggle` | enabled | `toggle` |
| `POST delete` | node_id,replacement | `delete-node` |
| `POST delete-many` | node_ids,replacement | `delete-nodes` |
| `POST unbind` | binding_id | `unbind` |
| `POST unbind-many` | binding_ids | `unbind-many` |
| `POST test` | node_id | `test-node` |
| `POST edit` | node_id,remarks | `update-node` |
| `POST edit-code` | code_id,value | `update-code` |
| `POST add-codes` | node_ids,count | `add-codes` |
| `POST delete-codes` | code_ids | `delete-codes` |
| `POST edit-binding` | binding_id,remark | `update-binding` |
| `GET  version` | — | `check-update` |
| `POST update` | — | `install-update` |

门户入口（免登录，`portal.sysauth=false`）：
- `GET  /pwc` → 渲染 `portal.htm`
- `POST /pwc/login`，参数 `code` → `bind`（`REMOTE_ADDR` 作为 ip）

## 全项目文件清单

| 路径 | 归属 | 职责 |
|------|------|------|
| `app.lua` | M1-M4/M6 | 全部后端动作 |
| `root/usr/lib/lua/luci/controller/passwall_device.lua` | M3 | HTTP 路由/参数透传 |
| `root/usr/lib/lua/luci/view/passwall_device/main.htm` | M3 | 主管理页面 |
| `root/usr/lib/lua/luci/view/passwall_device/portal.htm` | M2 | 设备认证页 |
| `root/usr/share/passwall-device/firewall.sh` | M5 | nft/iptables 拦截与门户重定向 |
| `root/usr/share/passwall-device/guard.sh` | M5 | 5s 守护：离线清理 + 防火墙指纹同步 |
| `root/usr/share/passwall-device/portal-setup.sh` | M5 | DNS(hosts/dnsmasq) 与 nginx 强制门户 |
| `root/etc/init.d/passwall-device` | M5 | procd 启停、reload 触发器 |
| `root/etc/config/passwall_device` | 全部 | UCI 默认配置 |
| `root/usr/share/rpcd/acl.d/luci-app-passwall-device.json` | M3 | LuCI ACL 权限 |
| `build-openwrt.sh` | M7 | 打 ipk |
| `install.sh` / `uninstall.sh` | M7 | 直接目录安装/卸载 |
| `package/CONTROL/{control,postinst,prerm}` | M7 | opkg 控制脚本 |
| `deploy/nginx-passwall-editor.conf` | M5 | 反向代理参考（本机用） |
| `update.json` / `VERSION` / `root/usr/share/passwall-device/VERSION` | M6 | 自更新清单与版本号 |
| `tests/test_extract.lua` | M1 | 提取逻辑冒烟测试 |
