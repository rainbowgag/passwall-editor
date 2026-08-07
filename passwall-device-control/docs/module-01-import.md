# M1 节点导入与解析

## 职责范围

从用户粘贴的**混杂文本**中自动提取代理节点链接，规范化后写入 PassWall，并按规则批量生成口令。本模块只负责“把链接变成 PassWall 节点 + 口令”，不负责设备绑定、防火墙等。

## 涉及文件

- `app.lua`（主要逻辑，见下方行号）
- `controller/passwall_device.lua` → `api_import`（HTTP 参数透传）
- `view/passwall_device/main.htm` → “批量导入节点”卡片与 `import_btn` 事件
- `tests/test_extract.lua`（提取逻辑冒烟测试）

## 支持与生成的链接类型

| 类型 | 说明 |
|------|------|
| `vmess://` `vless://` | 走 PassWall 官方订阅解析器导入 |
| `trojan://` | 规范化后走官方解析器，且默认用 sing-box 核心 |
| `trojan-go://` | 仅把 scheme 改成 `trojan://`，**保留** TLS/WS/Host/路径参数（`app.lua:390` 附近） |
| `ss://` | 支持 SIP002 与旧式 Base64，走官方解析器 |
| `socks://` `socks5://` | 自建节点，默认 sing-box；支持 `socks://Base64(user:pass)@host:port#备注` |
| `IP:端口:用户名:密码` / `IP:端口` | SOCKS 简写，自动转成 socks5 节点 |

## 核心函数（`app.lua` 行号）

| 函数 | 行号 | 作用 |
|------|------|------|
| `split_link_codes` | 58 | 解析行尾 `---口令1 口令2` 显式口令 |
| `extract_links` | 268 | 从文本提取节点并识别显式口令，忽略无关行 |
| `parse_socks_link` | 302 | 解析 socks 链接（含 Base64 认证） |
| `code_in_use` | 330 | 口令去重校验 |
| `create_codes` | 337 | 按前缀+位数生成连续口令 |
| `create_explicit_codes` | 362 | 生成用户显式指定的口令 |
| `import_nodes` | 377 | 主流程：写官方订阅→按序取新增节点→建 meta→配核心→生成口令 |

## 关键行为要点

- 导入顺序 = 新增节点顺序（`import_nodes` 用 `c:foreach` 且按 `.name` 之外的写入序，注释专门提醒不要按 `.name` 排序）。
- socks 节点排在前、官方解析节点排在后，再匹配 `---口令` 显式队列（`app.lua:439` 附近）。
- sing-box 优先条件（`app.lua:459` 附近）：VLESS Reality、Trojan、socks 节点且有 `/usr/bin/sing-box` 时设 `type=sing-box`。
- 全部成功后才 commit；若 PassWall 一个节点都没加会返回错误。

## 常见改动点

- 新增一种协议（例如 `hysteria2://`、`wireguard://`）：在 `extract_links` 的 `accepted` 表加入 scheme；socks 之外的新协议通常走 PassWall 官方解析器。
- 改口令生成规则：调 `create_codes` 的 `code_width`/`code_prefix`/起始号逻辑。
- 改显式口令解析分隔符：调 `split_link_codes`。

## 测试与验证

```sh
lua tests/test_extract.lua     # 提取冒烟测试（需 luci.jsonc）
```

对照用例：链接末尾带 `---A101 A102` 应生成对应显式口令；socks 简写 `IP:端口:用户:密码` 应被识别；无关行应进入 `ignored`。

## 在新对话中的开场白

> 本项目是 OpenWrt PassWall 设备口令插件，先读 `docs/reference.md` 了解数据结构与接口，再读 `docs/module-01-import.md`（M1 节点导入与解析）。我要改的需求是：<在此描述你想要的导入/口令改动>。相关源码是 `passwall-device-control/root/usr/share/passwall-device/app.lua`（只看导入相关函数）与 `tests/test_extract.lua`。
