# M4 节点健康测试

## 职责范围

对单个或多个节点做连通性测试：用当前节点配置起一个临时代理，通过它访问外部 IP 检测服务（`api.ipify.org`）拿到出口 IP，判断节点是否可用，并把结果写回 `node` 元信息用于界面展示。

## 涉及文件

- `app.lua`：`test_node`、`record_node_test`
- `view/passwall_device/main.htm`：节点行的“测试”按钮与“测试所选节点”批量按钮
- `controller/passwall_device.lua` → `api_test`

## 核心函数（`app.lua` 行号）

| 函数 | 行号 | 作用 |
|------|------|------|
| `record_node_test` | 1011 | 把测试结果写回 `node` 的 `last_test_*` 字段并 commit |
| `test_node` | 1025 | 单节点测试主流程 |

## 测试流程（`test_node`）

1. 校验节点存在。
2. 用 `/usr/share/passwall/app.sh run_socks ... no_run=1` 让 PassWall 生成该节点的临时测试配置（`/tmp/etc/passwall/pwc-node-test-<pid>.json`），监听 `127.0.0.1` 随机端口。
3. 按节点类型选二进制：`sing-box` → `/usr/bin/sing-box run -c`，否则 `/usr/bin/xray run -config`。
4. 后台起代理进程，写 pidfile。
5. `curl --proxy socks5h://127.0.0.1:<port>` 访问 `https://api.ipify.org`，取出口 IP。
6. 杀进程、清理临时文件，按结果走 `record_node_test`。
7. 失败返回 `reachable=false`（节点在界面上标“代理不可用”，绑定设备保持断网语义）。

## 界面行为

- 单节点：行内“测试”按钮 → `POST test`。
- 批量：`test_nodes_btn` 并发 3，逐个调用 `POST test`，完成提示“N 个可用”。
- 结果显示在 `nodeStatus()`：`last_reachable=1` 绿字“代理可用 + 出口 IP”；`0` 红字“代理不可用”；空为“未测试”。

## 常见改动点

- 换检测目标（改 `api.ipify.org`，例如改用 `ifconfig.me`/多目标）。
- 改超时（`--connect-timeout 3 --max-time 8`）或并发上限（前端 `Math.min(3, ids.length)`）。
- 改测试结果展示文案/颜色。
- 加“测速”（带宽）需扩展流程（当前只测连通+出口 IP）。

## 在新对话中的开场白

> 本项目是 OpenWrt PassWall 设备口令插件，先读 `docs/reference.md` 再读 `docs/module-04-healthcheck.md`（M4 节点健康测试）。我要改的需求是：<描述测试逻辑/展示改动>。相关源码是 `app.lua` 的 `test_node`/`record_node_test` 和 `main.htm` 的测试相关 JS。
