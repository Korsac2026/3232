-- aether gamesense GUI: main categories (Combat, Blatant, Exploits, Render,
-- Utility, World, Inventory). Kits/Legit keep their original panel windows,
-- opened from the Panels tab. Key GUI and welcome dashboard are untouched.
local vape = shared.vape
assert(type(vape) == 'table', 'aether gui: missing vape')
local fetch = assert(shared.AetherV2FetchSource, 'aether gui: missing fetch')

local src = fetch('aetherv2/lib/aether-ui.lua')
local GS = assert((loadstring or load)(src, 'aether-ui'))()
assert(type(GS) == 'table' and type(GS.Window) == 'function', 'aether gui: bad ui lib')

local CATEGORY_TABS = {
	{'Combat', 'rbxassetid://18248771514'},
	{'Blatant', 'rbxassetid://15453313321'},
	{'Exploits', 'rbxassetid://15453335745'},
	{'Render', 'rbxassetid://15453344494'},
	{'Utility', 'rbxassetid://15453349637'},
	{'World', 'rbxassetid://15453354931'},
	{'Inventory', 'rbxassetid://15453359751'},
}

local function disp(mod)
	return tostring(mod.DisplayName or mod.Name or 'Module')
end

local function modOn(mod)
	return mod.Enabled == true
end

local Window = GS:Window({Name = 'aether', CloseBind = Enum.KeyCode.Insert})

local function renderTextList(sec, opt, flag)
	sec:Label({Message = tostring(opt.Name or 'List')})
	local shown = {}
	local listCtl = nil
	local function refresh()
		if not listCtl then return end
		for _, v in ipairs(shown) do
			pcall(function() listCtl:RemoveValue(v) end)
		end
		shown = {}
		if type(opt.List) == 'table' then
			for _, v in ipairs(opt.List) do
				local s = tostring(v)
				local ok = pcall(function() listCtl:AddValue(s) end)
				if ok then table.insert(shown, s) end
			end
		end
	end
	local ok, ctl = pcall(function()
		return sec:List({Size = 110, Flag = flag, Callback = function(value)
			if value ~= nil then
				pcall(function() opt:ChangeValue(tostring(value)) end)
				refresh()
			end
		end})
	end)
	if not (ok and ctl) then return end
	listCtl = ctl
	refresh()
	pcall(function()
		sec:TextBox({Name = 'Add entry', Default = '', CheckIfPressedEnter = true, Flag = flag .. '_add',
			Callback = function(text)
				local s = tostring(text or ''):gsub('%s+', '')
				if s ~= '' then
					pcall(function() opt:ChangeValue(s) end)
					refresh()
				end
			end})
	end)
end

local function renderTargets(sec, opt, flag)
	sec:Label({Message = tostring(opt.Name or 'Targets')})
	for _, sub in ipairs({
		{Key = 'Players', Label = 'Target players'},
		{Key = 'NPCs', Label = 'Target NPCs'},
		{Key = 'Invisible', Label = 'Ignore invisible'},
		{Key = 'Walls', Label = 'Ignore behind walls'},
	}) do
		local so = opt[sub.Key]
		if type(so) == 'table' then
			pcall(function()
				sec:Toggle({Name = sub.Label, Default = so.Enabled == true, Flag = flag .. '_' .. sub.Key,
					Callback = function(s)
						local want = s and true or false
						if want ~= (so.Enabled and true or false) then
							pcall(function() so:Toggle() end)
						end
					end})
			end)
		end
	end
end

local function renderOption(sec, opt, flag)
	local t = tostring(opt.Type or '')
	local name = tostring(opt.Name or 'Option')
	if t == 'Toggle' then
		sec:Toggle({Name = name, Default = opt.Enabled == true, Flag = flag,
			Callback = function(s)
				local want = s and true or false
				if want ~= (opt.Enabled and true or false) then
					pcall(function() opt:Toggle() end)
				end
			end})
	elseif t == 'Slider' then
		local min = tonumber(opt.Min) or 0
		local max = tonumber(opt.Max) or 100
		if max <= min then max = min + 1 end
		local val = tonumber(opt.Value) or min
		if val < min then val = min elseif val > max then val = max end
		local dec = ((val % 1 ~= 0) or (min % 1 ~= 0) or (max % 1 ~= 0)) and 2 or 0
		sec:Slider({Name = name, Min = min, Max = max, Default = val, Decimal = dec,
			Ending = tostring(opt.Suffix or ''), Flag = flag,
			Callback = function(v)
				pcall(function() opt:SetValue(v) end)
			end})
	elseif t == 'Dropdown' then
		local list = (type(opt.List) == 'table' and #opt.List > 0) and opt.List or {'None'}
		sec:Dropdown({Name = name, Content = list, Default = opt.Value, Flag = flag,
			Callback = function(v)
				pcall(function() opt:SetValue(v) end)
			end})
	elseif t == 'TextBox' then
		sec:TextBox({Name = name, Default = tostring(opt.Value or ''), Flag = flag,
			Callback = function(v)
				pcall(function() opt:SetValue(v) end)
			end})
	elseif t == 'Button' then
		local fn = opt.Function
		sec:Button({Name = name,
			Callback = function()
				if type(fn) == 'function' then pcall(fn) end
			end})
	elseif t == 'ColorSlider' then
		local col = (typeof(opt.Value) == 'Color3') and opt.Value or Color3.new(1, 1, 1)
		local lab = sec:Label({Message = name})
		pcall(function()
			lab:ColorPicker({Default = col, Flag = flag,
				Callback = function(c)
					local h, s, v = c:ToHSV()
					pcall(function()
						if type(opt.SetValue) == 'function' then opt:SetValue(h, s, v) else opt:Color(h, s, v) end
					end)
				end})
		end)
	elseif t == 'TextList' then
		renderTextList(sec, opt, flag)
	elseif t == 'Targets' then
		renderTargets(sec, opt, flag)
	else
		sec:Label({Message = name .. ' (n/a)'})
	end
end

local function renderModule(sec, mod, tag)
	local flag = 'aeth_' .. tag .. '_' .. tostring(mod.Name)
	local ok, t = pcall(function()
		return sec:Toggle({Name = disp(mod), Default = modOn(mod), Flag = flag,
			Callback = function(s)
				local want = s and true or false
				if want ~= modOn(mod) then
					pcall(function() mod:Toggle() end)
				end
			end})
	end)
	if not (ok and t) then return end
	if type(mod.Options) == 'table' then
		local names = {}
		for n in pairs(mod.Options) do table.insert(names, n) end
		table.sort(names, function(a, b) return tostring(a) < tostring(b) end)
		for _, n in ipairs(names) do
			local opt = mod.Options[n]
			if type(opt) == 'table' then
				local rok = pcall(renderOption, sec, opt, flag .. '_' .. tostring(n))
				if not rok then
					pcall(function()
						sec:Label({Message = tostring(n) .. ' (n/a)'})
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
end

local function renderList(tab, mods, tag)
	table.sort(mods, function(a, b) return disp(a):lower() < disp(b):lower() end)
	local left = tab:Section({Name = tag, Side = 'Left', Fill = true})
	local right = tab:Section({Name = tag .. ' 2', Side = 'Right', Fill = true})
	local sides = {left, right}
	for i, mod in ipairs(mods) do
		pcall(renderModule, sides[((i - 1) % 2) + 1], mod, tag)
	end
end

-- group tab-category modules by their Category field
local byCategory = {}
if type(vape.Modules) == 'table' then
	for _, mod in pairs(vape.Modules) do
		if type(mod) == 'table' and mod.Name and type(mod.Category) == 'string' then
			byCategory[mod.Category] = byCategory[mod.Category] or {}
			table.insert(byCategory[mod.Category], mod)
		end
	end
end

for _, entry in ipairs(CATEGORY_TABS) do
	pcall(function()
		local name, icon = entry[1], entry[2]
		local mods = byCategory[name]
		if mods and #mods > 0 then
			local tab = Window:CreateTab({Icon = icon})
			renderList(tab, mods, name)
		end
	end)
end

-- Legit / Kits are opened from two clickable icons pinned to the top-center
-- of the screen (one per panel), outside the window so they always stay reachable.
local function panelWindow(panel)
	if type(panel) ~= 'table' then return nil end
	if typeof(panel.Panel) == 'Instance' then return panel.Panel end
	if type(panel.Modules) == 'table' then
		for _, m in pairs(panel.Modules) do
			if type(m) == 'table' and typeof(m.Panel) == 'Instance' then
				return m.Panel
			end
		end
	end
	return nil
end

local function createPanelButton(api, iconId, label, xOffset)
	local win = panelWindow(api)
	if not win then return nil end
	local host = GS.UI.ScreenGUI or (gethui and gethui())
	if not host then return nil end
	local holder = Instance.new('Frame')
	holder.Size = UDim2.new(0, 52, 0, 56)
	holder.Position = UDim2.new(0.5, xOffset, 0, 8)
	holder.BackgroundTransparency = 1
	holder.Parent = host
	local btn = Instance.new('ImageButton')
	btn.Size = UDim2.new(0, 40, 0, 40)
	btn.Position = UDim2.new(0.5, -20, 0, 0)
	btn.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
	btn.BackgroundTransparency = 0.25
	btn.BorderSizePixel = 0
	btn.Image = iconId
	btn.ImageColor3 = Color3.fromRGB(220, 220, 220)
	btn.ScaleType = Enum.ScaleType.Fit
	btn.Parent = holder
	pcall(function()
		local c = Instance.new('UICorner'); c.CornerRadius = UDim.new(0, 8); c.Parent = btn
	end)
	local labelObj = Instance.new('TextLabel')
	labelObj.Size = UDim2.new(1, 0, 0, 14)
	labelObj.Position = UDim2.new(0, 0, 0, 42)
	labelObj.BackgroundTransparency = 1
	labelObj.Text = label
	labelObj.TextColor3 = Color3.fromRGB(200, 200, 200)
	labelObj.TextSize = 12
	labelObj.Font = Enum.Font.Code
	labelObj.Parent = holder
	btn.MouseButton1Click:Connect(function()
		pcall(function() win.Visible = not win.Visible end)
	end)
	return holder
end

pcall(function()
	local hostscreen = GS.UI.ScreenGUI or (gethui and gethui())
	if hostscreen then
		createPanelButton(vape.Legit, getcustomasset('aetherv2/assets/new/legittab.png'), 'Legit', -40)
		createPanelButton(vape.Kits, getcustomasset('aetherv2/assets/new/friendstab.png'), 'Kits', 24)
	end
end)
pcall(function() Window:SetTab(1) end)

-- retire the old click GUI: unbind its hotkey, hide its category windows and the
-- leftover Uranium banner so only gamesense shows.
pcall(function() vape.Keybind = {} end)
if type(vape.Windows) == 'table' then
	for _, w in pairs(vape.Windows) do
		pcall(function() w.Visible = false end)
	end
end
pcall(function()
	if typeof(vape.gui) == 'Instance' then
		vape.gui.Visible = false
		vape.gui.Enabled = false
	end
end)

pcall(function()
	if type(GS.Init) == 'function' then GS:Init() end
end)
return true
