-- aether gamesense GUI: renders Kits + Legit panels only.
-- Key GUI and welcome dashboard are untouched.
local vape = shared.vape
assert(type(vape) == 'table', 'aether gui: missing vape')
local fetch = assert(shared.AetherV2FetchSource, 'aether gui: missing fetch')

local src = fetch('aetherv2/lib/aether-ui.lua')
local GS = assert((loadstring or load)(src, 'aether-ui'))()
assert(type(GS) == 'table' and type(GS.Window) == 'function', 'aether gui: bad ui lib')

local function disp(mod)
	return tostring(mod.DisplayName or mod.Name or 'Module')
end

local function modOn(mod)
	return mod.Enabled == true
end

local Window = GS:Window({Name = 'aether', CloseBind = Enum.KeyCode.Insert})

local function renderOption(sec, opt, flag, kids)
	local t = tostring(opt.Type or '')
	local name = tostring(opt.Name or 'Option')
	if t == 'Toggle' then
		local c = sec:Toggle({Name = name, Hidden = true, Default = opt.Enabled == true, Flag = flag,
			Callback = function(s)
				local want = s and true or false
				if want ~= (opt.Enabled and true or false) then
					pcall(function() opt:Toggle() end)
				end
			end})
		table.insert(kids, c)
	elseif t == 'Slider' then
		local min = tonumber(opt.Min) or 0
		local max = tonumber(opt.Max) or 100
		if max <= min then max = min + 1 end
		local val = tonumber(opt.Value) or min
		if val < min then val = min elseif val > max then val = max end
		local dec = ((val % 1 ~= 0) or (min % 1 ~= 0) or (max % 1 ~= 0)) and 2 or 0
		local c = sec:Slider({Name = name, Hidden = true, Min = min, Max = max, Default = val, Decimal = dec,
			Ending = tostring(opt.Suffix or ''), Flag = flag,
			Callback = function(v)
				pcall(function() opt:SetValue(v) end)
			end})
		table.insert(kids, c)
	elseif t == 'Dropdown' then
		local list = (type(opt.List) == 'table' and #opt.List > 0) and opt.List or {'None'}
		local c = sec:Dropdown({Name = name, Hidden = true, Content = list, Default = opt.Value, Flag = flag,
			Callback = function(v)
				pcall(function() opt:SetValue(v) end)
			end})
		table.insert(kids, c)
	elseif t == 'TextBox' then
		local c = sec:TextBox({Name = name, Hidden = true, Default = tostring(opt.Value or ''), Flag = flag,
			Callback = function(v)
				pcall(function() opt:SetValue(v) end)
			end})
		table.insert(kids, c)
	elseif t == 'Button' then
		local fn = opt.Function
		local c = sec:Button({Name = name, Hidden = true,
			Callback = function()
				if type(fn) == 'function' then pcall(fn) end
			end})
		table.insert(kids, c)
	elseif t == 'ColorSlider' then
		local col = (typeof(opt.Value) == 'Color3') and opt.Value or Color3.new(1, 1, 1)
		local lab = sec:Label({Message = name, Hidden = true})
		table.insert(kids, lab)
		local ok, pick = pcall(function()
			return lab:ColorPicker({Default = col, Flag = flag,
				Callback = function(c)
					local h, s, v = c:ToHSV()
					pcall(function()
						if type(opt.SetValue) == 'function' then opt:SetValue(h, s, v) else opt:Color(h, s, v) end
					end)
				end})
		end)
		if ok and pick ~= nil then table.insert(kids, pick) end
	else
		local lab = sec:Label({Message = name .. ' (n/a)', Hidden = true})
		table.insert(kids, lab)
	end
end

local function renderPanel(tab, panel, tag)
	local mods = {}
	if panel and type(panel.Modules) == 'table' then
		for _, m in pairs(panel.Modules) do
			if type(m) == 'table' and m.Name then table.insert(mods, m) end
		end
	end
	table.sort(mods, function(a, b) return disp(a):lower() < disp(b):lower() end)
	local left = tab:Section({Name = tag, Side = 'Left', Fill = true})
	local right = tab:Section({Name = tag .. ' 2', Side = 'Right', Fill = true})
	local sides = {left, right}
	for i, mod in ipairs(mods) do
		local sec = sides[((i - 1) % 2) + 1]
		local flag = 'aeth_' .. tag .. '_' .. tostring(mod.Name)
		local kids = {}
		local function syncKids()
			local on = modOn(mod)
			for _, k in ipairs(kids) do
				pcall(function() k:SetVisible(on) end)
			end
		end
		local ok, t = pcall(function()
			return sec:Toggle({Name = disp(mod), Default = modOn(mod), Flag = flag,
				Callback = function(s)
					local want = s and true or false
					if want ~= modOn(mod) then
						pcall(function() mod:Toggle() end)
					end
					syncKids()
				end})
		end)
		if ok and t then
			if type(mod.Options) == 'table' then
				local names = {}
				for n in pairs(mod.Options) do table.insert(names, n) end
				table.sort(names, function(a, b) return tostring(a) < tostring(b) end)
				for _, n in ipairs(names) do
					local opt = mod.Options[n]
					if type(opt) == 'table' then
						local rok = pcall(renderOption, sec, opt, flag .. '_' .. tostring(n), kids)
						if not rok then
							pcall(function()
								table.insert(kids, sec:Label({Message = tostring(n) .. ' (n/a)', Hidden = true}))
							end)
						end
					end
				end
			end
			-- migrate any saved bind into the gamesense keybind so the old
			-- hidden system never double-toggles the module.
			local def = Enum.KeyCode.Unknown
			if type(mod.Bind) == 'table' and #mod.Bind == 1 and Enum.KeyCode[mod.Bind[1]] then
				def = Enum.KeyCode[mod.Bind[1]]
			end
			pcall(function() mod:SetBind({}) end)
			pcall(function()
				t:Keybind({Default = def, Mode = 'Toggle', UseMode = true, ChangeToggle = true,
					Flag = flag .. '_key', Callback = function() end})
			end)
			syncKids()
		end
	end
end

local kitsTab = Window:CreateTab({Icon = 'rbxassetid://8547236654'})
renderPanel(kitsTab, vape.Kits, 'Kits')
local legitTab = Window:CreateTab({Icon = 'rbxassetid://15453335745'})
renderPanel(legitTab, vape.Legit, 'Legit')
Window:SetTab(1)

-- retire the old click GUI: unbind its hotkey and hide its windows.
pcall(function() vape.Keybind = {} end)
if type(vape.Windows) == 'table' then
	for _, w in pairs(vape.Windows) do
		pcall(function() w.Visible = false end)
	end
end
for _, p in ipairs({vape.Legit, vape.Kits}) do
	if type(p) == 'table' and p.Panel then
		pcall(function() p.Panel.Visible = false end)
		pcall(function() p.Panel:SetVisible(false) end)
	end
end

GS:Init()
return true
