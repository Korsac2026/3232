-- aether gamesense GUI: main categories (Combat, Blatant, Exploits, Render,
-- Utility, World, Inventory). Kits/Legit open from two top-center icons.
-- Key GUI and welcome dashboard are untouched.
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

-- settings snapshot captured at creation time (main.lua injects option.__s).
local function s(opt, key)
	local t = opt and opt.__s and type(opt.__s) == 'table' and opt.__s or opt or {}
	return {
		Name = t.Name or key or (t.DisplayName or 'Option'),
		Min = t.Min,
		Max = t.Max,
		Suffix = t.Suffix,
		Default = t.Default,
		List = t.List,
		Tooltip = t.Tooltip,
		Function = t.Function,
		Visible = t.Visible,
	}
end

local function optionValue(opt, key)
	local t = s(opt, key)
	if opt.Type == 'Toggle' then
		return opt.Enabled == true
	elseif opt.Type == 'Slider' then
		return tonumber(opt.Value)
	elseif opt.Type == 'Dropdown' then
		return opt.Value
	elseif opt.Type == 'TextBox' then
		return opt.Value
	end
	return nil
end

-- TextList mirrors the original vape text-list: a textbox + "Add" button appends
-- entries via ChangeValue (so a module can be pointed at more objects), and each
-- entry is a toggle that enables/disables it in ListEnabled while re-running the
-- option's Function.
local function renderTextList(sec, opt, key, kids)
	if type(opt.List) ~= 'table' then return end
	table.insert(kids, sec:Label({Message = key}))
	local function runFn()
		local og = s(opt, key)
		local fn = og.Function or opt.Function
		if type(fn) == 'function' then pcall(fn, opt.List) end
	end
	local addbox = nil
	pcall(function()
		addbox = sec:TextBox({Name = 'Add ' .. key, Default = '', Flag = 'aeth_listadd_' .. key,
			Callback = function() end})
		table.insert(kids, addbox)
	end)
	pcall(function()
		table.insert(kids, sec:Button({Name = 'Add', Callback = function()
			local text = ''
			if addbox then pcall(function() text = tostring(addbox:Get() or '') end) end
			text = text:gsub('%s+', '')
			if text ~= '' then
				pcall(function() opt:ChangeValue(text) end)
				runFn()
			end
		end}))
	end)
	for _, v in ipairs(opt.List) do
		local name = tostring(v)
		table.insert(kids, sec:Toggle({Name = name,
			Default = opt.ListEnabled and table.find(opt.ListEnabled, v) ~= nil,
			Flag = 'aeth_tl_' .. key .. '_' .. name,
			Callback = function(st)
				local enabled = opt.ListEnabled and table.find(opt.ListEnabled, name) ~= nil
				if enabled and not st then
					local ind = table.find(opt.ListEnabled, name)
					if ind then table.remove(opt.ListEnabled, ind) end
					runFn()
				elseif not enabled and st then
					table.insert(opt.ListEnabled, name)
					runFn()
				end
			end}))
	end
end

local function renderTargets(sec, opt, key, kids)
	table.insert(kids, sec:Label({Message = key or 'Targets'}))
	for _, sub in ipairs({
		{Key = 'Players', Label = 'Players'},
		{Key = 'NPCs', Label = 'NPCs'},
		{Key = 'Invisible', Label = 'Ignore invisible'},
		{Key = 'Walls', Label = 'Ignore behind walls'},
	}) do
		local so = opt[sub.Key]
		if type(so) == 'table' then
			table.insert(kids, sec:Toggle({Name = sub.Label, Default = so.Enabled == true,
				Flag = 'aeth_tg_' .. key .. '_' .. sub.Key,
				Callback = function(st)
					if (so.Enabled == true) ~= (st == true) then
						pcall(function() so:Toggle() end)
					end
				end}))
		end
	end
end

local function renderOption(sec, opt, key, kids)
	local og = s(opt, key)
	local name = tostring(og.Name or key or 'Option')
	local t = tostring(opt.Type or '')
	if t == 'Toggle' then
		table.insert(kids, sec:Toggle({Name = name, Default = opt.Enabled == true, Flag = 'aeth_' .. key,
			Callback = function(st)
				if (opt.Enabled == true) ~= (st == true) then
					pcall(function() opt:Toggle() end)
				end
			end}))
	elseif t == 'Slider' then
		local min = og.Min ~= nil and tonumber(og.Min) or 0
		local max = og.Max ~= nil and tonumber(og.Max) or (min + 1)
		local val = tonumber(opt.Value) or min
		if val < min then val = min elseif val > max then val = max end
		local decimals = (og.Decimal == 100) and 2 or ((og.Decimal == 10) and 1 or 0)
		table.insert(kids, sec:Slider({Name = name, Min = min, Max = max, Default = val,
			Decimal = decimals,
			Ending = tostring(og.Suffix or ''), Flag = 'aeth_' .. key,
			Callback = function(v) pcall(function() opt:SetValue(v) end) end}))
	elseif t == 'Dropdown' then
		local list = (og.List and #og.List > 0) and og.List or {tostring(opt.Value or 'None')}
		table.insert(kids, sec:Dropdown({Name = name, Content = list, Default = opt.Value,
			Flag = 'aeth_' .. key,
			Callback = function(v) pcall(function() opt:SetValue(v) end) end}))
	elseif t == 'TextBox' then
		table.insert(kids, sec:TextBox({Name = name, Default = tostring(opt.Value or ''),
			Flag = 'aeth_' .. key,
			Callback = function(v) pcall(function() opt:SetValue(v) end) end}))
	elseif t == 'Button' then
		table.insert(kids, sec:Button({Name = name,
			Callback = function() pcall(og.Function or function() end) end}))
	elseif t == 'ColorSlider' then
		local hue = opt.Hue or 0
		local sat = opt.Sat or 0
		local val = opt.Value ~= nil and opt.Value or 1
		local col = Color3.fromHSV(hue, sat, val)
		table.insert(kids, sec:Label({Message = name}))
		local lab = sec:Label({Message = ' '})
		pcall(function()
			lab:ColorPicker({Default = col, Flag = 'aeth_' .. key,
				Callback = function(c)
					local h, st, vv = c:ToHSV()
					pcall(function()
						if type(opt.SetValue) == 'function' then opt:SetValue(h, st, vv) else opt:Color(h, st, vv) end
					end)
				end})
		end)
		table.insert(kids, lab)
	elseif t == 'TextList' then
		renderTextList(sec, opt, key, kids)
	elseif t == 'Targets' then
		renderTargets(sec, opt, key, kids)
	else
		sec:Label({Message = name .. ' (n/a)'})
	end
end

local function renderModule(sec, mod, tag)
	local flag = 'aeth_mod_' .. tag .. '_' .. tostring(mod.Name)
	local kids = {}
	local function syncKids()
		local on = modOn(mod)
		for _, k in ipairs(kids) do
			pcall(function() k:SetVisible(on) end)
		end
	end
	local ok, t = pcall(function()
		return sec:Toggle({Name = disp(mod), Default = modOn(mod), Flag = flag,
			Callback = function(st)
				if modOn(mod) ~= (st == true) then
					pcall(function() mod:Toggle() end)
				end
				syncKids()
			end})
	end)
	if not (ok and t) then return end
	if type(mod.Options) == 'table' then
		local names = {}
		for n in pairs(mod.Options) do names[#names + 1] = n end
		table.sort(names, function(a, b) return tostring(a) < tostring(b) end)
		for _, n in ipairs(names) do
			local opt = mod.Options[n]
			if type(opt) == 'table' and opt.Type ~= 'Label' then
				pcall(renderOption, sec, opt, n, kids)
			end
		end
	end
	-- migrate a saved bind into the gamesense keybind.
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

local function renderList(tab, mods, tag)
	table.sort(mods, function(a, b) return disp(a):lower() < disp(b):lower() end)
	local left = tab:Section({Name = tag, Side = 'Left', Fill = true})
	local right = tab:Section({Name = tag .. ' 2', Side = 'Right', Fill = true})
	local sides = {left, right}
	for i, mod in ipairs(mods) do
		pcall(renderModule, sides[((i - 1) % 2) + 1], mod, tag)
	end
end

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

-- Kits / Legit: reparent their panel windows to gethui (independent of the old
-- Uranium ScreenGui) and pin a clickable icon per panel at the top center.
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

local host = GS.UI.ScreenGUI or (gethui and gethui())
local function pinPanelButton(panel, iconId, label, xOff)
	local win = panelWindow(panel)
	if not win then return nil end
	if typeof(win) == 'Instance' and win.Parent and typeof(vape.gui) == 'Instance' and win:IsDescendantOf(vape.gui) then
		pcall(function() win.Parent = gethui() end)
	end
	if not host then return nil end
	local holder = Instance.new('Frame')
	holder.AnchorPoint = Vector2.new(0, 0)
	holder.Size = UDim2.new(0, 52, 0, 56)
	holder.Position = UDim2.new(0.5, xOff, 0, 6)
	holder.BackgroundTransparency = 1
	holder.Parent = host
	local btn = Instance.new('ImageButton')
	btn.AnchorPoint = Vector2.new(0.5, 0)
	btn.Size = UDim2.new(0, 40, 0, 40)
	btn.Position = UDim2.new(0.5, 0, 0, 0)
	btn.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
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

do
	local legitWin = panelWindow(vape.Legit)
	local kitsWin = panelWindow(vape.Kits)
	if host then
		if legitWin then pinPanelButton(vape.Legit, getcustomasset('aetherv2/assets/new/legittab.png'), 'Legit', -40) end
		if kitsWin then pinPanelButton(vape.Kits, getcustomasset('aetherv2/assets/new/friendstab.png'), 'Kits', 20) end
	end
end

pcall(function() Window:SetTab(1) end)

-- retire the old click GUI: unbind its hotkey and disable the Uranium ScreenGui
-- (panels were already reparented above).
pcall(function() vape.Keybind = {} end)
if type(vape.Windows) == 'table' then
	for _, w in pairs(vape.Windows) do
		pcall(function() w.Visible = false end)
	end
end
pcall(function()
	if typeof(vape.gui) == 'Instance' then
		if vape.gui:IsA('ScreenGui') then vape.gui.Enabled = false else vape.gui.Visible = false end
	end
end)

pcall(function()
	if type(GS.Init) == 'function' then GS:Init() end
end)
return true