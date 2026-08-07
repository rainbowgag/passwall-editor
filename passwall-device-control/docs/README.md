# PassWall 设备口令 —— 模块化开发索引

> 本文档把整个 `passwall-device-control` 项目拆成若干个**职责单一**的模块。每个模块单独一个文档，记录了它的范围、关键文件、核心函数/动作、常见改动点、测试与验证方式，以及**如何在一个新对话里单独描述该模块的需求**。
>
> **为什么要拆分**：本项目后端逻辑高度集中在 `app.lua`（约 1150 行），界面与脚本也互相耦合。过去一个对话里塞下全部上下文后，对话变得很长，容易卡在“网络连接中”。拆分后，新对话只需附带对应的模块文档（+ 必要时指定源码文件），就能聚焦一件事，避免把整个项目都读一遍。

## 如何使用

1. 到 `docs/` 找到与你要做的事最接近的模块文档。
2. 打开一个**新的对话**，粘贴该模块文档的 **“在新对话中的开场白”** 段落（或直接说“先读 docs/xx.md，然后……”，并给出你要改的需求）。
3. 如果要跨模块改动，就在同一条消息里列出涉及的模块，让对话按需读取相关文件。

## 模块清单

| 模块 | 文档 | 一句话职责 | 典型对话话题 |
|------|------|-----------|--------------|
| M1 节点导入与解析 | [module-01-import.md](module-01-import.md) | 从混杂文本提取 vmess/vless/trojan/trojan-go/ss/socks 并写入 PassWall，生成口令 | “导入更多协议/格式”“口令编号规则” |
| M2 设备绑定与认证 | [module-02-binding.md](module-02-binding.md) | 设备输口令绑定节点、建 ACL、踢旧设备、开/关认证服务 | “绑定流程”“踢设备”“绑定的兼容性” |
| M3 管理界面与 API | [module-03-management-ui.md](module-03-management-ui.md) | LuCI 主页面 + HTTP API：节点/口令/设备的增删改查与搜索 | “加个按钮/列”“改搜索”“批量操作” |
| M4 节点健康测试 | [module-04-healthcheck.md](module-04-healthcheck.md) | 用 sing-box/xray 起临时代理测出口 IP，展示连通状态 | “测速/连通性”“测试逻辑改动” |
| M5 防火墙与强制门户 | [module-05-firewall-portal.md](module-05-firewall-portal.md) | nftables/iptables 阻断、DNS 跳转、guard 守护、init.d | “改拦截规则”“IPv6 处理”“门户跳转” |
| M6 自更新与版本 | [module-06-update.md](module-06-update.md) | 检查远程清单、校验 SHA-256、opkg 安装升级 | “发新版本”“改更新源”“升级校验” |
| M7 打包安装卸载 | [module-07-packaging.md](module-07-packaging.md) | 构建 ipk、安装/卸载脚本、postinst/prerm、迁移清理 | “重新打包”“备份/恢复”“卸载恢复” |

## 共享参考

- [reference.md](reference.md)：UCI 配置 schema、`app.lua` 的全部命令行动作、控制器 HTTP 路由、全项目文件清单。**任何模块改动前都建议先看这份**，因为它记录了各模块都依赖的数据结构与接口。

## 文件结构速览

```text
passwall-device-control/
├─ app.lua                          # 后端主逻辑（import/bind/管理/测试/更新），M1-M4/M6 共用
├─ controller/passwall_device.lua   # LuCI HTTP 路由与参数透传，M3
├─ view/passwall_device/main.htm    # 主管理页面（JS），M3/M4/M6
├─ view/passwall_device/portal.htm  # 设备认证页，M2
├─ firewall.sh / guard.sh           # nft/iptables + 守护，M5
├─ portal-setup.sh                  # DNS/nginx 强制门户，M5
├─ init.d/passwall-device           # 服务启停，M5
├─ build-openwrt.sh / install.sh / uninstall.sh / package/CONTROL/*  # M7
├─ update.json / VERSION            # 自更新清单，M6
└─ config/passwall_device           # UCI 默认配置，见 reference.md
```

> 路径均相对仓库根 `passwall-device-control/`。绝对路径前缀：`D:\Users\youyo\Documents\passwall控制\passwall-device-control\`。
