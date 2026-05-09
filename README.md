 # 校园网 / USB 随身 WiFi 自动切换 LuCI 插件

这是一个适用于 OpenWrt 的 LuCI 插件和切换脚本，用于在 **校园 WAN** 与 **USB 随身 WiFi** 之间自动切换。

当前版本按“USB 是计费网络”的前提设计：

- 白天默认只走校园网；
- 白天关闭或禁用 USB 随身 WiFi，避免偷跑计费流量；
- 工作日前夜提前预热 USB；
- 到断网时间切到 USB；
- 工作日早晨提前执行校园网认证；
- 到恢复时间切回校园网，并关闭 USB 计费网络。

文件名仍保留原项目的 `f50-wan-switch.sh`，但页面显示、接口名和配置逻辑已改为校园网 / USB 随身 WiFi。

---

## 一、适配的接口名称

本项目按你的路由器环境适配：


USB 网络示例配置在：

```text
examples/network-f50.conf
```

虽然文件名仍保留 `network-f50.conf`，但内容已经是：

```conf
config interface 'usb'
	option device 'usb0'
	option proto 'dhcp'
	option metric '20'
	option peerdns '0'
	list dns '223.5.5.5'
	list dns '119.29.29.29'
```

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

由于登录脚本中包含账号和密码，**本仓库不保存你的真实账号密码**。

你需要在路由器上手动创建：

```sh
mkdir -p /root/cumt
vi /root/cumt/login.sh
chmod +x /root/cumt/login.sh
```

示例：

```sh
#!/bin/sh

USER_ACCOUNT="你的账号"
USER_PASSWORD="你的密码"

curl "http://10.2.5.251:801/eportal/?" \
-G \
--data-urlencode "c=Portal" \
--data-urlencode "a=login" \
--data-urlencode "login_method=1" \
--data-urlencode "user_account=${USER_ACCOUNT}" \
--data-urlencode "user_password=${USER_PASSWORD}"
```

mwan3 配置中已经包含：

```conf
config rule 'campus_portal'
	option dest_ip '10.2.5.251'
	option use_policy 'campus_only'
```

这条规则用于保证访问校园网认证地址 `10.2.5.251` 时固定走校园 WAN，而不是走 USB。

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

## 八、合并 OpenWrt 配置

### 1. 网络配置

参考：

```text
examples/network-f50.conf
```

将 USB 接口配置合并到：

```text
/etc/config/network
```

核心内容：

```conf
config interface 'usb'
	option device 'usb0'
	option proto 'dhcp'
	option metric '20'
	option peerdns '0'
	list dns '223.5.5.5'
	list dns '119.29.29.29'
```

### 2. 防火墙配置

参考：

```text
examples/firewall-wan-zone-snippet.conf
```

将 `usb` 加入现有 wan 防火墙区域：

```conf
list network 'usb'
```

示例：

```conf
config zone
	option name 'wan'
	option input 'REJECT'
	option output 'ACCEPT'
	option forward 'REJECT'
	option masq '1'
	option mtu_fix '1'
	list network 'wan'
	list network 'usb'
```

### 3. mwan3 配置

参考：

```text
examples/mwan3.conf
```

核心策略：

```conf
config policy 'campus_only'
	option last_resort 'unreachable'
	list use_member 'wan_m1_w3'

config policy 'usb_only'
	option last_resort 'unreachable'
	list use_member 'usb_m1_w3'

config rule 'campus_portal'
	option dest_ip '10.2.5.251'
	option use_policy 'campus_only'

config rule 'default_rule'
	option dest_ip '0.0.0.0/0'
	option use_policy 'campus_only'
```

注意：

```conf
config interface 'usb'
	option enabled '0'
```

USB 的 mwan3 监控默认关闭。脚本会在夜间预热或切换到 USB 时自动启用，切回校园网后再关闭。

### 4. cron 配置

参考：

```text
examples/crontab.root
```

合并到 root 的 crontab：

```sh
crontab -e
```

加入：

```cron
@reboot /root/f50-wan-switch.sh auto
*/5 * * * * /root/f50-wan-switch.sh auto
```

---

## 九、脚本命令

```sh
/root/f50-wan-switch.sh auto
```

按自动规则执行。

```sh
/root/f50-wan-switch.sh campus
```

切到校园 WAN 单线策略，执行校园网认证，并开启 USB 计费保护：

- 关闭 mwan3 的 USB 监控；
- 关闭 USB 接口，避免继续产生 USB 计费流量。

```sh
/root/f50-wan-switch.sh usb
```

切到 USB 随身 WiFi 单线策略，并关闭 USB 计费保护：

- 启动 USB 接口；
- 启用 mwan3 的 USB 监控；
- 将默认流量切到 `usb_only`。

```sh
/root/f50-wan-switch.sh prepare-usb
```

只预热 USB：启动 `usb` 接口，启用 mwan3 的 USB 监控，但不切换默认出口。

```sh
/root/f50-wan-switch.sh prepare-campus
```

只预认证校园网：启动 `wan` 接口并执行 `/root/cumt/login.sh`，但不切换默认出口。

```sh
/root/f50-wan-switch.sh login
```

只执行校园网认证。

```sh
/root/f50-wan-switch.sh down-wan
```

手动关闭校园 WAN 接口，便于测试和临时断开校园网。

```sh
/root/f50-wan-switch.sh down-usb
```

手动关闭 USB 随身 WiFi 接口，并关闭 mwan3 的 USB 监控，便于测试和避免 USB 计费流量。

兼容别名：

```sh
/root/f50-wan-switch.sh wan-down
/root/f50-wan-switch.sh stop-wan
/root/f50-wan-switch.sh usb-down
/root/f50-wan-switch.sh stop-usb
```

```sh
/root/f50-wan-switch.sh status
```

输出脚本状态和 mwan3 状态。

兼容旧命令：

```sh
/root/f50-wan-switch.sh f50
```

等价于：

```sh
/root/f50-wan-switch.sh usb
```

---

## 十、USB 计费保护说明

本项目默认尽量避免白天 USB 产生流量：

1. 白天使用 `campus_only`，默认流量不能走 USB；
2. 白天关闭 `mwan3.usb.enabled`，避免 USB 监控探测流量；
3. 切回校园网后执行 `ifdown usb`；
4. 只有 23:25 预热 USB 之后才可能产生 USB 流量；
5. 23:30 后才正式切到 USB。

需要注意：

- 23:25 到 23:30 的预热阶段可能产生 DHCP、mwan3 探测等少量流量；
- 23:30 到 08:00 使用 USB，是预期内计费流量；
- 如果你在 LuCI 中手动点击“切到 USB 随身 WiFi”，会立即开始使用 USB 计费网络。

---

## 十一、验证命令

安装并合并配置后，可以执行：

```sh
/root/f50-wan-switch.sh luci-status
```

期望能看到类似：

```text
mode=campus
policy=campus_only
default_rule=campus_only
usb_mwan_enabled=0
auto_action=campus
```

查看 mwan3：

```sh
mwan3 status
```

查看接口：

```sh
ifstatus wan
ifstatus usb
```

查看日志：

```sh
logread | grep wan-usb-switch
```

---

## 十二、故障排查

### 1. LuCI 页面打不开

执行：

```sh
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null
/etc/init.d/uhttpd reload
```

### 2. 点击按钮无反应

检查脚本权限：

```sh
chmod 755 /root/f50-wan-switch.sh
```

检查 LuCI 调用：

```sh
/root/f50-wan-switch.sh luci-status
```

### 3. 校园网认证失败

检查：

```sh
ls -l /root/cumt/login.sh
chmod +x /root/cumt/login.sh
/root/cumt/login.sh
```

确认 mwan3 中存在：

```conf
config rule 'campus_portal'
	option dest_ip '10.2.5.251'
	option use_policy 'campus_only'
```

### 4. USB 无法上线

检查接口名和设备名：

```sh
ifstatus usb
ip link show usb0
```

如果设备名不是 `usb0`，需要修改：

```text
/etc/config/network
```

以及示例中的 `option device`。

### 5. 白天仍有 USB 流量

检查当前策略：

```sh
uci get mwan3.default_rule.use_policy
uci get mwan3.usb.enabled
```

白天应为：

```text
campus_only
0
```

如果不是，可以执行：

```sh
/root/f50-wan-switch.sh campus
```

手动点击 LuCI 中的“切到 USB 随身 WiFi”或执行：

```sh
/root/f50-wan-switch.sh usb
```

会主动关闭 USB 计费保护并开始使用 USB 网络。切回“校园 WAN”或执行：

```sh
/root/f50-wan-switch.sh campus
```

会重新开启 USB 计费保护。

---

## 十三、设计取舍

为了避免 USB 计费网络白天偷跑流量，本项目没有采用“双 WAN 常在线 + USB 自动备用”的高可用方案，而是采用：

```text
白天 campus_only
夜间 usb_only
切换前预热
早晨预认证
切回后关闭 USB
```

这能在“尽量无感切换”和“控制 USB 计费流量”之间取得更稳妥的平衡。