local m, s, o

m = SimpleForm("wan_switch", translate("WAN/F50切换"),
	translate("使用 mwan3 在校园 WAN 和中兴 F50 之间切换。自动模式会按工作日夜间规则选择出口。"))

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

o = s:option(DummyValue, "f50_status", translate("F50"))
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

o = s:option(Button, "switch_to_f50", translate("切到 F50"))
o.inputstyle = "apply"
o.write = function(self, section) end

o = s:option(Button, "switch_auto", translate("按自动规则切换"))
o.inputstyle = "apply"
o.write = function(self, section) end

return m
