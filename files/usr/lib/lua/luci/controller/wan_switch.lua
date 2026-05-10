module("luci.controller.wan_switch", package.seeall)

local http = require "luci.http"
local sys = require "luci.sys"

local SCRIPT = "/root/f50-wan-switch.sh"

local function trim(s)
	return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function first_line(cmd)
	return trim((sys.exec(cmd) or ""):match("([^\n]*)"))
end

local function line_value(out, key)
	return trim(out:match(key .. "=([^\n]*)") or "")
end

local function iface_ip(iface)
	return first_line("ifstatus " .. iface .. " 2>/dev/null | jsonfilter -e '@[\"ipv4-address\"][0].address' 2>/dev/null")
end

local function route_dev()
	return first_line("ip -4 route show default 2>/dev/null | awk '/^default/ { for (i=1; i<=NF; i++) if ($i == \"dev\") { print $(i+1); exit } }'")
end

local function iface_dev(iface)
	local dev = first_line("ifstatus " .. iface .. " 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null")
	if dev == "" then
		dev = first_line("ifstatus " .. iface .. " 2>/dev/null | jsonfilter -e '@.device' 2>/dev/null")
	end
	if dev == "" then
		dev = first_line("uci -q get network." .. iface .. ".device 2>/dev/null")
	end
	return dev
end

local function shell_quote(s)
	return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'"
end

local function run_script(mode)
	local marker = "__WAN_SWITCH_RC__"
	local cmd = SCRIPT .. " " .. shell_quote(mode) .. " 2>&1; echo " .. marker .. "$?"
	local out = sys.exec(cmd) or ""
	local rc = tonumber(out:match(marker .. "(%d+)%s*$") or "1") or 1
	local clean = trim(out:gsub(marker .. "%d+%s*$", ""))

	return rc, clean
end

local function build_status()
	local out = sys.exec(SCRIPT .. " luci-status 2>/dev/null") or ""
	local mode = line_value(out, "mode")
	local policy = line_value(out, "policy")
	local default_rule = line_value(out, "default_rule")
	local https = line_value(out, "https")
	local usb_mwan_enabled = line_value(out, "usb_mwan_enabled")
	local auto_action = line_value(out, "auto_action")
	local next_action = line_value(out, "next_action")
	local today, today_workday = out:match("today=([%d%-]+)%s+workday=(%w+)")
	local tomorrow, tomorrow_workday = out:match("tomorrow=([%d%-]+)%s+workday=(%w+)")
	local wan_up = first_line("ifstatus wan 2>/dev/null | jsonfilter -e '@.up' 2>/dev/null")
	local usb_up = first_line("ifstatus usb 2>/dev/null | jsonfilter -e '@.up' 2>/dev/null")
	local wan_ip = iface_ip("wan")
	local usb_ip = iface_ip("usb")
	local default_dev = route_dev()
	local usb_dev = iface_dev("usb")
	local hm = tonumber(os.date("%H%M")) or 0
	local outage_tonight = (tomorrow_workday == "yes")
	local morning_window = (hm < 800 and today_workday == "yes")
	local night_prepare_window = (hm >= 2325 and hm < 2330 and tomorrow_workday == "yes")
	local night_window = (hm >= 2330 and tomorrow_workday == "yes")
	local campus_prepare_window = (hm >= 755 and hm < 800 and today_workday == "yes")
	local outage_window = morning_window or night_window
	local current_exit = (mode == "usb" or (usb_dev ~= "" and default_dev == usb_dev)) and "USB 随身 WiFi" or "校园 WAN"
	local recommended_policy = outage_window and "usb_only" or "campus_only"
	local headline, level, window_label
	local usb_online = (usb_up == "true")
	local billing_protection = (mode ~= "usb" and usb_mwan_enabled ~= "1" and not usb_online)

	if morning_window then
		window_label = "工作日早晨断网窗口"
	elseif campus_prepare_window then
		window_label = "校园网预认证窗口"
	elseif night_window then
		window_label = "今晚断网窗口"
	elseif night_prepare_window then
		window_label = "USB 预热窗口"
	elseif outage_tonight then
		window_label = "今晚会断网"
	else
		window_label = "今晚预计不断网"
	end

	if outage_window then
		if mode == "usb" then
			level = usb_online and "success" or "danger"
			headline = usb_online and "断网窗口：USB 随身 WiFi 保护中" or "断网窗口：USB 接口未在线"
		else
			level = "danger"
			headline = "断网窗口：当前未走 USB"
		end
	elseif night_prepare_window then
		level = usb_online and "warning" or "danger"
		headline = usb_online and "USB 已预热，等待 23:30 切换" or "USB 预热中，接口未在线"
	elseif campus_prepare_window then
		level = "warning"
		headline = "校园网预认证中，等待 08:00 切回"
	elseif outage_tonight then
		if mode == "usb" then
			level = usb_online and "success" or "danger"
			headline = usb_online and "今晚会断网，已提前走 USB" or "今晚会断网，但 USB 离线"
		elseif usb_online then
			level = "warning"
			headline = "今晚会断网，USB 已打开，计费保护未完全启用"
		else
			level = "info"
			headline = "今晚会断网，白天 USB 计费保护中"
		end
	else
		if mode == "usb" then
			level = "info"
			headline = "当前走 USB，今晚预计不断网"
		else
			level = billing_protection and "success" or "warning"
			headline = billing_protection and "当前走校园 WAN，USB 计费保护中" or "当前走校园 WAN，请检查 USB 计费保护"
		end
	end

	return {
		mode = mode,
		policy = policy,
		default_rule = default_rule,
		https = https,
		usb_mwan_enabled = usb_mwan_enabled,
		auto_action = auto_action,
		today = today or "",
		today_workday = today_workday or "",
		tomorrow = tomorrow or "",
		tomorrow_workday = tomorrow_workday or "",
		wan_online = (wan_up == "true"),
		usb_online = usb_online,
		wan_ip = wan_ip,
		usb_ip = usb_ip,
		default_dev = default_dev,
		usb_dev = usb_dev,
		now = os.date("%F %H:%M:%S"),
		current_exit = current_exit,
		outage_tonight = outage_tonight,
		outage_window = outage_window,
		billing_protection = billing_protection,
		recommended_policy = recommended_policy,
		window_label = window_label,
		next_action = next_action,
		headline = headline,
		level = level
	}
end

function index()
	local page

	page = entry({"admin", "services", "wan_switch"}, cbi("wan_switch"), _("校园网/随身WiFi切换"), 60)
	page.dependent = true

	entry({"admin", "services", "wan_switch", "switch"}, call("action_switch")).leaf = true
	entry({"admin", "services", "wan_switch", "status"}, call("action_status")).leaf = true

	entry({"admin", "network", "wan_switch"}, alias("admin", "services", "wan_switch"), nil, 60).dependent = true
end

function action_switch()
	local target = http.formvalue("target")
	local mode

	if target == "campus" then
		mode = "campus"
	elseif target == "usb" or target == "f50" then
		mode = "usb"
	elseif target == "auto" then
		mode = "auto"
	elseif target == "prepare-usb" then
		mode = "prepare-usb"
	elseif target == "prepare-campus" then
		mode = "prepare-campus"
	elseif target == "down-wan" then
		mode = "down-wan"
	elseif target == "down-usb" then
		mode = "down-usb"
	elseif target == "login" then
		mode = "login"
	else
		http.status(400, "Bad Request")
		http.prepare_content("application/json")
		http.write_json({ success = false, message = "invalid target" })
		return
	end

	local rc, out = run_script(mode)
	local message = (rc == 0) and "执行完成" or ("执行失败，退出码 " .. tostring(rc))
	if rc ~= 0 and out ~= "" then
		message = message .. "：" .. out
	end

	http.prepare_content("application/json")
	http.write_json({
		success = (rc == 0),
		rc = rc,
		message = message,
		output = out,
		target = mode,
		status = build_status()
	})
end

function action_status()
	http.prepare_content("application/json")
	http.write_json(build_status())
end