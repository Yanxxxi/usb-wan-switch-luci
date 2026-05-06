# F50 WAN Switch LuCI

OpenWrt LuCI page and shell script for switching between a primary WAN and a USB-tethered ZTE F50 backup WAN through `mwan3`.

This repository is sanitized: it does not include router passwords, campus login credentials, personal cron jobs, or host-specific backups.

## What It Does

- Keeps the normal WAN interface as the default path most of the time.
- Adds a second WAN named `f50`, usually a USB RNDIS/CDC Ethernet device such as `eth2`.
- Uses `mwan3` policies instead of changing `network.wan.device`.
- Can manually switch to:
  - primary WAN
  - F50
  - automatic mode
- Provides a LuCI page under `Services -> WAN/F50 Switch`.
- The dashboard shows:
  - current exit path
  - whether the F50 is online
  - whether tonight is expected to have an outage
  - whether protection is active
  - the next automatic action

## Repository Layout

```text
README.md
CHANGELOG.md
.github/workflows/validate.yml
install-openwrt.sh
scripts/validate.sh
files/root/f50-wan-switch.sh
files/usr/lib/lua/luci/controller/wan_switch.lua
files/usr/lib/lua/luci/model/cbi/wan_switch.lua
files/usr/lib/lua/luci/view/wan_switch/status.htm
examples/network-f50.conf
examples/firewall-wan-zone-snippet.conf
examples/mwan3.conf
examples/crontab.root
```

## Requirements

- OpenWrt with LuCI, tested on an OpenWrt 23.05-based build.
- `mwan3` and LuCI-compatible Lua runtime.
- `curl` and `jsonfilter` for holiday/workday detection.
- A primary WAN interface named `wan`.
- A backup interface named `f50`.

Install packages as needed:

```sh
opkg update
opkg install mwan3 luci-app-mwan3 curl
```

## Install

Copy this directory to the router, then run:

```sh
chmod +x install-openwrt.sh
./install-openwrt.sh
```

Then merge the example config snippets:

1. Add `examples/network-f50.conf` into `/etc/config/network`.
2. Add `list network 'f50'` to the existing firewall zone named `wan`.
3. Merge `examples/mwan3.conf` into `/etc/config/mwan3`.
4. Add `examples/crontab.root` lines into `/etc/crontabs/root`.
5. Optional: copy `examples/f50-wan-switch.conf.example` to `/root/f50-wan-switch.conf`, fill in your captive-portal login URL, and run `chmod 600 /root/f50-wan-switch.conf`.

Reload services:

```sh
/etc/init.d/network reload
ifup f50
/etc/init.d/firewall reload
/etc/init.d/mwan3 enable
/etc/init.d/mwan3 restart
/etc/init.d/cron restart
```

Open LuCI:

```text
http://<router-ip>/cgi-bin/luci/admin/services/wan_switch
```

## Automatic Schedule

The default script assumes this use case:

- if tomorrow is a workday, switch to F50 after `23:20`;
- if today is a workday, keep F50 before `07:50`;
- otherwise use primary WAN.

It checks Chinese holiday/workday data from:

```text
https://timor.tech/api/holiday/info/YYYY-MM-DD
```

Results are cached under:

```text
/root/.cache/f50-wan-switch/
```

If the API is unavailable, the script falls back to Monday-Friday as workdays.

## Commands

```sh
/root/f50-wan-switch.sh status
/root/f50-wan-switch.sh campus
/root/f50-wan-switch.sh f50
/root/f50-wan-switch.sh auto
/root/f50-wan-switch.sh campus-login
```

## Local Checks

Before publishing or packaging, run:

```sh
./scripts/validate.sh
```

The check verifies shell syntax and scans for common private values.

## Notes

- The OpenWrt Network page may still show `wan` bound to the primary device. That is expected. Traffic selection is done by `mwan3` policy routing.
- Existing connections may stay on the previous WAN until they reconnect.
- Review the interface names before applying. Some routers use `usb0`, `eth2`, `wwan0`, or another device name for USB tethering.
- If the primary WAN requires captive-portal login, configure `/root/f50-wan-switch.conf`. The script will force login through the primary WAN interface and only switch back after the primary WAN passes the connectivity check.
- Choose a license before publishing this package publicly.
