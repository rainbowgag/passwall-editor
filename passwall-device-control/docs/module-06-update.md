# M6 自更新与版本

## 职责范围

页面“当前/最新版本”展示、检查远程更新清单、校验 SHA-256、下载并 `opkg install` 升级。涉及版本比较与远程清单校验。

## 涉及文件

- `app.lua`：`version_parts`、`version_newer`、`fetch_update_manifest`、`check_update`、`install_update`
- `update.json`（远程清单源）
- `VERSION` 与 `root/usr/share/passwall-device/VERSION`（当前版本号）
- `view/passwall_device/main.htm`：版本区与 `checkVersion()`、`update_btn`
- `controller/passwall_device.lua`：`api_version`、`api_update`

## 核心函数（`app.lua` 行号）

| 函数 | 行号 | 作用 |
|------|------|------|
| `version_parts` / `version_newer` | 1060/1066 | 按点分数字比较版本 |
| `fetch_update_manifest` | 1075 | 依次拉取 `UPDATE_MANIFESTS` 两个源，校验字段合法性 |
| `check_update` | 1096 | 返回当前/最新/是否可升级/notes |
| `install_update` | 1107 | 下载→校验 SHA-256→`opkg install`→返回新版本 |

## 更新源

`UPDATE_MANIFESTS`（`app.lua:1055`）依次尝试：

1. `https://raw.githubusercontent.com/rainbowgag/passwall-editor/main/passwall-device-control/update.json`
2. `http://m.yaml.uk:25532/update.json`

清单字段：`version`、`ipk_url`（须 `http(s)://`）、`sha256`（须 64 位十六进制）、`notes`、`published_at`。任一字段不合法即弃用该源。

## 校验与升级

- 仅在 `version_newer(latest, current)` 为真时才允许安装。
- 下载到 `/tmp` 后用 `sha256sum` 与清单 `sha256` 比对，不一致则拒绝并删除。
- `opkg install` 后读取新 `VERSION` 返回；页面 `update_btn` 成功则 1.5s 后刷新。

## 发新版本流程

1. 在 `VERSION` 与 `root/usr/share/passwall-device/VERSION` 递增版本号。
2. 用 `build-openwrt.sh` 产出 `dist/luci-app-passwall-device_<VERSION>_all.ipk`（见 M7）。
3. 更新 `update.json` 的 `version`、`ipk_url`、`sha256`（对产出的 ipk 算 SHA-256）、`notes`。
4. 上传 ipk 到两个更新源对应的位置。

## 常见改动点

- 增删更新源（`UPDATE_MANIFESTS`）。
- 改升级后的回跳/提示（`main.htm` 的 `update_btn` 回调）。
- 改版本比较规则（例如支持预发布版号）。
- 改下载超时（`--connect-timeout 8 --max-time 120`）。

## 在新对话中的开场白

> 本项目是 OpenWrt PassWall 设备口令插件，先读 `docs/reference.md` 再读 `docs/module-06-update.md`（M6 自更新与版本）。我要改的需求是：<描述自更新/版本改动>。相关源码是 `app.lua` 的 `fetch_update_manifest`/`check_update`/`install_update`，`update.json` 与 `VERSION`。
