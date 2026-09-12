local license = ... or {}
repeat task.wait() until game:IsLoaded()

if shared.vape then
	pcall(function() shared.vape:Uninject() end)
	shared.vape = nil
	pcall(function()
		if _G then _G.vape = nil end
	end)
	if getgenv then
		pcall(function() getgenv().vape = nil end)
	end
end

local REPO_OWNER = 'Korsac2026'
local REPO_NAME = '3232'
local REPO_BRANCH = 'main'

local vape
local compileString = loadstring
local queue_on_teleport = queue_on_teleport or function() end
local isfile = isfile or function(file)
	local suc, res = pcall(function()
		return readfile(file)
	end)
	return suc and res ~= nil and res ~= ''
end
local function fileIsUsable(path)
	local ok, content = pcall(readfile, path)
	if not ok then return false end
	if not content or content == '' then return false end
	if content == '__DELETED_MARKER__' then return false end
	if path:sub(-4) == '.lua' and not content:find('This watermark is used to delete the file if its cached', 1, true) then
		return false, content
	end
	return true, content
end
local cloneref = cloneref or function(obj)
	return obj
end

local playersService = cloneref(game:GetService('Players'))
local httpService = cloneref(game:GetService('HttpService'))

local SOURCE_COMMIT = REPO_BRANCH
local BEDWARS_GAME_ID = 2619619496
local BEDWARS_LOBBY_PLACE = 6872265039
local BEDWARS_MATCH_PLACE = 6872274481

local ALLOWED = {
	['guis/new.lua'] = true,
	['games/universal.lua'] = true,
	['libraries/entity.lua'] = true,
	['libraries/prediction.lua'] = true,
	['libraries/hash.lua'] = true,
	['libraries/drawing.lua'] = true,
	['libraries/base64.lua'] = true,
	['libraries/string.lua'] = true,
	['libraries/cheatenginelib.lua'] = true,
	['profiles/packages.json'] = true,
	['version.txt'] = true
}

local function relativePath(path)
	return tostring(path):gsub('^aetherv2/', ''):gsub('\\', '/')
end

local function isGameModule(path)
	return path:match('^games/%d+%.lua$') ~= nil or path:match('^games/%d+%.patch%.lua$') ~= nil
end

local function isKeptLocal(path)
	return path:sub(1, 6) == 'songs/' or path:sub(1, 8) == 'configs/'
end

local function isAsset(path)
	return path:sub(1, 7) == 'assets/'
end

local function downloadFile(path, func)
	local rel = relativePath(path)
	-- cache.lua ya sincroniza los archivos cambiados antes de llegar aquí,
	-- así que los locales usables se reutilizan para carga instantánea
	local usable = fileIsUsable(path)
	if usable then
		return (func or readfile)(path)
	end
	local suc, res = pcall(function()
		return game:HttpGet('https://raw.githubusercontent.com/'..REPO_OWNER..'/'..REPO_NAME..'/'..REPO_BRANCH..'/'..rel..'?t='..tostring(os.time()), true)
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

local function remoteExists(rel)
	local suc, res = pcall(function()
		return game:HttpGet('https://raw.githubusercontent.com/'..REPO_OWNER..'/'..REPO_NAME..'/'..REPO_BRANCH..'/'..rel, true)
	end)
	return suc and type(res) == 'string' and res ~= '404: Not Found' and not res:find('^%s*<!doctype html')
end

shared.AetherV2FetchSource = function(path)
	return downloadFile(path)
end
shared.UraniumFetchSource = shared.AetherV2FetchSource
shared.UraniumFetchSourceUrl = function(path)
	return 'https://raw.githubusercontent.com/'..REPO_OWNER..'/'..REPO_NAME..'/'..REPO_BRANCH..'/'..relativePath('aetherv2/'..tostring(path or ''))
end

local function hardenGui(source)
	source = source:gsub('fontsize%.Text = text', "fontsize.Text = tostring(text or '')")
	source = source:gsub('moduletitle%.Text = moduleapi%.DisplayName', "moduletitle.Text = tostring(moduleapi.DisplayName or moduleapi.Name or '')")
	source = source:gsub('getfontsize%(removeTags%(text%)', "getfontsize(removeTags(text or '')")
	source = source:gsub('option:Load%(v%)', 'pcall(function() option:Load(v) end)')
	source = source:gsub('object:Toggle%(true%)', 'pcall(function() object:Toggle(true) end)')
	source = source:gsub('self:UpdateTextGUI%(true%)', 'pcall(function() self:UpdateTextGUI(true) end)')
	return source
end

local function hardenBedWars(source)
	if not source:find('local function canPlace', 1, true) then
		source = source:gsub('local function getBlockInterval%(%)', [[local function canPlace()
	local placer = bedwars.BlockPlacementController and bedwars.BlockPlacementController.blockPlacer
	if not placer then return false end
	local ok, info = pcall(function()
		local selector = placer.clientManager and placer.clientManager:getBlockSelector()
		return selector and selector:getMouseInfo(0)
	end)
	return ok and type(info) == 'table' and info.placementPosition ~= nil
end

local function canSwing()
	if not (entitylib and entitylib.isAlive) then return false end
	if bedwars.SwordController and bedwars.SwordController.disableSwingState then return false end
	if bedwars.DaoController and bedwars.DaoController.chargingMaid then return false end
	return true
end

local function getBlockInterval()]], 1)
	end
	source = source:gsub('local kits, list = {}, {}', 'local kitIds, list = {}, {}', 1)
	source = source:gsub('kits%[v%.name%] = i', 'kitIds[v.name] = i', 1)
	source = source:gsub('kit = kits%[Kit%.Value%]', 'kit = kitIds[Kit.Value]', 1)
	source = source:gsub('in bedwars%.ArmorTrimType do', 'in bedwars.ArmorTrimType or {} do')
	source = source:gsub('in bedwars%.ArmorTrimColor do', 'in bedwars.ArmorTrimColor or {} do')
	source = source:gsub('in bedwars%.ArmorTrimEffectType do', 'in bedwars.ArmorTrimEffectType or {} do')
	source = source:gsub('in bedwars%.ItemSkinType do', 'in bedwars.ItemSkinType or {} do')
	source = source:gsub('return patchUraniumRuntime%(UraniumMatchRuntime, context%)', 'return patchUraniumRuntime(UraniumMatchRuntime, UraniumRuntimeContext or context)')
	return source
end

local function runChunk(source, chunkName, ...)
	source = tostring(source or '')
	if chunkName == 'gui' then
		source = hardenGui(source)
	elseif tostring(chunkName):match('^%d+$') then
		source = hardenBedWars(source)
	end
	local chunk, err = compileString(source, chunkName)
	if not chunk then
		error(chunkName..' compile failed: '..tostring(err), 0)
	end
	local ok, result = xpcall(function(...)
		return chunk(...)
	end, debug.traceback, ...)
	if not ok then
		error(chunkName..': '..tostring(result), 0)
	end
	return result
end

local function loadPremiumModules()
	if shared.UraniumPremiumAuthorized ~= true then return end
	local fetchSource = shared.UraniumPremiumFetchSource
	local fetchTree = shared.UraniumPremiumFetchTree
	if type(fetchSource) ~= 'function' or type(fetchTree) ~= 'function' then return end
	shared.UraniumPremiumModules = type(shared.UraniumPremiumModules) == 'table' and shared.UraniumPremiumModules or {}

	local ok, treeBody = pcall(fetchTree)
	if not ok or type(treeBody) ~= 'string' then
		warn('[Uranium] Premium modules were unavailable; continuing with normal modules')
		return
	end
	local decoded, tree = pcall(httpService.JSONDecode, httpService, treeBody)
	if not decoded or type(tree) ~= 'table' or type(tree.tree) ~= 'table' then
		warn('[Uranium] Premium module list was invalid; continuing with normal modules')
		return
	end

	local placeId = tostring(vape.Place or game.PlaceId)
	local function collectModules(prefix, destination)
		for _, entry in ipairs(tree.tree) do
			local path = type(entry) == 'table' and entry.path or nil
			if type(entry) == 'table' and entry.type == 'blob' and type(path) == 'string'
				and path:sub(1, #prefix) == prefix and path:sub(-4) == '.lua' then
				local category = path:sub(#prefix + 1):match('^([^/]+)/')
				if category and category ~= '' then
					table.insert(destination, {Path = path, Category = category})
				end
			end
		end
		table.sort(destination, function(left, right) return left.Path < right.Path end)
	end

	local modules = {}
	collectModules('games/universal/', modules)
	collectModules('games/'..placeId..'/', modules)
	for _, module in ipairs(modules) do
		local received, source = pcall(fetchSource, module.Path)
		if received and type(source) == 'string' and #source >= 8 then
			local chunk, compileError = compileString(source, 'premium/'..module.Path)
			if chunk then
				local categoryName, categoryApi = module.Category, nil
				for name, category in pairs(vape.Categories or {}) do
					if tostring(name):lower() == module.Category:lower() then
						categoryName, categoryApi = name, category
						break
					end
				end
				local context = {
					Category = categoryName,
					CategoryApi = categoryApi,
					Path = module.Path,
					Scope = module.Path:sub(1, #'games/universal/') == 'games/universal/' and 'universal' or 'game'
				}
				local snapshot = {}
				for name, loadedModule in pairs(vape.Modules or {}) do
					snapshot[name] = loadedModule
				end
				local ran, result = xpcall(function()
					return chunk(vape, license, context)
				end, debug.traceback)
				if ran and type(result) == 'function' then
					ran, result = xpcall(function()
						return result(vape, license, context)
					end, debug.traceback)
				end
				if ran then
					for name, loadedModule in pairs(vape.Modules or {}) do
						if snapshot[name] ~= loadedModule then
							shared.UraniumPremiumModules[tostring(name):lower():gsub('[%s_%-%./]+', '')] = true
						end
					end
				else
					warn('[Uranium] Premium module '..module.Path..' failed: '..tostring(result))
				end
			else
				warn('[Uranium] Premium module '..module.Path..' did not compile: '..tostring(compileError))
			end
		else
			warn('[Uranium] Premium module '..module.Path..' could not be fetched')
		end
	end
end

local function finishLoading()
	vape.Init = nil
	local loaded, loadError = pcall(function()
		vape:Load()
	end)
	if not loaded then
		warn('[Uranium] Config load failed: '..tostring(loadError))
	end
	if shared.UraniumPremiumAuthorized and not license.Closet then
		pcall(function()
			vape:CreateNotification('Uranium Premium', 'Premium key validated', 6, 'info')
		end)
	end
	if _G.UraniumCloseLoadingScreen then
		pcall(_G.UraniumCloseLoadingScreen)
	end

	local teleportedServers
	vape:Clean(playersService.LocalPlayer.OnTeleport:Connect(function()
		if (not teleportedServers) and (not shared.VapeIndependent) then
			teleportedServers = true
			local teleportScript = ([[
				shared.vapereload = true
				if shared.VapeDeveloper then
					loadstring(readfile('Uranium/init.lua'), 'loader')()
				else
					loadstring(game:HttpGet('https://raw.githubusercontent.com/%s/%s/%s/init.lua', true), 'loader')()
				end
			]]):format(REPO_OWNER, REPO_NAME, REPO_BRANCH)
			if shared.VapeDeveloper then
				teleportScript = 'shared.VapeDeveloper = true\n'..teleportScript
			end
			if shared.VapeCustomProfile then
				teleportScript = 'shared.VapeCustomProfile = "'..shared.VapeCustomProfile..'"\n'..teleportScript
			end
			vape:Save()
			queue_on_teleport(teleportScript)
		end
		teleportedServers = true
		local teleportScript = [[
			shared.vapereload = true
			loadstring(game:HttpGet('https://raw.githubusercontent.com/Korsac2026/3232/main/init.lua?t='..tostring(os.clock()), true), 'init.lua')(_scriptconfig)
		]]
		local teleportConfig = httpService:JSONEncode(license)
		teleportConfig = teleportConfig:gsub('":true', '=true'):gsub('{"', '{')
		teleportConfig = teleportConfig:gsub(',"', ','):gsub('":', '=')
		teleportConfig = teleportConfig:gsub('%[', '{'):gsub('%]', '}')
		teleportScript = teleportScript:gsub('_scriptconfig', teleportConfig)
		if shared.VapeDeveloper then
			teleportScript = 'shared.VapeDeveloper = true\n'..teleportScript
		end
		if shared.VapeCustomProfile then
			teleportScript = 'shared.VapeCustomProfile = "'..shared.VapeCustomProfile..'"\n'..teleportScript
		end
		pcall(function() vape:Save() end)
		queue_on_teleport(teleportScript)
	end))

	if not shared.vapereload and not license.Closet then
		local bind = table.concat(vape.Keybind or {'RightShift'}, ' + '):upper()
		pcall(function()
			vape:CreateNotification(
				'Finished Loading',
				(vape.VapeButton and 'Press the button in the top right' or 'Press '..bind)..' to open GUI',
				5
			)
		end)
	end
end

for _, folder in {
	'aetherv2',
	'aetherv2/profiles',
	'aetherv2/guis',
	'aetherv2/games',
	'aetherv2/libraries',
	'aetherv2/assets',
	'aetherv2/assets/new',
	'aetherv2/songs',
	'aetherv2/songs/spotify'
} do
	if not isfolder(folder) then
		pcall(makefolder, folder)
	end
end

if not isfile('aetherv2/profiles/gui.txt') then
	writefile('aetherv2/profiles/gui.txt', 'new')
end

if not isfile('aetherv2/profiles/commit.txt') then
	pcall(writefile, 'aetherv2/profiles/commit.txt', REPO_BRANCH)
end

vape = runChunk(downloadFile('aetherv2/guis/new.lua'), 'gui', license)
shared.vape = vape
if _G then _G.vape = vape end
if getgenv then getgenv().vape = vape end
task.wait()

if not shared.VapeIndependent then
	runChunk(downloadFile('aetherv2/games/universal.lua'), 'universal', license)
	task.wait()
	local placePath = 'aetherv2/games/'..game.PlaceId..'.lua'
	local ok = pcall(function()
		runChunk(downloadFile(placePath), tostring(game.PlaceId), license)
	end)
	if not ok then
		warn('[Uranium] No game module for '..tostring(game.PlaceId))
	end
	task.wait()
	local patchPath = 'aetherv2/games/'..game.PlaceId..'.patch.lua'
	pcall(function()
		runChunk(downloadFile(patchPath), tostring(game.PlaceId)..'-patch', license)
	end)
	loadPremiumModules()
	finishLoading()
else
	vape.Init = finishLoading
	return vape
end