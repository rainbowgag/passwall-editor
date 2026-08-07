# M3 管理界面与 API

## 职责范围

LuCI 主管理页面的展示与交互，以及对应的 HTTP API 后端。覆盖节点、口令、设备（绑定）三类对象的列表、搜索、编辑、批量删除/解绑。这是用户日常“在后台操作”的模块。

## 涉及文件

- `view/passwall_device/main.htm`（全部页面结构与前端 JS）
- `controller/passwall_device.lua`（路由与参数透传）
- `app.lua` 中的列表/编辑/删除动作
- `root/usr/share/rpcd/acl.d/luci-app-passwall-device.json`（LuCI 权限）

## 页面组成（`main.htm`）

1. **服务状态卡片**：启用/停用、刷新、版本显示（版本部分属 M6）。
2. **批量导入卡片**：属 M1。
3. **节点与口令卡片**：节点列表、口令 chips、编辑、测试（测试属 M4）、批量添加口令、批量删除。
4. **设备绑定卡片**：绑定列表、设备备注、批量解绑。
5. **危险操作卡片**：一键恢复初始配置（双重确认后清空所有节点/口令/绑定并停用服务，走 `reset` 动作）。
6. **最近日志**：`logread -e passwall-device`。

版本区另有“回退到该版本”下拉（属 M6），列出更新清单中的历史版本。

前端用原生 JS + `fetch` POST 到 `/admin/services/passwall_device/<action>`。状态来自 `GET status` 返回的 `{enabled,nodes,bindings,version,...}`。

## 核心后端函数（`app.lua` 行号）

| 函数 | 行号 | 作用 |
|------|------|------|
| `list_status` | 194 | 汇总节点/绑定/口令/开关/日志，是页面的数据源 |
| `update_node` | 845 | 改节点名（去重校验） |
| `update_code` | 866 | 改口令（去重校验，同步到绑定） |
| `add_codes` | 883 | 为选中节点追加口令 |
| `delete_codes` | 899 | 删口令，关联绑定随之解绑断网 |
| `update_binding` | 918 | 改设备自定义备注 |
| `delete_nodes` | 939 | 删节点（可迁移动到另一节点或级联删绑定/口令） |
| `unbind_many` | 996 | 批量解绑并断网 |
| `reset_all` | — | 一键恢复初始配置：清空全部节点/口令/绑定/ACL，恢复全局默认并停用服务 |

## 关键行为要点

- 节点/口令搜索在前端 `render()` 里按 `remarks`+口令拼接字符串过滤。
- 全选 checkbox 只作用于“当前筛选结果”（`nodes_all`/`bindings_all`）。
- 批量测试并发上限 3（前端 `Promise.all` 控制）。
- 删除节点时可输入“替换节点名”做迁移：绑定和口令的 `node_id` 改指向新节点，ACL 的 `tcp_node` 也一并改。

## 常见改动点

- 新增列/按钮/批量操作：改 `main.htm` 的表格结构与 JS，再在 `controller` 加路由、`app.lua` 加动作并接进分发块（`app.lua:1131`）。
- 改搜索规则（例如加按备注搜索）。
- 改状态展示（在线绿字、离线红字保留绑定）。
- 改空状态文案。
- 改恢复初始配置的确认文案与动作（`main.htm` 的 `reset_btn`、`app.lua` 的 `reset_all`）。

## 在新对话中的开场白

> 本项目是 OpenWrt PassWall 设备口令插件，先读 `docs/reference.md` 再读 `docs/module-03-management-ui.md`（M3 管理界面与 API）。我要改的需求是：<描述界面或接口改动>。相关源码是 `main.htm`、`controller/passwall_device.lua`，以及 `app.lua` 的 `list_status` 和各类 update/delete/add 函数。
