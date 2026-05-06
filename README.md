# F50 WAN Switch LuCI

[中文](#中文) | [English](#english)

OpenWrt LuCI 插件和切换脚本，用 `mwan3` 在主 WAN 与 USB 共享网络的中兴 F50 备用 WAN 之间切换。

This repository is sanitized. It does not include router passwords, captive-portal credentials, personal cron jobs, or host-specific backups.

## 中文

### 项目简介

这个项目适合这类场景：路由器平时走主 WAN，例如校园网、有线宽带或宿舍网络；在固定断网时段或主 WAN 不可用时，自动切到通过 USB 连接的中兴 F50、手机 USB 共享网络或其他备用 WAN。

项目包含：

- `/root/f50-wan-switch.sh`：核心切换脚本。
- LuCI 页面：在网页端查看当前状态并手动切换。
- `mwan3` 示例配置：用策略路由切换流量，不直接改 `network.wan.device`。
- 节假日/调休判断：可用于“工作日前一晚断网”这类规则。
- 可选的门户认证登录：切回主 WAN 前先登录并验证主 WAN 真能出公网。

### 功能

- 平时优先走主 WAN。
- 备用 WAN 命名为 `f50`，默认示例设备是 `eth2`。
- 支持手动切换：
  - 主 WAN
  - F50
  - 自动判断
- LuCI 页面显示：
  - 当前实际出口
  - 主 WAN 和 F50 是否在线
  - 今晚是否预计断网
  - 当前是否已经处于 F50 保护状态
  - 下一次自动动作
- 自动判断中国节假日和调休；接口不可用时退回周一到周五规则。
- 如果主 WAN 需要网页登录认证，可以配置登录 URL。脚本会强制从主 WAN 接口发起登录，并确认连通后才切回。

### 仓库结构

```text
README.md
LICENSE
CHANGELOG.md
.github/workflows/validate.yml
install-openwrt.sh
scripts/validate.sh
files/root/f50-wan-switch.sh
files/etc/init.d/f50-wan-switch
files/usr/lib/lua/luci/controller/wan_switch.lua
files/usr/lib/lua/luci/model/cbi/wan_switch.lua
files/usr/lib/lua/luci/view/wan_switch/status.htm
examples/network-f50.conf
examples/firewall-wan-zone-snippet.conf
examples/mwan3.conf
examples/crontab.root
examples/f50-wan-switch.conf.example
```

### 依赖

- OpenWrt + LuCI，已在 OpenWrt 23.05 系固件上测试。
- `mwan3`
- `curl`
- `jsonfilter`

可按需安装：

```sh
opkg update
opkg install mwan3 luci-app-mwan3 curl
```

### 安装

把本仓库复制到 OpenWrt 路由器上，然后运行：

```sh
chmod +x install-openwrt.sh
./install-openwrt.sh
```

再按你的路由器情况合并示例配置：

1. 把 `examples/network-f50.conf` 合并到 `/etc/config/network`。
2. 在 `/etc/config/firewall` 的 `wan` zone 里加入 `list network 'f50'`。
3. 把 `examples/mwan3.conf` 合并到 `/etc/config/mwan3`。
4. 把 `examples/crontab.root` 加入 `/etc/crontabs/root`。不要使用 `@reboot`，部分 OpenWrt/BusyBox 组合会因此导致 `crond` 崩溃；开机自动判断由 `/etc/init.d/f50-wan-switch` 负责。
5. 如果主 WAN 需要门户认证，把 `examples/f50-wan-switch.conf.example` 复制为 `/root/f50-wan-switch.conf`，填入自己的登录 URL，并设置权限：

```sh
chmod 600 /root/f50-wan-switch.conf
```

重载服务：

```sh
/etc/init.d/network reload
ifup f50
/etc/init.d/firewall reload
/etc/init.d/mwan3 enable
/etc/init.d/mwan3 restart
/etc/init.d/cron restart
/etc/init.d/f50-wan-switch enable
```

LuCI 页面地址：

```text
http://<router-ip>/cgi-bin/luci/admin/services/wan_switch
```

### 自动切换逻辑

默认逻辑适合“工作日前一晚断网，工作日早上恢复”的场景：

- 如果明天是工作日，`23:20` 后切到 F50。
- 如果今天是工作日，`07:50` 前保持 F50。
- 其他时间使用主 WAN。

节假日和调休数据来自：

```text
https://timor.tech/api/holiday/info/YYYY-MM-DD
```

结果缓存到：

```text
/root/.cache/f50-wan-switch/
```

如果接口不可用，脚本会退回普通周一到周五规则。

### 门户认证

如果主 WAN 是校园网或需要网页登录认证的网络，可以配置：

```sh
CAMPUS_IFACE='eth1'
CAMPUS_CHECK_IP='223.5.5.5'
CAMPUS_LOGIN_URL='http://example.edu/login?user=YOUR_USER&password=YOUR_PASSWORD'
```

脚本会使用：

```sh
curl --interface "$CAMPUS_IFACE" "$CAMPUS_LOGIN_URL"
```

然后再通过 `ping -I "$CAMPUS_IFACE"` 检查主 WAN 是否真的能出公网。只有检查通过，才会切回主 WAN 优先。

### 常用命令

```sh
/root/f50-wan-switch.sh status
/root/f50-wan-switch.sh campus
/root/f50-wan-switch.sh f50
/root/f50-wan-switch.sh auto
/root/f50-wan-switch.sh campus-login
```

### 本地检查

发布或打包前运行：

```sh
./scripts/validate.sh
```

它会检查 shell 语法，并扫描常见隐私字段。

### 注意事项

- OpenWrt 的“网络/接口”页面可能仍显示 `wan` 绑定在主 WAN 设备上，这是正常的。本项目通过 `mwan3` 策略路由选择实际流量出口。
- 已建立的连接可能继续停留在旧出口，新连接才会按新策略走。
- 不同路由器的 USB 共享网络设备名可能是 `eth2`、`usb0`、`wwan0` 等，使用前需要确认。
- 公开仓库不要提交真实的 `/root/f50-wan-switch.conf`。

### License

本项目使用 MIT License。选择 MIT 是因为这个项目定位为轻量工具和 LuCI 页面，目标是方便其他爱好者复制、修改、研究和二次分发。

## English

### Overview

This project provides an OpenWrt LuCI page and a shell switcher for routing traffic between a primary WAN and a USB-tethered ZTE F50 backup WAN through `mwan3`.

It is useful when a primary network, such as a campus network or dorm network, has predictable outage windows and a USB-tethered backup connection is available.

### Features

- Keeps the primary WAN as the normal path.
- Adds a backup WAN named `f50`, usually a USB RNDIS/CDC Ethernet device such as `eth2`.
- Uses `mwan3` policies instead of changing `network.wan.device`.
- Supports manual switching to:
  - primary WAN
  - F50
  - automatic mode
- Provides a LuCI dashboard showing:
  - current exit path
  - primary WAN and F50 status
  - whether an outage is expected tonight
  - whether F50 protection is active
  - the next automatic action
- Supports China holiday/workday detection for adjusted workdays and holidays.
- Optionally runs captive-portal login before switching back to the primary WAN.

### Requirements

- OpenWrt with LuCI, tested on an OpenWrt 23.05-based build.
- `mwan3`
- `curl`
- `jsonfilter`

Install packages as needed:

```sh
opkg update
opkg install mwan3 luci-app-mwan3 curl
```

### Installation

Copy this repository to the router, then run:

```sh
chmod +x install-openwrt.sh
./install-openwrt.sh
```

Then merge the example configuration snippets:

1. Add `examples/network-f50.conf` to `/etc/config/network`.
2. Add `list network 'f50'` to the existing firewall zone named `wan`.
3. Merge `examples/mwan3.conf` into `/etc/config/mwan3`.
4. Add `examples/crontab.root` lines into `/etc/crontabs/root`. Do not use `@reboot`; some OpenWrt/BusyBox combinations may crash `crond` when parsing it. Boot-time auto mode is handled by `/etc/init.d/f50-wan-switch`.
5. Optional: copy `examples/f50-wan-switch.conf.example` to `/root/f50-wan-switch.conf`, fill in your captive-portal login URL, and run `chmod 600 /root/f50-wan-switch.conf`.

Reload services:

```sh
/etc/init.d/network reload
ifup f50
/etc/init.d/firewall reload
/etc/init.d/mwan3 enable
/etc/init.d/mwan3 restart
/etc/init.d/cron restart
/etc/init.d/f50-wan-switch enable
```

Open LuCI:

```text
http://<router-ip>/cgi-bin/luci/admin/services/wan_switch
```

### Automatic Schedule

The default script assumes this use case:

- if tomorrow is a workday, switch to F50 after `23:20`;
- if today is a workday, keep F50 before `07:50`;
- otherwise use the primary WAN.

It checks Chinese holiday/workday data from:

```text
https://timor.tech/api/holiday/info/YYYY-MM-DD
```

Results are cached under:

```text
/root/.cache/f50-wan-switch/
```

If the API is unavailable, the script falls back to Monday-Friday as workdays.

### Captive-Portal Login

If the primary WAN requires portal authentication, configure `/root/f50-wan-switch.conf`:

```sh
CAMPUS_IFACE='eth1'
CAMPUS_CHECK_IP='223.5.5.5'
CAMPUS_LOGIN_URL='http://example.edu/login?user=YOUR_USER&password=YOUR_PASSWORD'
```

The script forces login through the primary WAN interface, then checks connectivity through the same interface before switching back.

### Commands

```sh
/root/f50-wan-switch.sh status
/root/f50-wan-switch.sh campus
/root/f50-wan-switch.sh f50
/root/f50-wan-switch.sh auto
/root/f50-wan-switch.sh campus-login
```

### Local Checks

Before publishing or packaging, run:

```sh
./scripts/validate.sh
```

The check verifies shell syntax and scans for common private values.

### Notes

- The OpenWrt Network page may still show `wan` bound to the primary device. That is expected. Traffic selection is done by `mwan3` policy routing.
- Existing connections may stay on the previous WAN until they reconnect.
- Review the interface names before applying. Some routers use `usb0`, `eth2`, `wwan0`, or another device name for USB tethering.
- Do not commit a real `/root/f50-wan-switch.conf` to a public repository.

### License

MIT License.
