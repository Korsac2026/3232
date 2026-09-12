local license = ... or {}
if type(license) ~= 'table' then license = {} end
if type(license) ~= 'table' and type(license) == 'string' then license = {key = license} end

-- // REAPER KEY SYSTEM (https://reaper-pryd.onrender.com) //
local REAPER_URL = 'https://reaper-pryd.onrender.com'
local REAPER_VERIFY = REAPER_URL .. '/api/client/validate'
local KEY_FILE = 'aetherv2/profiles/key.txt'

local FORCE_REFRESH = false
local REPO_OWNER = 'Korsac2026'
local REPO_NAME = '3232'
local REPO_BRANCH = 'main'

local cloneref = cloneref or function(obj)
	return obj
end

local function exists(path)
	local ok, data = pcall(readfile, path)
	return ok and type(data) == 'string' and data ~= ''
end

local function loadingParent()
	if gethui then
		local ok, gui = pcall(gethui)
		if ok and gui then return gui end
	end
	local ok, gui = pcall(function()
		return cloneref(game:GetService('CoreGui'))
	end)
	return ok and gui or nil
end

local isfile = isfile or function(file)
	local suc, res = pcall(function()
		return readfile(file)
	end)
	return suc and res ~= nil and res ~= ''
end

-- // Anti doble-ejecucion: si ya hay una carga en curso (<120s), ignora esta //
do
	local started = shared.ReaperLoadingAt
	if type(started) == 'number' and os.clock() - started < 120 then
		return
	end
	shared.ReaperLoadingAt = os.clock()
end

-- // Limpia GUIs huerfanas de ejecuciones anteriores (crash sin Uninject) //
pcall(function()
	local containers = {}
	if gethui then
		local ok, h = pcall(gethui)
		if ok and h then table.insert(containers, h) end
	end
	pcall(function() table.insert(containers, cloneref(game:GetService('CoreGui'))) end)
	pcall(function()
		local plr = cloneref(game:GetService('Players')).LocalPlayer
		if plr then table.insert(containers, plr:FindFirstChildOfClass('PlayerGui')) end
	end)
	for _, c in ipairs(containers) do
		if c then
			for _, g in ipairs(c:GetChildren()) do
				if g:IsA('ScreenGui') then
					local stale = g.Name == 'ReaperKeyAuth' or g.Name == 'UraniumLoading'
					if not stale then
						pcall(function() stale = g:GetAttribute('Uranium') == true end)
					end
					if stale and not (shared.vape and g == shared.vape.gui) then
						pcall(function() g:Destroy() end)
					end
				end
			end
		end
	end
end)

local _nativeDelFile = delfile
local function safeDelFile(file)
	if _nativeDelFile then
		pcall(_nativeDelFile, file)
		return
	end
	pcall(writefile, file, '__DELETED_MARKER__')
end

local function fileIsUsable(path)
	local ok, content = pcall(readfile, path)
	if not ok then return false end
	if not content or content == '' then return false end
	if content == '__DELETED_MARKER__' then return false end
	return true, content
end

local function cleanOldCache()
	for _, folder in ipairs({'Uranium/games', 'Uranium/guis', 'Uranium/libraries', 'Uranium/assets'}) do
		if isfolder(folder) then
			for _, f in ipairs(listfiles(folder)) do
				if f:find('loader') or f:find('init') or f:find('commit%.txt') then continue end
				if isfile(f) then
					local ok, c = pcall(readfile, f)
					if not ok or not c or c == '' or c == '__DELETED_MARKER__' then
						safeDelFile(f)
					elseif f:sub(-4) == '.lua' and not c:find('This watermark is used to delete the file if its cached', 1, true) then
						safeDelFile(f)
					end
				end
			end
		end
	end
end

if FORCE_REFRESH then
	cleanOldCache()
end

local function downloadFile(path, func)
	local usable, content = fileIsUsable(path)
	if usable and (not FORCE_REFRESH or path:find('commit%.txt') or path:find('profiles')) then
		return (func or readfile)(path)
	end
	local suc, res = pcall(function()
		local rel = select(1, path:gsub('^Uranium/', ''):gsub('^aetherv2/', ''))
		return game:HttpGet('https://raw.githubusercontent.com/'..REPO_OWNER..'/'..REPO_NAME..'/'..REPO_BRANCH..'/'..rel, true)
	end)
	if not suc or res == '404: Not Found' or type(res) ~= 'string' or #res == 0 then
		if usable then
			return (func or readfile)(path)
		end
		error(res or 'empty response')
	end
	if path:find('.lua') then
		res = '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n'..res
	end
	writefile(path, res)
	return (func or readfile)(path)
end

pcall(function()
	if not isfolder('Uranium/profiles') then makefolder('Uranium/profiles') end
	writefile('Uranium/profiles/commit.txt', REPO_BRANCH)
end)
pcall(function()
	if not isfolder('aetherv2/profiles') then makefolder('aetherv2/profiles') end
	writefile('aetherv2/profiles/commit.txt', REPO_BRANCH)
end)

-- // AUTO-UPDATE: sincroniza archivos cambiados segun el ultimo commit //
pcall(function()
	local body = game:HttpGet('https://raw.githubusercontent.com/Korsac2026/3232/main/cache.lua?t='..tostring(os.clock()), true)
	assert(type(body) == 'string' and #body > 50 and not body:find('^%s*404'), 'cache.lua missing')
	assert(loadstring(body, 'cache.lua'))()
end)

-- // REAPER KEY AUTH (bloquea la carga sin key valida) //
do
	local httpService = cloneref(game:GetService('HttpService'))
	local playersService = cloneref(game:GetService('Players'))

	local function getHwid()
		if type(gethwid) == 'function' then
			local ok, hwid = pcall(gethwid)
			if ok and type(hwid) == 'string' and hwid ~= '' then
				return hwid
			end
		end
		local userId = '0'
		pcall(function()
			local plr = playersService.LocalPlayer
			if plr then userId = tostring(plr.UserId) end
		end)
		return 'ROBLOX-' .. userId
	end

	local function httpPostJson(url, payload)
		local body = httpService:JSONEncode(payload)
		local reqFn = (syn and syn.request) or http_request or request or (fluxus and fluxus.request)
		if type(reqFn) == 'function' then
			local ok, res = pcall(reqFn, {
				Url = url,
				Method = 'POST',
				Headers = {['Content-Type'] = 'application/json'},
				Body = body
			})
			if ok and type(res) == 'table' then
				local code = tonumber(res.StatusCode or res.Status or 0) or 0
				return true, tostring(res.Body or ''), code
			end
			return false, 'request failed'
		end
		return false, 'executor sin soporte HTTP POST (se necesita syn.request / http_request)'
	end

	local function verifyKey(key, hwid)
		local lastErr = 'sin respuesta'
		for attempt = 1, 3 do
			local ok, resBody = httpPostJson(REAPER_VERIFY, {key = key, hwid = hwid})
			if ok and type(resBody) == 'string' and resBody ~= '' then
				local decodedOk, data = pcall(httpService.JSONDecode, httpService, resBody)
				if decodedOk and type(data) == 'table' then
					if data.success == true then
						return true, data
					end
					return false, (type(data.message) == 'string' and data.message or 'key invalida')
				end
				lastErr = 'respuesta invalida del servidor'
			else
				lastErr = tostring(resBody)
			end
			if attempt < 3 then task.wait(2 * attempt) end
		end
		return false, lastErr
	end

	local verifiedKey = nil
	local saveKeyChoice = false

	local function promptKey(hwid, verifyFn)
		local provided = nil
		if type(license.key) == 'string' and license.key ~= '' then provided = license.key end
		if not provided and type(license.Key) == 'string' and license.Key ~= '' then provided = license.Key end
		if not provided and type(shared.ReaperKey) == 'string' and shared.ReaperKey ~= '' then provided = shared.ReaperKey end
		if not provided and getgenv then
			pcall(function()
				local g = getgenv()
				if type(g.ReaperKey) == 'string' and g.ReaperKey ~= '' then provided = g.ReaperKey end
			end)
		end
		if not provided then
			pcall(function()
				local saved = readfile(KEY_FILE)
				if type(saved) == 'string' and saved:gsub('%s+', '') ~= '' then
					provided = saved:gsub('%s+', '')
				end
			end)
		end
		if provided then return provided end
		local parent = loadingParent()
		if not parent then
			error('[REAPER] Put your key in shared.ReaperKey before executing (no GUI available)', 0)
		end
		local done = false
		local result = nil
		local verifying = false
		local screen = Instance.new('ScreenGui')
		screen.Name = 'ReaperKeyAuth'
		screen.ResetOnSpawn = false
		screen.DisplayOrder = 2147483647
		screen.IgnoreGuiInset = true
		screen.Parent = parent
		local frame = Instance.new('Frame')
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Size = UDim2.fromOffset(440, 345)
		frame.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
		frame.BorderSizePixel = 0
		frame.Parent = screen
		local corner = Instance.new('UICorner')
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = frame
		local accent = Instance.new('Frame')
		accent.Size = UDim2.new(1, 0, 0, 3)
		accent.BackgroundColor3 = Color3.fromRGB(0, 255, 170)
		accent.BorderSizePixel = 0
		accent.Parent = frame
		local title = Instance.new('TextLabel')
		title.Position = UDim2.fromOffset(0, 12)
		title.Size = UDim2.new(1, 0, 0, 26)
		title.BackgroundTransparency = 1
		title.Text = 'REAPER KEY SYSTEM'
		title.TextColor3 = Color3.fromRGB(0, 255, 170)
		title.Font = Enum.Font.GothamBold
		title.TextSize = 18
		title.Parent = frame
		local subtitle = Instance.new('TextLabel')
		subtitle.Position = UDim2.fromOffset(0, 36)
		subtitle.Size = UDim2.new(1, 0, 0, 16)
		subtitle.BackgroundTransparency = 1
		subtitle.Text = 'reaper-pryd.onrender.com'
		subtitle.TextColor3 = Color3.fromRGB(120, 130, 140)
		subtitle.Font = Enum.Font.Code
		subtitle.TextSize = 12
		subtitle.Parent = frame
		local hwidTitle = Instance.new('TextLabel')
		hwidTitle.Position = UDim2.fromOffset(20, 60)
		hwidTitle.Size = UDim2.new(1, -40, 0, 16)
		hwidTitle.BackgroundTransparency = 1
		hwidTitle.Text = 'YOUR HWID (binds to your key)'
		hwidTitle.TextXAlignment = Enum.TextXAlignment.Left
		hwidTitle.TextColor3 = Color3.fromRGB(150, 160, 170)
		hwidTitle.Font = Enum.Font.GothamBold
		hwidTitle.TextSize = 11
		hwidTitle.Parent = frame
		local hwidBox = Instance.new('TextBox')
		hwidBox.Position = UDim2.fromOffset(20, 78)
		hwidBox.Size = UDim2.new(1, -110, 0, 32)
		hwidBox.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		hwidBox.BorderSizePixel = 0
		hwidBox.Text = tostring(hwid or '')
		hwidBox.TextXAlignment = Enum.TextXAlignment.Left
		hwidBox.TextTruncate = Enum.TextTruncate.AtEnd
		hwidBox.TextEditable = false
		hwidBox.ClearTextOnFocus = false
		hwidBox.TextColor3 = Color3.fromRGB(200, 210, 220)
		hwidBox.Font = Enum.Font.Code
		hwidBox.TextSize = 12
		hwidBox.Parent = frame
		local copyBtn = Instance.new('TextButton')
		copyBtn.Position = UDim2.new(1, -80, 0, 78)
		copyBtn.Size = UDim2.fromOffset(60, 32)
		copyBtn.BackgroundColor3 = Color3.fromRGB(20, 26, 32)
		copyBtn.BorderSizePixel = 0
		copyBtn.Text = 'COPY'
		copyBtn.TextColor3 = Color3.fromRGB(0, 255, 170)
		copyBtn.Font = Enum.Font.GothamBold
		copyBtn.TextSize = 12
		copyBtn.Parent = frame
		local box = Instance.new('TextBox')
		box.Position = UDim2.fromOffset(20, 122)
		box.Size = UDim2.new(1, -40, 0, 42)
		box.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		box.BorderSizePixel = 0
		box.TextColor3 = Color3.fromRGB(255, 255, 255)
		box.PlaceholderText = 'REAPER-XXXX-XXXX'
		box.PlaceholderColor3 = Color3.fromRGB(90, 100, 110)
		box.Text = ''
		box.Font = Enum.Font.Code
		box.TextSize = 14
		box.ClearTextOnFocus = false
		box.Parent = frame
		local status = Instance.new('TextLabel')
		status.Position = UDim2.fromOffset(20, 168)
		status.Size = UDim2.new(1, -40, 0, 20)
		status.BackgroundTransparency = 1
		status.Text = ''
		status.Font = Enum.Font.Code
		status.TextSize = 12
		status.Parent = frame
		local function setStatus(msg, ok)
			status.Text = msg or ''
			status.TextColor3 = ok and Color3.fromRGB(0, 255, 170) or Color3.fromRGB(255, 60, 60)
		end
		local btn = Instance.new('TextButton')
		btn.Position = UDim2.fromOffset(20, 196)
		btn.Size = UDim2.new(1, -40, 0, 38)
		btn.BackgroundColor3 = Color3.fromRGB(0, 255, 170)
		btn.BorderSizePixel = 0
		btn.Text = 'AUTHORIZE'
		btn.TextColor3 = Color3.fromRGB(0, 0, 0)
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 15
		btn.AutoButtonColor = true
		btn.Parent = frame
		local saveBox = false
		local saveBtn = Instance.new('TextButton')
		saveBtn.Position = UDim2.fromOffset(20, 240)
		saveBtn.Size = UDim2.new(1, -40, 0, 24)
		saveBtn.BackgroundTransparency = 1
		saveBtn.Text = '[ ] Remember key on this PC'
		saveBtn.TextXAlignment = Enum.TextXAlignment.Left
		saveBtn.TextColor3 = Color3.fromRGB(150, 160, 170)
		saveBtn.Font = Enum.Font.GothamBold
		saveBtn.TextSize = 12
		saveBtn.Parent = frame
		saveBtn.MouseButton1Click:Connect(function()
			saveBox = not saveBox
			saveBtn.Text = (saveBox and '[X] ' or '[ ] ') .. 'Remember key on this PC'
			saveBtn.TextColor3 = saveBox and Color3.fromRGB(0, 255, 170) or Color3.fromRGB(150, 160, 170)
		end)
		local foot = Instance.new('TextLabel')
		foot.Position = UDim2.new(0, 20, 1, -46)
		foot.Size = UDim2.new(1, -40, 0, 40)
		foot.BackgroundTransparency = 1
		foot.Text = 'Key is verified online with your HWID.\nIt is saved locally after approval.'
		foot.TextColor3 = Color3.fromRGB(100, 110, 120)
		foot.Font = Enum.Font.Code
		foot.TextSize = 11
		foot.Parent = frame
		copyBtn.MouseButton1Click:Connect(function()
			pcall(function()
				if setclipboard then
					setclipboard(tostring(hwid or ''))
				elseif toclipboard then
					toclipboard(tostring(hwid or ''))
				end
			end)
			setStatus('hwid copied', true)
		end)
		local function submit()
			if verifying or done then return end
			local k = box.Text:gsub('%s+', '')
			if k == '' then
				setStatus('enter a key')
				return
			end
			if type(verifyFn) ~= 'function' then
				result = k
				done = true
				return
			end
			verifying = true
			btn.Text = 'VERIFYING...'
			btn.AutoButtonColor = false
			setStatus('verifying with reaper-pryd.onrender.com...', true)
			task.spawn(function()
				local ok, info = verifyFn(k, hwid)
				if done then return end
				if ok then
					verifiedKey = k
					saveKeyChoice = saveBox
					result = k
					setStatus('key accepted', true)
					task.wait(0.4)
					done = true
				else
					setStatus(type(info) == 'string' and info or 'key rejected')
					btn.Text = 'AUTHORIZE'
					btn.AutoButtonColor = true
					verifying = false
				end
			end)
		end
		btn.MouseButton1Click:Connect(submit)
		box.FocusLost:Connect(function(enter)
			if enter then submit() end
		end)
		box:CaptureFocus()
		repeat task.wait() until done
		pcall(function() screen:Destroy() end)
		return result
	end

	local hwid = getHwid()
	local key = promptKey(hwid, verifyKey)
	if type(key) ~= 'string' or key == '' then
		shared.ReaperLoadingAt = nil
		error('[REAPER] No key entered', 0)
	end
	local valid, info
	if key == verifiedKey then
		valid, info = true, {cached = true}
	else
		valid, info = verifyKey(key, hwid)
	end
	if not valid then
		local reason = type(info) == 'string' and info or 'key rejected'
		shared.ReaperLoadingAt = nil
		error('[REAPER] key rejected: ' .. tostring(reason), 0)
	end
	shared.ReaperKey = key
	shared.ReaperHwid = hwid
	shared.ReaperAuthorized = true
	if type(info) == 'table' then
		shared.ReaperKeyInfo = info
	end
	pcall(function()
		if saveKeyChoice then
			if not isfolder('aetherv2/profiles') then makefolder('aetherv2/profiles') end
			writefile(KEY_FILE, key)
		elseif delfile then
			pcall(delfile, KEY_FILE)
		end
	end)
end

local function closeLoadingScreen()
	local screen = _G.UraniumLoadingScreen
	_G.UraniumLoadingScreen = nil
	_G.UraniumCloseLoadingScreen = nil
	_G.UraniumSetLoadingStatus = nil
	if typeof(screen) == 'Instance' then
		local tweenService = game:GetService('TweenService')
		local fade = TweenInfo.new(0.25)
		for _, object in screen:GetDescendants() do
			if object:IsA('ImageLabel') then
				pcall(function()
					tweenService:Create(object, fade, {ImageTransparency = 1}):Play()
				end)
			elseif object:IsA('Frame') then
				pcall(function()
					tweenService:Create(object, fade, {BackgroundTransparency = 1}):Play()
				end)
			end
		end
		task.delay(0.3, function()
			if screen then
				screen:Destroy()
			end
		end)
	end
end

local skipLoading = license.Closet == true
	or (exists('aetherv2/profiles/disableloading.txt') and readfile('aetherv2/profiles/disableloading.txt') == 'true')

if not skipLoading then
	local parent = loadingParent()
	if parent then
		local old = parent:FindFirstChild('UraniumLoading')
		if old then old:Destroy() end
		local screen = Instance.new('ScreenGui')
		screen.Name = 'UraniumLoading'
		screen.IgnoreGuiInset = true
		screen.ResetOnSpawn = false
		screen.DisplayOrder = 2147483647
		screen.Parent = parent

		local scrim = Instance.new('Frame')
		scrim.Name = 'Scrim'
		scrim.Size = UDim2.fromScale(1, 1)
		scrim.BackgroundColor3 = Color3.fromRGB(5, 7, 11)
		scrim.BackgroundTransparency = 0.18
		scrim.BorderSizePixel = 0
		scrim.Parent = screen

		local logo = Instance.new('TextLabel')
		logo.Name = 'Logo'
		logo.AnchorPoint = Vector2.new(0.5, 0.5)
		logo.Position = UDim2.fromScale(0.5, 0.5)
		logo.Size = UDim2.fromOffset(300, 70)
		logo.BackgroundTransparency = 1
		logo.Text = 'URANIUM'
		logo.TextColor3 = Color3.fromRGB(255, 255, 255)
		logo.TextSize = 36
		logo.FontFace = Font.fromEnum(Enum.Font.GothamBold)
		logo.TextTransparency = 1
		logo.Parent = scrim
		game:GetService('TweenService'):Create(logo, TweenInfo.new(0.4), {TextTransparency = 0}):Play()

		_G.UraniumLoadingScreen = screen
		_G.UraniumCloseLoadingScreen = closeLoadingScreen
		_G.UraniumSetLoadingStatus = function() end
		task.wait()
	end
end

-- Trae la ultima GUI solo si cambio (max 1 chequeo cada 10 min para cargar rapido)
pcall(function()
	local lastCheck = tonumber(readfile('aetherv2/profiles/gui_check.txt') or '') or 0
	if os.time() - lastCheck < 600 then return end
	local freshGui = game:HttpGet('https://raw.githubusercontent.com/Korsac2026/3232/main/guis/new.lua?t='..tostring(os.time()), true)
	if type(freshGui) == 'string' and #freshGui > 1000 and not freshGui:find('^%s*404') then
		local current = nil
		pcall(function() current = readfile('aetherv2/guis/new.lua') end)
		if type(current) == 'string' then
			current = current:gsub('^%-%-This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n', '')
		end
		if current ~= freshGui then
			if not isfolder('aetherv2/guis') then pcall(makefolder, 'aetherv2/guis') end
			pcall(writefile, 'aetherv2/guis/new.lua', '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n' .. freshGui)
		end
		pcall(writefile, 'aetherv2/profiles/gui_check.txt', tostring(os.time()))
	end
end)

local function fetchFresh(path, fallbackUrl)
	local urls = {}
	local fetch = shared.UraniumFetchSourceUrl
	if type(fetch) == 'function' then
		local fok, u = pcall(fetch, path)
		if fok and type(u) == 'string' and u ~= '' then table.insert(urls, u) end
	end
	table.insert(urls, fallbackUrl .. '?t=' .. tostring(os.time()))
	for _, url in ipairs(urls) do
		local ok, body = pcall(game.HttpGet, game, url, true)
		if ok and type(body) == 'string' and #body > 50 and not body:find('^%s*404') then
			return body
		end
	end
	return nil
end

local body = fetchFresh('main.lua', 'https://raw.githubusercontent.com/Korsac2026/3232/main/main.lua')
if body then
	writefile('aetherv2/main.lua', body)
elseif not exists('aetherv2/main.lua') then
	closeLoadingScreen()
	shared.ReaperLoadingAt = nil
	error('Could not download aetherv2/main.lua')
end

local ok, result = pcall(function()
	return loadstring(readfile('aetherv2/main.lua'), 'main')(license)
end)
shared.ReaperLoadingAt = nil
if not ok then
	closeLoadingScreen()
	error(result)
end

return result