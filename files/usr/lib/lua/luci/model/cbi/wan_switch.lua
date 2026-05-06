local m, s

m = SimpleForm("wan_switch", translate("WAN/F50切换"),
	translate("使用 mwan3 在校园 WAN 和中兴 F50 之间切换。自动模式会按工作日夜间规则选择出口。"))

m.submit = false
m.reset = false

s = m:section(SimpleSection)
s.template = "wan_switch/status"

return m
