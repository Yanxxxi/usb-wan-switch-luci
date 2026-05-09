 # 校园网 / USB 随身 WiFi 自动切换 LuCI 插件

这是一个适用于 OpenWrt 的 LuCI 插件和切换脚本，用于在 **校园 WAN** 与 **USB 随身 WiFi** 之间自动切换。


- 白天默认只走校园网；
- 白天关闭或禁用 USB 随身 WiFi，避免偷跑计费流量；
- 工作日前夜提前预热 USB；
- 到断网时间切到 USB；
- 工作日早晨提前执行校园网认证；
- 到恢复时间切回校园网，并关闭 USB 计费网络。

文件名仍保留原项目的 `f50-wan-switch.sh`，但页面显示、接口名和配置逻辑已改为校园网 / USB 随身 WiFi。

---

---

## 二、核心策略

本插件使用 mwan3 进行策略路由切换。

由于 USB 是计费网络，本项目不使用“校园网优先、USB 自动备用”的策略，而是使用更安全的单线策略：

| 策略名 | 含义 | 使用场景 |
|---|---|---|
| `campus_only` | 只走校园 WAN | 白天默认状态 |
| `usb_only` | 只走 USB 随身 WiFi | 工作日前夜和早晨断网窗口 |
| `campus_portal` | 校园网认证地址强制走 WAN | 执行校园网登录 |

这样可以避免白天校园网短暂波动时业务流量自动跑到 USB 上产生计费。

---

## 三、自动切换时间线

默认自动规则如下：

| 时间 | 动作 |
|---|---|
| 23:25 - 23:29 | 如果明天是工作日，提前启动 USB，启用 mwan3 的 USB 监控 |
| 23:30 后 | 如果明天是工作日，切到 `usb_only` |
| 次日 07:55 - 07:59 | 如果今天是工作日，提前启动校园 WAN 并执行校园网认证 |
| 次日 08:00 后 | 切回 `campus_only`，关闭 USB 计费网络 |
| 其他时间 | 保持 `campus_only` |

建议 cron 每 5 分钟执行一次：

```cron
@reboot /root/f50-wan-switch.sh auto
*/5 * * * * /root/f50-wan-switch.sh auto
```

示例文件：

```text
examples/crontab.root
```

---

## 四、校园网认证脚本

插件默认调用：

```sh
/root/cumt/login.sh
```


---


## 五、安装文件

项目主要文件：

```text
install-openwrt.sh
files/root/f50-wan-switch.sh
files/usr/lib/lua/luci/controller/wan_switch.lua
files/usr/lib/lua/luci/model/cbi/wan_switch.lua
files/usr/lib/lua/luci/view/wan_switch/status.htm
examples/network-f50.conf
examples/firewall-wan-zone-snippet.conf
examples/mwan3.conf
examples/crontab.root
```

安装脚本会复制：

```text
files/root/f50-wan-switch.sh
files/usr/lib/lua/luci/controller/wan_switch.lua
files/usr/lib/lua/luci/model/cbi/wan_switch.lua
files/usr/lib/lua/luci/view/wan_switch/status.htm
```

到路由器对应目录。

---

## 七、安装步骤

### 1. 安装依赖

在 OpenWrt 上需要有：

```sh
opkg update
opkg install mwan3 luci-app-mwan3 curl jsonfilter
```

如果 LuCI 已安装，一般无需额外安装 LuCI 基础包。

### 2. 上传项目

将整个项目目录上传到 OpenWrt，例如：

```sh
scp -r f50-wan-switch-luci-export root@192.168.1.1:/root/
```

### 3. 执行安装

在路由器上执行：

```sh
cd /root/f50-wan-switch-luci-export
sh install-openwrt.sh
```

安装完成后脚本位于：

```sh
/root/f50-wan-switch.sh
```

LuCI 页面位于：

```text
服务 -> 校园网/随身WiFi切换
```

也可通过旧入口：

```text
网络 -> 校园网/随身WiFi切换
```

---

