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

local function build_status()
	local out = sys.exec(SCRIPT .. " luci-status 2>/dev/null") or ""
	local default_rule = out:match("default_rule=([^\n]+)") or ""
	local https = out:match("https=([^\n]+)") or ""
	local today, today_workday = out:match("today=([%d%-]+)%s+workday=(%w+)")
	local tomorrow, tomorrow_workday = out:match("tomorrow=([%d%-]+)%s+workday=(%w+)")
	local wan_up = first_line("ifstatus wan 2>/dev/null | jsonfilter -e '@.up' 2>/dev/null")
	local f50_up = first_line("ifstatus f50 2>/dev/null | jsonfilter -e '@.up' 2>/dev/null")
	local hm = tonumber(os.date("%H%M")) or 0
	local outage_tonight = (tomorrow_workday == "yes")
	local morning_window = (hm < 750 and today_workday == "yes")
	local night_window = (hm >= 2320 and tomorrow_workday == "yes")
	local outage_window = morning_window or night_window
	local current_exit = (trim(default_rule) == "f50_first") and "F50" or "校园 WAN"
	local recommended_policy = outage_window and "f50_first" or "campus_first"
	local headline, level, next_action, window_label

	if morning_window then
		window_label = "工作日早晨断网窗口"
		next_action = "07:50 后自动切回校园 WAN"
	elseif night_window then
		window_label = "今晚断网窗口"
		next_action = "明早 07:50 后自动切回校园 WAN"
	elseif outage_tonight then
		window_label = "今晚会断网"
		next_action = "23:20 自动切到 F50"
	else
		window_label = "今晚预计不断网"
		next_action = "保持校园 WAN"
	end

	if outage_window then
		if f50_up ~= "true" then
			level = "danger"
			headline = "断网窗口：F50 离线"
		elseif trim(default_rule) == "f50_first" then
			level = "success"
			headline = "断网窗口：F50 保护中"
		else
			level = "danger"
			headline = "断网窗口：当前未走 F50"
		end
	elseif outage_tonight then
		if f50_up ~= "true" then
			level = "danger"
			headline = "今晚会断网，但 F50 离线"
		elseif trim(default_rule) == "f50_first" then
			level = "success"
			headline = "今晚会断网，已提前走 F50"
		else
			level = "warning"
			headline = "今晚会断网，等待自动切换"
		end
	else
		if trim(default_rule) == "f50_first" then
			level = "info"
			headline = "当前走 F50，今晚预计不断网"
		else
			level = "success"
			headline = "当前走校园 WAN，今晚预计不断网"
		end
	end

	return {
		default_rule = trim(default_rule),
		https = trim(https),
		today = today or "",
		today_workday = today_workday or "",
		tomorrow = tomorrow or "",
		tomorrow_workday = tomorrow_workday or "",
		wan_online = (wan_up == "true"),
		f50_online = (f50_up == "true"),
		wan_ip = first_line("ifstatus wan 2>/dev/null | jsonfilter -e '@[\"ipv4-address\"][0].address' 2>/dev/null"),
		f50_ip = first_line("ifstatus f50 2>/dev/null | jsonfilter -e '@[\"ipv4-address\"][0].address' 2>/dev/null"),
		now = os.date("%F %H:%M:%S"),
		current_exit = current_exit,
		outage_tonight = outage_tonight,
		outage_window = outage_window,
		recommended_policy = recommended_policy,
		window_label = window_label,
		next_action = next_action,
		headline = headline,
		level = level
	}
end

function index()
	local page

	page = entry({"admin", "services", "wan_switch"}, cbi("wan_switch"), _("WAN/F50切换"), 60)
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
	elseif target == "f50" then
		mode = "f50"
	elseif target == "auto" then
		mode = "auto"
	else
		http.status(400, "Bad Request")
		http.prepare_content("application/json")
		http.write_json({ success = false, message = "invalid target" })
		return
	end

	local rc = sys.call(SCRIPT .. " " .. mode .. " >/dev/null 2>&1")

	http.prepare_content("application/json")
	http.write_json({
		success = (rc == 0),
		target = mode,
		status = build_status()
	})
end

function action_status()
	http.prepare_content("application/json")
	http.write_json(build_status())
end
