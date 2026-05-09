local m, s, o

m = SimpleForm("wan_switch", translate("校园网/随身WiFi切换"),
	translate("按工作日夜间规则在校园 WAN 和 USB 随身 WiFi 之间切换。白天使用校园网单线策略并关闭 USB 计费网络，夜间提前预热 USB 后再切换。"))

m.submit = false
m.reset = false

s = m:section(SimpleSection)
s.template = "wan_switch/status"

s = m:section(SimpleSection)

o = s:option(DummyValue, "current_policy", translate("当前策略"))
o.cfgvalue = function(self)
	return translate("加载中...")
end

o = s:option(DummyValue, "wan_status", translate("校园 WAN"))
o.cfgvalue = function(self)
	return translate("加载中...")
end

o = s:option(DummyValue, "usb_status", translate("USB 随身 WiFi"))
o.cfgvalue = function(self)
	return translate("加载中...")
end

o = s:option(DummyValue, "billing_status", translate("USB 计费保护"))
o.cfgvalue = function(self)
	return translate("加载中...")
end

o = s:option(DummyValue, "workday_status", translate("工作日判断"))
o.cfgvalue = function(self)
	return translate("加载中...")
end

o = s:option(Button, "switch_to_campus", translate("切到校园 WAN"))
o.inputstyle = "apply"
o.write = function(self, section) end

o = s:option(Button, "switch_to_usb", translate("切到 USB 随身 WiFi"))
o.inputstyle = "apply"
o.write = function(self, section) end

o = s:option(Button, "switch_auto", translate("按自动规则切换"))
o.inputstyle = "apply"
o.write = function(self, section) end

o = s:option(Button, "login_campus", translate("仅校园网认证"))
o.inputstyle = "reload"
o.write = function(self, section) end

o = s:option(Button, "down_wan", translate("切到 USB 并关闭校园 WAN"))
o.inputstyle = "remove"
o.write = function(self, section) end

o = s:option(Button, "down_usb", translate("切回校园 WAN 并关闭 USB"))
o.inputstyle = "remove"
o.write = function(self, section) end

return m
