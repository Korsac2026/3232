local license = ... or {}
local vape = shared.vape
if not vape then return end

local env = getgenv and getgenv() or _G
local entitylib = vape.Libraries and vape.Libraries.entity
local store = (env and env.store) or shared.store
local bedwars = (env and env.bedwars) or shared.bedwars

if env then
	env.canPlace = env.canPlace or function()
		if not (bedwars and store and store.hand and store.hand.toolType == 'block') then
			return false
		end
		local placer = bedwars.BlockPlacementController and bedwars.BlockPlacementController.blockPlacer
		if not placer then return false end
		local ok, info = pcall(function()
			local selector = placer.clientManager and placer.clientManager:getBlockSelector()
			return selector and selector:getMouseInfo(0)
		end)
		return ok and type(info) == 'table' and info.placementPosition ~= nil
	end
	env.canSwing = env.canSwing or function()
		if not (entitylib and entitylib.isAlive and store and store.hand and store.hand.toolType == 'sword') then
			return false
		end
		if bedwars and bedwars.SwordController and bedwars.SwordController.disableSwingState then
			return false
		end
		if bedwars and bedwars.DaoController and bedwars.DaoController.chargingMaid then
			return false
		end
		return true
	end
end

local Runtime = shared.AetherBedWarsRuntime
if type(Runtime) == 'table' and type(Runtime.Context) == 'table' and type(Runtime.InstallLongJumpJadeHook) == 'function' then
	pcall(Runtime.InstallLongJumpJadeHook, Runtime, vape.Modules and vape.Modules.LongJump)
end
-- Uranium patch addition: fixed AutoClicker (upstream v3.8.2). Safe to re-run every boot.
local g = getgenv()
if g.vape == nil then g.vape = shared.vape end
local lplr = game:GetService('Players').LocalPlayer
local rs = game:GetService('ReplicatedStorage')
if g.lplr == nil then g.lplr = lplr end
if g.inputService == nil then g.inputService = game:GetService('UserInputService') end
if g.store == nil then g.store = (shared and shared.store) or (function() local ok, s = pcall(function() return require(lplr.PlayerScripts.TS.ui.store).ClientStore end) return ok and s or nil end)() end
if g.entitylib == nil then g.entitylib = (function() local ok, src = pcall(readfile, 'aetherv2/libraries/entity.lua') if not ok or type(src) ~= 'string' then return nil end local fn = loadstring(src, 'UraniumPatch_entity') if not fn then return nil end local ok2, lib = pcall(fn) return ok2 and lib or nil end)() end
if g.run == nil then g.run = function(f) local ok, err = xpcall(f, (debug and debug.traceback) or tostring) if not ok then warn('[UraniumPatch] skipped: ' .. tostring(err)) end end end
if g.bedwars == nil then local bw = {} local Knit = (function() local ok, k = pcall(function() return require(rs['rbxts_include']['node_modules']['@easy-games'].knit.src).KnitClient end) return ok and k or nil end)() local C = Knit and Knit.Controllers or {} bw.SwordController = C.SwordController bw.BlockPlacementController = C.BlockPlacementController bw.BlockCpsController = C.BlockCpsController bw.KeybindLoadController = C.KeybindLoadController bw.ItemMeta = (function() local ok, m = pcall(function() return require(rs.TS.item['item-meta']) end) return (ok and m and m.items) or nil end)() bw.SharedConstants = (function() local ok, m = pcall(function() return require(rs.TS['shared-constants']) end) return (ok and m) or {} end)() bw.AppController = (function() local ok, fw = pcall(function() return require(rs['rbxts_include']['node_modules']['@flamework'].core.out).Flamework end) if not ok or type(fw.resolveDependency) ~= 'function' then return nil end local ok2, c = pcall(fw.resolveDependency, '@easy-games/game-core:client/controllers/app-controller@AppController') return (ok2 and c) or nil end)() bw.UILayers = (function() local ok, m = pcall(function() return require(rs['rbxts_include']['node_modules']['@easy-games']['game-core'].out) end) return (ok and m and m.UILayers) or nil end)() g.bedwars = bw end
task.spawn(function() pcall(function() g.vape:Remove('AutoClicker') end) end)
task.wait(2)
run(function()
	local AutoClicker
	local Attack
	local CPS
	local Place
	local Wool
	local BlockCPS = {}
	-- Every loop the module starts carries the number it was started with. A key release, a new
	-- press and a module toggle all just increment this, which retires whichever loop is running
	-- without ever cancelling a thread that has already finished.
	local runId = 0

	local function isCasting()
		local casting = lplr:GetAttribute('IsCasting')
		return casting and casting ~= 0 and casting ~= ''
	end

	local function canSwing()
		if type(bedwars.SwordController.getSwordSwingDisabled) ~= 'function' or bedwars.SwordController:getSwordSwingDisabled() or isCasting() then
			return false
		end

		local itemmeta = store.hand and store.hand.tool and bedwars.ItemMeta[store.hand.tool.Name]
		return itemmeta ~= nil and itemmeta.sword ~= nil and itemmeta.sword.chargedAttack == nil
	end

	local function canPlace()
		local controller = bedwars.BlockPlacementController
		return controller ~= nil and not controller.disabled and not isCasting()
	end

	local function getWoolBaseCps()
		if Wool.Enabled and store.hand and store.hand.tool then
			return store.hand.tool.Name:find('wool_') ~= nil
		end
		return not Wool.Enabled
	end

	local function placeInterval()
		local cps = BlockCPS:GetRandomValue()
		return math.max(1 / math.max(cps, 0.001), 1 / (bedwars.SharedConstants.BLOCK_PLACE_CPS or 12))
	end

	local function clickInterval()
		return 1 / math.max(CPS:GetRandomValue(), 0.001)
	end

	local function waitInterval()
		return store.hand.toolType == 'block' and placeInterval() or clickInterval()
	end

	local function canClickBlock()
		if store.hand.toolType ~= 'block' or not Place.Enabled then return false end
		if not getWoolBaseCps() then return false end
		local blockPlacer = bedwars.BlockPlacementController.blockPlacer
		if not blockPlacer or not canPlace() then return false end
		return (workspace:GetServerTimeNow() - (bedwars.BlockCpsController.lastPlaceTimestamp or 0)) >= ((1 / (bedwars.SharedConstants.BLOCK_PLACE_CPS or 12)) * 0.5)
	end

	-- The placer's own bridge helper, driven the way the touch controls drive it. A placer this
	-- version of the game does not have, or a knockback controller that has not been built yet,
	-- is not worth an error: the fallback simply does not run.
	local function callAutoBridge(blockPlacer)
		task.spawn(function()
			pcall(function()
				local controller = bedwars.KnockbackController
				local sinceKnockback = controller and workspace:GetServerTimeNow() - controller:getLastKnockbackTime() or 0
				blockPlacer:autoBridge(sinceKnockback >= 0.2)
			end)
		end)
	end

	-- The crosshair is the only thing asked for normally: the game decides what is under it and
	-- whether a block fits there, so its answer is used exactly as before.
	local function placeThroughCrosshair(blockPlacer)
		local selector = blockPlacer.clientManager and blockPlacer.clientManager:getBlockSelector()
		local mouseinfo = selector and selector:getMouseInfo(0)
		if mouseinfo and mouseinfo.placementPosition == mouseinfo.placementPosition then
			task.spawn(blockPlacer.placeBlock, blockPlacer, mouseinfo.placementPosition, mouseinfo)
			return true
		end
		return false
	end

	--[[	Aiming almost straight down is the usual bridging pose and the one case the crosshair cannot
		answer: the ray lands on the block under your own feet, whose only free cell is the one you
		are standing in, so the selector returns nothing and the click silently does nothing. The
		game's own bridge helper places for exactly that pose, so it is used as a fallback - but only
		when the crosshair offered nothing and you are actually walking, so standing still and aiming
		normally behave as they always did.
	]]
	local function placeSafelyDownwards(blockPlacer)
		if type(blockPlacer.autoBridge) ~= 'function' then return end
		local humanoid = entitylib.isAlive and entitylib.character and entitylib.character.Humanoid
		if not humanoid or humanoid.MoveDirection.Magnitude <= 0.1 then return end
		callAutoBridge(blockPlacer)
	end

	local function placeBlock()
		local blockPlacer = bedwars.BlockPlacementController.blockPlacer
		if not blockPlacer then return end

		if inputService.TouchEnabled and type(blockPlacer.autoBridge) == 'function' then
			callAutoBridge(blockPlacer)
			return
		end

		if placeThroughCrosshair(blockPlacer) then return end
		placeSafelyDownwards(blockPlacer)
	end

	local function clickOnce()
		-- The menu layer is checked here rather than around the call, so the loop's single guard
		-- covers it too: a controller that is not up yet is a click to skip, not a dead loop.
		if bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN) then return end
		if store.hand.toolType == 'block' then
			if canClickBlock() then
				placeBlock()
			end
		elseif Attack.Enabled and store.hand.toolType == 'sword' then
			if inputService.TouchEnabled then
				local controller = bedwars.SwordController
				if controller.mobileSwingPressed then
					controller:mobileSwingPressed()
				end
			elseif canSwing() and not bedwars.SwordController.disableSwingState then
				bedwars.SwordController:swingSwordAtMouse(0.39)
			end
		end
	end

	local function stopClicking()
		runId += 1
	end

	local function AutoClick()
		stopClicking()
		local mine = runId

		task.spawn(function()
			-- One failed click - a controller mid-reload, a placer that has just been replaced -
			-- used to take the whole loop down with it, leaving the mouse held and nothing
			-- happening until the button was released and pressed again. Reported once per press
			-- and then carried on.
			local warned = false
			task.wait(waitInterval())
			while runId == mine and AutoClicker.Enabled do
				local ok, err = pcall(clickOnce)
				if not ok and not warned then
					warned = true
					warn('[AetherV2] AutoClicker: '..tostring(err))
				end
				task.wait(waitInterval())
			end
		end)
	end

	local function isAttack(input)
		local keybinds = bedwars.KeybindLoadController and bedwars.KeybindLoadController:getKeybinds()
		local keyboard = keybinds and keybinds.keyboard and keybinds.keyboard.controlActions.Attack or Enum.UserInputType.MouseButton1
		local gamepad = keybinds and keybinds.gamepad and keybinds.gamepad.controlActions.Attack or Enum.KeyCode.ButtonR2
		return input.UserInputType == keyboard or input.KeyCode == keyboard or input.KeyCode == gamepad
	end

	AutoClicker = vape.Categories.Combat:CreateModule({
		Name = 'AutoClicker',
		Function = function(callback)
			if callback then
				AutoClicker:Clean(inputService.InputBegan:Connect(function(input)
					if isAttack(input) then
						AutoClick()
					end
				end))

				AutoClicker:Clean(inputService.InputEnded:Connect(function(input)
					if isAttack(input) then
						stopClicking()
					end
				end))

				if inputService.TouchEnabled then
					local hooked = {}
					local function hookButton(button)
						if hooked[button] or not button:IsA('GuiButton') or not tonumber(button.Name) then return end
						hooked[button] = true
						AutoClicker:Clean(button.MouseButton1Down:Connect(AutoClick))
						AutoClicker:Clean(button.MouseButton1Up:Connect(stopClicking))
					end

					task.spawn(function()
						local mobileUI = lplr.PlayerGui:WaitForChild('MobileUI', 20)
						if not mobileUI or not AutoClicker.Enabled then return end

						for _, v in mobileUI:GetChildren() do
							hookButton(v)
						end
						AutoClicker:Clean(mobileUI.ChildAdded:Connect(hookButton))
					end)
				end
			else
				stopClicking()
			end
		end,
		Tooltip = 'Hold attack button to automatically click'
	})

	Attack = AutoClicker:CreateToggle({
		Name = 'Attack',
		Function = function(callback)
			if CPS and CPS.Object then
				CPS.Object.Visible = callback
			end
		end,
		Default = true,
		Tooltip = 'Swings your sword while the attack button is held'
	})
	CPS = AutoClicker:CreateTwoSlider({
		Name = 'CPS',
		Min = 1,
		Max = 9,
		DefaultMin = 7,
		DefaultMax = 7
	})
	Place = AutoClicker:CreateToggle({
		Name = 'Place Blocks',
		Function = function(callback)
			if BlockCPS.Object then
				BlockCPS.Object.Visible = callback
			end

			if Wool then
				Wool.Object.Visible = callback
			end
		end,
		Default = true
	})
	Wool = AutoClicker:CreateToggle({Name = 'Wool only', Tooltip = 'Only clicks when you are holding wool', Darker = true})
	BlockCPS = AutoClicker:CreateTwoSlider({
		Name = 'Block CPS',
		Min = 1,
		Max = 20,
		DefaultMin = 20,
		DefaultMax = 20,
		Darker = true
	})
end)

if shared.vape.Modules == nil or shared.vape.Modules.AutoClicker == nil then warn('[UraniumPatch] AutoClicker did not register') else print('[UraniumPatch] AutoClicker fix active') end
-- UraniumFix_AutoClicker v2 — env + upstream fixed AutoClicker (AetherV2 v3.8.2).
local g = getgenv()
g.vape = shared.vape
local lplr = game:GetService('Players').LocalPlayer
local rs = game:GetService('ReplicatedStorage')
if g.lplr == nil then g.lplr = lplr end
if g.inputService == nil then g.inputService = game:GetService('UserInputService') end
if g.store == nil then g.store = (shared and shared.store) or (function() local ok, s = pcall(function() return require(lplr.PlayerScripts.TS.ui.store).ClientStore end) return ok and s or nil end)() end
if g.entitylib == nil then g.entitylib = (function() local ok, src = pcall(readfile, 'aetherv2/libraries/entity.lua') if not ok or type(src) ~= 'string' then return nil end local fn = loadstring(src, 'UraniumFix_entity') if not fn then return nil end local ok2, lib = pcall(fn) return ok2 and lib or nil end)() end
if g.run == nil then g.run = function(f) local ok, err = xpcall(f, (debug and debug.traceback) or tostring) if not ok then warn('[UraniumFix] skipped: ' .. tostring(err)) end end end
if g.bedwars == nil then g.bedwars = {} end
local bw = g.bedwars
local Knit = (function() local ok, k = pcall(function() return require(rs['rbxts_include']['node_modules']['@easy-games'].knit.src).KnitClient end) return ok and k or nil end)()
local C = Knit and Knit.Controllers or {}
if bw.SwordController == nil then bw.SwordController = C.SwordController end
if bw.BlockPlacementController == nil then bw.BlockPlacementController = C.BlockPlacementController end
if bw.BlockCpsController == nil then bw.BlockCpsController = C.BlockCpsController end
if bw.KeybindLoadController == nil then bw.KeybindLoadController = C.KeybindLoadController end
if bw.ItemMeta == nil then bw.ItemMeta = (function() local ok, m = pcall(function() return require(rs.TS.item['item-meta']) end) return (ok and m and m.items) or nil end)() end
if bw.SharedConstants == nil then bw.SharedConstants = (function() local ok, m = pcall(function() return require(rs.TS['shared-constants']) end) return (ok and m) or {} end)() end
if bw.AppController == nil then bw.AppController = (function() local ok, fw = pcall(function() return require(rs['rbxts_include']['node_modules']['@flamework'].core.out).Flamework end) if not ok or type(fw.resolveDependency) ~= 'function' then return nil end local ok2, c = pcall(fw.resolveDependency, '@easy-games/game-core:client/controllers/app-controller@AppController') return (ok2 and c) or nil end)() end
if bw.UILayers == nil then bw.UILayers = (function() local ok, m = pcall(function() return require(rs['rbxts_include']['node_modules']['@easy-games']['game-core'].out) end) return (ok and m and m.UILayers) or nil end)() end
print('[FIX] env-bedwars sword=' .. tostring(bw.SwordController ~= nil) .. ' place=' .. tostring(bw.BlockPlacementController ~= nil) .. ' cps=' .. tostring(bw.BlockCpsController ~= nil) .. ' keys=' .. tostring(bw.KeybindLoadController ~= nil) .. ' meta=' .. tostring(bw.ItemMeta ~= nil))
task.spawn(function() pcall(function() g.vape:Remove('AutoClicker') end) end)
task.wait(2)
run(function()
	local AutoClicker
	local Attack
	local CPS
	local Place
	local Wool
	local BlockCPS = {}
	-- Every loop the module starts carries the number it was started with. A key release, a new
	-- press and a module toggle all just increment this, which retires whichever loop is running
	-- without ever cancelling a thread that has already finished.
	local runId = 0

	local function isCasting()
		local casting = lplr:GetAttribute('IsCasting')
		return casting and casting ~= 0 and casting ~= ''
	end

	local function canSwing()
		if type(bedwars.SwordController.getSwordSwingDisabled) ~= 'function' or bedwars.SwordController:getSwordSwingDisabled() or isCasting() then
			return false
		end

		local itemmeta = store.hand and store.hand.tool and bedwars.ItemMeta[store.hand.tool.Name]
		return itemmeta ~= nil and itemmeta.sword ~= nil and itemmeta.sword.chargedAttack == nil
	end

	local function canPlace()
		local controller = bedwars.BlockPlacementController
		return controller ~= nil and not controller.disabled and not isCasting()
	end

	local function getWoolBaseCps()
		if Wool.Enabled and store.hand and store.hand.tool then
			return store.hand.tool.Name:find('wool_') ~= nil
		end
		return not Wool.Enabled
	end

	local function placeInterval()
		local cps = BlockCPS:GetRandomValue()
		return math.max(1 / math.max(cps, 0.001), 1 / (bedwars.SharedConstants.BLOCK_PLACE_CPS or 12))
	end

	local function clickInterval()
		return 1 / math.max(CPS:GetRandomValue(), 0.001)
	end

	local function waitInterval()
		return store.hand.toolType == 'block' and placeInterval() or clickInterval()
	end

	local function canClickBlock()
		if store.hand.toolType ~= 'block' or not Place.Enabled then return false end
		if not getWoolBaseCps() then return false end
		local blockPlacer = bedwars.BlockPlacementController.blockPlacer
		if not blockPlacer or not canPlace() then return false end
		return (workspace:GetServerTimeNow() - (bedwars.BlockCpsController.lastPlaceTimestamp or 0)) >= ((1 / (bedwars.SharedConstants.BLOCK_PLACE_CPS or 12)) * 0.5)
	end

	-- The placer's own bridge helper, driven the way the touch controls drive it. A placer this
	-- version of the game does not have, or a knockback controller that has not been built yet,
	-- is not worth an error: the fallback simply does not run.
	local function callAutoBridge(blockPlacer)
		task.spawn(function()
			pcall(function()
				local controller = bedwars.KnockbackController
				local sinceKnockback = controller and workspace:GetServerTimeNow() - controller:getLastKnockbackTime() or 0
				blockPlacer:autoBridge(sinceKnockback >= 0.2)
			end)
		end)
	end

	-- The crosshair is the only thing asked for normally: the game decides what is under it and
	-- whether a block fits there, so its answer is used exactly as before.
	local function placeThroughCrosshair(blockPlacer)
		local selector = blockPlacer.clientManager and blockPlacer.clientManager:getBlockSelector()
		local mouseinfo = selector and selector:getMouseInfo(0)
		if mouseinfo and mouseinfo.placementPosition == mouseinfo.placementPosition then
			task.spawn(blockPlacer.placeBlock, blockPlacer, mouseinfo.placementPosition, mouseinfo)
			return true
		end
		return false
	end

	--[[	Aiming almost straight down is the usual bridging pose and the one case the crosshair cannot
		answer: the ray lands on the block under your own feet, whose only free cell is the one you
		are standing in, so the selector returns nothing and the click silently does nothing. The
		game's own bridge helper places for exactly that pose, so it is used as a fallback - but only
		when the crosshair offered nothing and you are actually walking, so standing still and aiming
		normally behave as they always did.
	]]
	local function placeSafelyDownwards(blockPlacer)
		if type(blockPlacer.autoBridge) ~= 'function' then return end
		local humanoid = entitylib.isAlive and entitylib.character and entitylib.character.Humanoid
		if not humanoid or humanoid.MoveDirection.Magnitude <= 0.1 then return end
		callAutoBridge(blockPlacer)
	end

	local function placeBlock()
		local blockPlacer = bedwars.BlockPlacementController.blockPlacer
		if not blockPlacer then return end

		if inputService.TouchEnabled and type(blockPlacer.autoBridge) == 'function' then
			callAutoBridge(blockPlacer)
			return
		end

		if placeThroughCrosshair(blockPlacer) then return end
		placeSafelyDownwards(blockPlacer)
	end

	local function clickOnce()
		-- The menu layer is checked here rather than around the call, so the loop's single guard
		-- covers it too: a controller that is not up yet is a click to skip, not a dead loop.
		if bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN) then return end
		if store.hand.toolType == 'block' then
			if canClickBlock() then
				placeBlock()
			end
		elseif Attack.Enabled and store.hand.toolType == 'sword' then
			if inputService.TouchEnabled then
				local controller = bedwars.SwordController
				if controller.mobileSwingPressed then
					controller:mobileSwingPressed()
				end
			elseif canSwing() and not bedwars.SwordController.disableSwingState then
				bedwars.SwordController:swingSwordAtMouse(0.39)
			end
		end
	end

	local function stopClicking()
		runId += 1
	end

	local function AutoClick()
		stopClicking()
		local mine = runId

		task.spawn(function()
			-- One failed click - a controller mid-reload, a placer that has just been replaced -
			-- used to take the whole loop down with it, leaving the mouse held and nothing
			-- happening until the button was released and pressed again. Reported once per press
			-- and then carried on.
			local warned = false
			task.wait(waitInterval())
			while runId == mine and AutoClicker.Enabled do
				local ok, err = pcall(clickOnce)
				if not ok and not warned then
					warned = true
					warn('[AetherV2] AutoClicker: '..tostring(err))
				end
				task.wait(waitInterval())
			end
		end)
	end

	local function isAttack(input)
		local keybinds = bedwars.KeybindLoadController and bedwars.KeybindLoadController:getKeybinds()
		local keyboard = keybinds and keybinds.keyboard and keybinds.keyboard.controlActions.Attack or Enum.UserInputType.MouseButton1
		local gamepad = keybinds and keybinds.gamepad and keybinds.gamepad.controlActions.Attack or Enum.KeyCode.ButtonR2
		return input.UserInputType == keyboard or input.KeyCode == keyboard or input.KeyCode == gamepad
	end

	AutoClicker = vape.Categories.Combat:CreateModule({
		Name = 'AutoClicker',
		Function = function(callback)
			if callback then
				AutoClicker:Clean(inputService.InputBegan:Connect(function(input)
					if isAttack(input) then
						AutoClick()
					end
				end))

				AutoClicker:Clean(inputService.InputEnded:Connect(function(input)
					if isAttack(input) then
						stopClicking()
					end
				end))

				if inputService.TouchEnabled then
					local hooked = {}
					local function hookButton(button)
						if hooked[button] or not button:IsA('GuiButton') or not tonumber(button.Name) then return end
						hooked[button] = true
						AutoClicker:Clean(button.MouseButton1Down:Connect(AutoClick))
						AutoClicker:Clean(button.MouseButton1Up:Connect(stopClicking))
					end

					task.spawn(function()
						local mobileUI = lplr.PlayerGui:WaitForChild('MobileUI', 20)
						if not mobileUI or not AutoClicker.Enabled then return end

						for _, v in mobileUI:GetChildren() do
							hookButton(v)
						end
						AutoClicker:Clean(mobileUI.ChildAdded:Connect(hookButton))
					end)
				end
			else
				stopClicking()
			end
		end,
		Tooltip = 'Hold attack button to automatically click'
	})

	Attack = AutoClicker:CreateToggle({
		Name = 'Attack',
		Function = function(callback)
			if CPS and CPS.Object then
				CPS.Object.Visible = callback
			end
		end,
		Default = true,
		Tooltip = 'Swings your sword while the attack button is held'
	})
	CPS = AutoClicker:CreateTwoSlider({
		Name = 'CPS',
		Min = 1,
		Max = 9,
		DefaultMin = 7,
		DefaultMax = 7
	})
	Place = AutoClicker:CreateToggle({
		Name = 'Place Blocks',
		Function = function(callback)
			if BlockCPS.Object then
				BlockCPS.Object.Visible = callback
			end

			if Wool then
				Wool.Object.Visible = callback
			end
		end,
		Default = true
	})
	Wool = AutoClicker:CreateToggle({Name = 'Wool only', Tooltip = 'Only clicks when you are holding wool', Darker = true})
	BlockCPS = AutoClicker:CreateTwoSlider({
		Name = 'Block CPS',
		Min = 1,
		Max = 20,
		DefaultMin = 20,
		DefaultMax = 20,
		Darker = true
	})
end)

print('[FIX] register-ac ' .. ((shared.vape.Modules ~= nil and shared.vape.Modules.AutoClicker ~= nil) and 'PASS' or 'FAIL'))
print('[FIX] done')
-- UraniumFix_Clutch v2 — repaired Clutch (nil-safe hand + working upvalues).
local g = getgenv()
g.vape = shared.vape
local lplr = game:GetService('Players').LocalPlayer
local rs = game:GetService('ReplicatedStorage')
if g.lplr == nil then g.lplr = lplr end
if g.inputService == nil then g.inputService = game:GetService('UserInputService') end
if g.store == nil then g.store = (shared and shared.store) or (function() local ok, s = pcall(function() return require(lplr.PlayerScripts.TS.ui.store).ClientStore end) return ok and s or nil end)() end
if g.entitylib == nil then g.entitylib = (function() local ok, src = pcall(readfile, 'aetherv2/libraries/entity.lua') if not ok or type(src) ~= 'string' then return nil end local fn = loadstring(src, 'UraniumFix_entity') if not fn then return nil end local ok2, lib = pcall(fn) return ok2 and lib or nil end)() end
if g.run == nil then g.run = function(f) local ok, err = xpcall(f, (debug and debug.traceback) or tostring) if not ok then warn('[UraniumFix] skipped: ' .. tostring(err)) end end end
local store = g.store
local entitylib = g.entitylib
local function roundPos(p) return Vector3.new(math.round(p.X / 3) * 3, math.round(p.Y / 3) * 3, math.round(p.Z / 3) * 3) end
local function getWool() for _, item in ((store.inventory or {}).inventory or {}).items or {} do if item.itemType ~= nil and item.itemType:find('wool') then return item.itemType, item.amount end end return nil end
local function getPlacedBlock(pos) if not pos then return nil end local bc = g.bedwars and g.bedwars.BlockController if not bc then return nil end local ok, gp = pcall(bc.getBlockPosition, bc, pos) if not ok then return nil end local ok2, st = pcall(bc.getStore, bc) if not ok2 then return nil end return st:getBlockAt(gp), gp end
local function notif(a, b, c, d) if g.vape ~= nil and type(g.vape.CreateNotification) == 'function' then return g.vape:CreateNotification(a, b, c, d) end warn('[Clutch] ' .. tostring(a) .. ': ' .. tostring(b)) end
if g.bedwars == nil then g.bedwars = {} end
local bw = g.bedwars
if bw.BlockController == nil then bw.BlockController = (function() local ok, m = pcall(function() return require(rs['rbxts_include']['node_modules']['@easy-games']['block-engine'].out) end) return (ok and m and m.BlockEngine) or nil end)() end
if bw.placeBlock == nil then
local BP = (function() local ok, m = pcall(function() return require(rs['rbxts_include']['node_modules']['@easy-games']['block-engine'].out.client.placement['block-placer']) end) return (ok and m and m.BlockPlacer) or nil end)()
local BE = (function() local ok, m = pcall(function() return require(lplr.PlayerScripts.TS.lib['block-engine']['client-block-engine']) end) return (ok and m and m.ClientBlockEngine) or nil end)()
if BP ~= nil and BE ~= nil and bw.BlockController ~= nil then
local ok, placer = pcall(BP.new, BE, 'wool_white')
if ok and placer ~= nil then
store.blockPlacer = placer
bw.placeBlock = function(pos, itemType) if not pos or not itemType then return nil end placer.blockType = itemType return placer:placeBlock(bw.BlockController:getBlockPosition(pos)) end
print('[FIX] placeBlock-ready PASS')
else
print('[FIX] placeBlock-ready FAIL | placer build failed')
end
else
print('[FIX] placeBlock-ready FAIL | parts missing')
end
end
task.spawn(function() pcall(function() g.vape:Remove('Clutch') end) end)
task.wait(2)
run(function()
	local Clutch
	local FallSpeed
	local LimitItems
	local AutoProtect

	local clutchParams = RaycastParams.new()
	clutchParams.FilterType = Enum.RaycastFilterType.Exclude

	local clutchOffsets = {
		Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0),
		Vector3.new(0, 1, 0), Vector3.new(0, -1, 0),
		Vector3.new(0, 0, 1), Vector3.new(0, 0, -1)
	}

	local function getClutchBlock()
		local hand = store.hand
		if LimitItems.Enabled and (hand == nil or hand.toolType ~= 'block') then
			return nil, 0
		end
		if hand ~= nil and hand.toolType == 'block' and hand.tool ~= nil then
			return hand.tool.Name, hand.amount or 0
		end
		local wool, amount = getWool()
		if wool then return wool, amount end
		local items = ((store.inventory or {}).inventory or {}).items or {}
		for _, item in items do
			local meta = bedwars.ItemMeta[item.itemType]
			if meta and meta.block then
				return item.itemType, item.amount
			end
		end
		return nil, 0
	end

	local function hasSupport(pos)
		local grid = bedwars.BlockController:getBlockPosition(pos)
		for _, off in clutchOffsets do
			if bedwars.BlockController:getStore():getBlockAt(grid + off) then
				return true
			end
		end
		return false
	end

	local function protectAbove(woolItem)
		if not AutoProtect.Enabled then return end
		local function attemptProtect()
			if not entitylib.isAlive then return false end
			local rootNow = entitylib.character.RootPart
			for _, height in ipairs({4.5, 7.5}) do
				local over = roundPos(rootNow.Position + Vector3.new(0, height, 0))
				local oblock, obp = getPlacedBlock(over)
				if not oblock and hasSupport(over) then
					bedwars.placeBlock(obp * 3, woolItem)
					return true
				end
			end
			return false
		end
		Clutch:Delay(0, function()
			if not attemptProtect() then
				Clutch:Delay(0.2, function()
					attemptProtect()
				end)
			end
		end)
	end

	Clutch = vape.Categories.Utility:CreateModule({
		Name = 'Clutch',
		Function = function(callback)
			if callback then
				local placedThisFall, notifiedEmpty = 0, false
				local wasGrounded = true
				local fastPoll = false
				repeat
					fastPoll = false
					if entitylib.isAlive then
						local char = entitylib.character
						local root = char.RootPart
						local humanoid = char.Humanoid
						local airborne = humanoid.FloorMaterial == Enum.Material.Air
						local flyOn = vape.Modules.Fly and vape.Modules.Fly.Enabled

						if airborne and not flyOn then
							fastPoll = true
							local justLeft = wasGrounded
							wasGrounded = false
							clutchParams.FilterDescendantsInstances = {lplr.Character}
							if justLeft and root.Velocity.Y <= 2 then
								local downNear = workspace:Raycast(root.Position, Vector3.new(0, -18, 0), clutchParams)
								if not downNear then
									local wool2, amount2 = getClutchBlock()
									if wool2 and (amount2 or 0) > 0 and placedThisFall < 4 then
										local feetNow = root.Position - Vector3.new(0, char.HipHeight + 1.5, 0)
										local blockNow, blockposNow = getPlacedBlock(roundPos(feetNow))
										if not blockNow and hasSupport(roundPos(feetNow)) then
											placedThisFall += 1
											Clutch:Delay(0, function() bedwars.placeBlock(blockposNow * 3, wool2) end)
											protectAbove(wool2)
											notif('Clutch', 'Clutch block placed', 2)
										end
									elseif not wool2 and not notifiedEmpty then
										notifiedEmpty = true
										notif('Clutch', 'No blocks for clutch', 4, 'alert')
									end
								end
							end
							if root.Velocity.Y < -FallSpeed.Value then
								clutchParams.FilterDescendantsInstances = {lplr.Character}
								local downHit = workspace:Raycast(root.Position, Vector3.new(0, -120, 0), clutchParams)
								if not downHit then
									local wool, amount = getClutchBlock()
									if wool and (amount or 0) > 0 and placedThisFall < 4 then
										local placed = false
										local function tryPlace(worldPos)
											if placed then return true end
											local block, blockpos = getPlacedBlock(worldPos)
											if not block and hasSupport(worldPos) then
												placedThisFall += 1
												placed = true
												Clutch:Delay(0, function() bedwars.placeBlock(blockpos * 3, wool) end)
												protectAbove(wool)
												notif('Clutch', 'Clutch block placed', 2)
											end
											return placed
										end

										local feet = root.Position + root.Velocity * 0.1 - Vector3.new(0, char.HipHeight + 1.5, 0)
										tryPlace(roundPos(feet))

										if not placed then
											local dir = humanoid.MoveDirection
											if dir.Magnitude < 0.05 then dir = root.CFrame.LookVector end
											dir = Vector3.new(dir.X, 0, dir.Z)
											if dir.Magnitude > 0 then
												dir = dir.Unit
												local wallHit = workspace:Raycast(root.Position, dir * 15, clutchParams)
												if wallHit then
													local target = roundPos(wallHit.Position + wallHit.Normal * 2)
													target = Vector3.new(target.X, roundPos(feet).Y, target.Z)
													tryPlace(target)
												end
											end
										end
									elseif not wool and not notifiedEmpty then
										notifiedEmpty = true
										notif('Clutch', 'No blocks for clutch', 4, 'alert')
									end
								end
							end
						else
							wasGrounded = true
							placedThisFall, notifiedEmpty = 0, false
						end
					end
					task.wait(fastPoll and 0.05 or 0.25)
				until not Clutch.Enabled
			end
		end,
		Tooltip = 'Places a block on the wall when falling into the void to save you.'
	})
	FallSpeed = Clutch:CreateSlider({Name = 'Fall speed', Min = 10, Max = 60, Default = 25, Tooltip = 'Minimum fall speed to trigger the clutch'})
	LimitItems = Clutch:CreateToggle({Name = 'Limit to items', Default = false, Tooltip = 'Only clutches while holding blocks'})
	AutoProtect = Clutch:CreateToggle({Name = 'Auto protect', Default = false, Tooltip = 'Places a block above you when clutching'})
end)
print('[FIX] register-clutch ' .. ((shared.vape.Modules ~= nil and shared.vape.Modules.Clutch ~= nil) and 'PASS' or 'FAIL'))
print('[FIX] done')
-- UraniumFix_StoreSync v1 — keeps getgenv().store live (hand+toolType, inventory, match).
local g = getgenv()
g.vape = shared.vape
local lplr = game:GetService('Players').LocalPlayer
local ItemMeta = (function() local ok, m = pcall(function() return require(game:GetService('ReplicatedStorage').TS.item['item-meta']) end) return (ok and m and m.items) or nil end)()
print('[FIX] sync-meta ' .. ((ItemMeta ~= nil) and 'PASS' or 'FAIL'))
local ClientStore = (function() local ok, s = pcall(function() return require(lplr.PlayerScripts.TS.ui.store).ClientStore end) return ok and s or nil end)()
if ClientStore == nil then warn('[FIX] sync-store FAIL | no ClientStore') return end
local function toolTypeOf(itemType, meta)
if not itemType then return nil end
if meta then if meta.sword then return 'sword' end if meta.block then return 'block' end end
if tostring(itemType):find('bow') then return 'bow' end
return nil
end
local Store = g.store
if type(Store) ~= 'table' then Store = {} g.store = Store end
task.spawn(function()
while true do
local ok, st = pcall(function() return ClientStore:getState() end)
if ok and type(st) == 'table' then
local oi = st.Inventory and st.Inventory.observedInventory
local inv = oi and oi.inventory
if inv then
Store.inventory = Store.inventory or {}
Store.inventory.inventory = Store.inventory.inventory or {}
Store.inventory.inventory.items = inv.items or {}
Store.inventory.inventory.armor = inv.armor or {}
Store.inventory.hotbar = oi.hotbar or {}
Store.inventory.hotbarSlot = oi.hotbarSlot or 0
local h = inv.hand
if type(h) == 'table' then
local meta = ItemMeta and h.itemType and ItemMeta[h.itemType] or nil
Store.hand = { itemType = h.itemType, amount = h.amount, tool = h.tool, toolType = toolTypeOf(h.itemType, meta) }
else
Store.hand = nil
end
end
if st.Game then Store.matchState = st.Game.matchState or 0 Store.queueType = st.Game.queueType or Store.queueType end
end
task.wait(0.5)
end
end)
task.wait(1)
local h = Store.hand
print('[FIX] sync-hand ' .. (type(h) == 'table' and ('PASS type=' .. tostring(h.toolType) .. ' item=' .. tostring(h.itemType)) or 'EMPTY'))
print('[FIX] sync-done')-- UraniumFix_ShimPack P1 v2 — ACTrigger (vape-identity guard).
local g = getgenv()
if g.UraniumACTriggerVape == shared.vape and g.UraniumACTriggerOn then print('[FIX] actrigger already-on') return end
g.UraniumACTriggerVape = shared.vape g.UraniumACTriggerOn = true
local uis = game:GetService('UserInputService')
local lplr = game:GetService('Players').LocalPlayer
local runId = 0
local function mod() local v = shared.vape return v and v.Modules and v.Modules.AutoClicker or nil end
local function isAttack(input)
local bw = g.bedwars
local kb = bw and bw.KeybindLoadController and bw.KeybindLoadController:getKeybinds()
local a = kb and kb.keyboard and kb.keyboard.controlActions and kb.keyboard.controlActions.Attack or Enum.UserInputType.MouseButton1
return input.UserInputType == a or input.KeyCode == a
end
local function cpsDelay()
local cps = 7 local ac = mod()
pcall(function() local o = ac and ac.Options and ac.Options['CPS'] if o and o.GetRandomValue then cps = o:GetRandomValue() end end)
return 1 / math.max(cps or 7, 0.001)
end
local function step()
local ac = mod() if not (ac and ac.Enabled) then return end
local bw = g.bedwars if not bw then return end
local st = g.store local h = st and st.hand if not h then return end
if h.toolType == 'sword' then
local atk = ac.Options and ac.Options['Attack'] if atk and not atk.Enabled then return end
local sc = bw.SwordController if not sc or sc.disableSwingState then return end
if lplr:GetAttribute('IsCasting') then return end
local meta = h.tool ~= nil and bw.ItemMeta[h.tool.Name] or nil
if not (meta and meta.sword and meta.sword.chargedAttack == nil) then return end
sc:swingSwordAtMouse(0.39)
elseif h.toolType == 'block' then
local plc = ac.Options and ac.Options['Place Blocks'] if plc and not plc.Enabled then return end
local bpc = bw.BlockPlacementController local placer = bpc and bpc.blockPlacer if not placer then return end
local ok, sel = pcall(function() return placer.clientManager:getBlockSelector() end)
if not ok or not sel then return end
local ok2, mi = pcall(function() return sel:getMouseInfo(0) end)
if ok2 and mi and mi.placementPosition == mi.placementPosition then
task.spawn(placer.placeBlock, placer, mi.placementPosition, mi)
end end end
uis.InputBegan:Connect(function(input, gpe) if gpe then return end if not isAttack(input) then return end local ac = mod() if not (ac and ac.Enabled) then return end runId = runId + 1 local mine = runId print('[FIX] actrigger start') task.spawn(function() task.wait(cpsDelay()) while mine == runId and mod() and mod().Enabled do local ok, err = pcall(step) if not ok then warn('[FIX] actrigger: ' .. tostring(err)) break end task.wait(cpsDelay()) end end) end)
uis.InputEnded:Connect(function(input) if isAttack(input) then runId = runId + 1 end end)
print('[FIX] actrigger armed')-- UraniumFix_ShimPack P2 v2 — ClutchV3 (vape-identity guard). Lasso wall + pearl link.
local g = getgenv()
if g.UraniumClutchV3Vape == shared.vape and g.UraniumClutchV3On then print('[FIX] clutchv3 already-on') return end
g.UraniumClutchV3Vape = shared.vape g.UraniumClutchV3On = true
local lplr = game:GetService('Players').LocalPlayer
local function mod(n) local v = shared.vape return v and v.Modules and v.Modules[n] or nil end
local function clutchOn() local c = mod('Clutch') return c ~= nil and c.Enabled end
local function getWool() local st = g.store local items = st and st.inventory and st.inventory.inventory and st.inventory.inventory.items or {} for _, it in pairs(items) do if type(it.itemType) == 'string' and it.itemType:find('wool') and (it.amount or 0) > 0 then return it.itemType end end return nil end
local function roundPos(p) return Vector3.new(math.round(p.X / 3) * 3, math.round(p.Y / 3) * 3, math.round(p.Z / 3) * 3) end
local function cellEmpty(bc, gp) local ok, st = pcall(bc.getStore, bc) if not ok or not st then return nil end local ok2, b = pcall(st.getBlockAt, st, gp) if not ok2 then return nil end return b == nil end
local lastWall = 0
local function wallAgainstLasso()
if os.clock() - lastWall < 3 then return end
local bw = g.bedwars if not bw or not bw.placeBlock or not bw.BlockController then return end
local wool = getWool() if not wool then return end
local ch = lplr.Character local root = ch and ch:FindFirstChild('HumanoidRootPart') if not root then return end
local fwd = root.CFrame.LookVector * Vector3.new(1, 0, 1) if fwd.Magnitude < 0.1 then fwd = Vector3.new(0, 0, 1) end fwd = fwd.Unit
lastWall = os.clock()
task.spawn(function()
local bc = bw.BlockController
for i = 0, 2 do
if not clutchOn() then break end
local target = roundPos(root.Position + fwd * 4 + Vector3.new(0, (i - 1) * 3, 0))
local ok, gp = pcall(bc.getBlockPosition, bc, target) if not ok then break end
for att = 1, 4 do
if not clutchOn() then break end
local empty = cellEmpty(bc, gp)
if empty == false then break end
pcall(bw.placeBlock, gp * 3, wool)
task.wait(0.4)
if cellEmpty(bc, gp) == false then break end
end end
print('[FIX] clutchv3 wall-done')
end)
end
local function isLassoPart(inst) local ok, r = pcall(function() if inst:IsA('RopeConstraint') then return true end local n = inst.Name:lower() return n:find('lasso', 1, true) ~= nil or n:find('rope', 1, true) ~= nil end) return ok and r end
local function watchCharacter(ch) if not ch then return end for _, d in ipairs(ch:GetDescendants()) do if isLassoPart(d) then wallAgainstLasso() break end end ch.DescendantAdded:Connect(function(d) if clutchOn() and isLassoPart(d) then print('[FIX] clutchv3 lasso-grab') wallAgainstLasso() end end) end
if lplr.Character then task.spawn(function() pcall(watchCharacter, lplr.Character) end) end
lplr.CharacterAdded:Connect(function(ch) task.wait(1) pcall(watchCharacter, ch) end)
task.spawn(function() while true do local c = mod('Clutch') local ap = mod('AutoPearl') if c and c.Enabled and ap and not ap.Enabled then pcall(function() ap:Toggle(true) end) print('[FIX] clutchv3 pearl-link on') end task.wait(2) end end)
print('[FIX] clutchv3 armed')-- UraniumFix_ShimPack P3 v2 — DaveyAim (vape-identity guard). Aim assist + brake.
local g = getgenv()
if g.UraniumDaveyAimVape == shared.vape and g.UraniumDaveyAimOn then print('[FIX] daveyaim already-on') return end
g.UraniumDaveyAimVape = shared.vape g.UraniumDaveyAimOn = true
g.vape = shared.vape
local lplr = game:GetService('Players').LocalPlayer
local cs = game:GetService('CollectionService')
local rs = game:GetService('ReplicatedStorage')
local Remotes = (function() local ok, m = pcall(function() return require(rs.TS.remotes) end) return ok and m or nil end)()
local DaveyAim = nil local AimAssist = {Enabled = true} local Brake = {Enabled = true}
local launched = false local brakeCD = 0
local function nearestEnemy(fromPos, maxD) local best, bestD = nil, maxD or 150 for _, p in ipairs(game:GetService('Players'):GetPlayers()) do if p ~= lplr then local ch = p.Character local hrp = ch and ch:FindFirstChild('HumanoidRootPart') local hum = ch and ch:FindFirstChildOfClass('Humanoid') if hrp and hum and hum.Health > 0 then if lplr.Team == nil or p.Team ~= lplr.Team then local d = (hrp.Position - fromPos).Magnitude if d < bestD then best, bestD = hrp, d end end end end end return best end
local function sessionCannon() local ch = lplr.Character local root = ch and ch:FindFirstChild('HumanoidRootPart') if not root then return nil end local best, bestD = nil, 12 for _, m in ipairs(cs:GetTagged('cannon')) do if m:IsA('Model') or m:IsA('BasePart') then local pos = (m:IsA('Model') and m:GetPivot().Position or m.Position) local d = (pos - root.Position).Magnitude if d < bestD then best, bestD = m, d end end end return best end
local function aimStep() local bw = g.bedwars if not bw then return end local cc = bw.CannonController if not cc or not cc.aiming then return end local cannon = sessionCannon() if not cannon then return end local cpos = (cannon:IsA('Model') and cannon:GetPivot().Position or cannon.Position) local target = nearestEnemy(cpos, 150) if not target then return end local dir = (target.Position - cpos) if dir.Magnitude < 1 then return end dir = dir.Unit local bp = bw.BlockController and bw.BlockController:getBlockPosition(cpos) if not bp then return end local cli = Remotes and Remotes.default and Remotes.default.Client if not cli then return end pcall(function() cli:Get('AimCannon'):SendToServer({cannonBlockPos = bp, lookVector = dir}) end) end
local function brakeStep() local ch = lplr.Character if not ch then launched = false return end local root = ch:FindFirstChild('HumanoidRootPart') local hum = ch:FindFirstChildOfClass('Humanoid') if not root or not hum then return end local sp = root.AssemblyLinearVelocity.Magnitude local air = hum.FloorMaterial == Enum.Material.Air if air and sp > 65 then launched = true return end if launched and not air then launched = false if os.clock() - brakeCD < 2 then return end local flat = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude if flat < 25 then return end brakeCD = os.clock() task.spawn(function() local t0 = os.clock() while os.clock() - t0 < 1 do local r2 = lplr.Character and lplr.Character:FindFirstChild('HumanoidRootPart') if not r2 then break end local v = r2.AssemblyLinearVelocity r2.AssemblyLinearVelocity = Vector3.new(v.X * 0.82, v.Y, v.Z * 0.82) task.wait() end end) end end
task.spawn(function() local vape = shared.vape DaveyAim = vape.Categories.Combat:CreateModule({Name = 'DaveyAim', Function = function(cb) if not cb then launched = false end end, Tooltip = 'Cannon aim assist + brake on land'}) AimAssist = DaveyAim:CreateToggle({Name = 'Aim Assist', Default = true, Tooltip = 'Aims your cannon at the nearest enemy while aiming'}) Brake = DaveyAim:CreateToggle({Name = 'Brake', Default = true, Tooltip = 'Kills slide after cannon launch'}) print('[FIX] daveyaim registered') end) task.spawn(function() while true do if DaveyAim ~= nil and DaveyAim.Enabled then if AimAssist.Enabled then pcall(aimStep) end if Brake.Enabled then pcall(brakeStep) end end task.wait(0.25) end end)
print('[FIX] daveyaim armed')-- UraniumFix_ShimPack P4 v2 — AutoDavey (vape-identity guard).
local g = getgenv()
if g.UraniumAutoDaveyVape == shared.vape and g.UraniumAutoDaveyOn then print('[FIX] autodavey already-on') return end
g.UraniumAutoDaveyVape = shared.vape g.UraniumAutoDaveyOn = true
g.vape = shared.vape
local lplr = game:GetService('Players').LocalPlayer
local cs = game:GetService('CollectionService')
local AutoDavey = nil local OnPlace = {Enabled = true} local OnLand = {Enabled = true}
local lastSwing = 0 local launched = false
local function pickTool() local st = g.store local h = st and st.hand if h and h.itemType == 'wood_pickaxe' and h.tool ~= nil then return h.tool end return nil end
local function swingOnce(why) local t = pickTool() if not t then return end if os.clock() - lastSwing < 1 then return end lastSwing = os.clock() local ok = pcall(function() t:Activate() end) if ok then print('[FIX] autodavey swing ' .. tostring(why)) end end
local function nearRoot(model, maxD) local ch = lplr.Character local root = ch and ch:FindFirstChild('HumanoidRootPart') if not root then return false end local pos = (model:IsA('Model') and model:GetPivot().Position or model.Position) return (pos - root.Position).Magnitude <= (maxD or 14) end
cs:GetInstanceAddedSignal('cannon'):Connect(function(m) task.wait(0.5) if AutoDavey ~= nil and AutoDavey.Enabled and OnPlace.Enabled and nearRoot(m, 14) then swingOnce('place') end end)
task.spawn(function() while true do if AutoDavey ~= nil and AutoDavey.Enabled and OnLand.Enabled then local ch = lplr.Character local root = ch and ch:FindFirstChild('HumanoidRootPart') local hum = ch and ch:FindFirstChildOfClass('Humanoid') if root and hum then local sp = root.AssemblyLinearVelocity.Magnitude local air = hum.FloorMaterial == Enum.Material.Air if air and sp > 65 then launched = true elseif launched and not air then launched = false swingOnce('land') end end end task.wait(0.25) end end)
task.spawn(function() local vape = shared.vape AutoDavey = vape.Categories.Utility:CreateModule({Name = 'AutoDavey', Function = function(cb) if not cb then launched = false end end, Tooltip = 'Wood-pickaxe swing on cannon place + on landing'}) OnPlace = AutoDavey:CreateToggle({Name = 'Swing on Place', Default = true, Tooltip = 'One pickaxe swing when your cannon is placed (wood pickaxe only)'}) OnLand = AutoDavey:CreateToggle({Name = 'Swing on Land', Default = true, Tooltip = 'One pickaxe swing when you land after launch (wood pickaxe only)'}) print('[FIX] autodavey registered') end)
print('[FIX] autodavey armed')-- UraniumFix_StoreSync v1 — keeps getgenv().store live (hand+toolType, inventory, match).
local g = getgenv()
g.vape = shared.vape
local lplr = game:GetService('Players').LocalPlayer
local ItemMeta = (function() local ok, m = pcall(function() return require(game:GetService('ReplicatedStorage').TS.item['item-meta']) end) return (ok and m and m.items) or nil end)()
print('[FIX] sync-meta ' .. ((ItemMeta ~= nil) and 'PASS' or 'FAIL'))
local ClientStore = (function() local ok, s = pcall(function() return require(lplr.PlayerScripts.TS.ui.store).ClientStore end) return ok and s or nil end)()
if ClientStore == nil then warn('[FIX] sync-store FAIL | no ClientStore') return end
local function toolTypeOf(itemType, meta)
if not itemType then return nil end
if meta then if meta.sword then return 'sword' end if meta.block then return 'block' end end
if tostring(itemType):find('bow') then return 'bow' end
return nil
end
local Store = g.store
if type(Store) ~= 'table' then Store = {} g.store = Store end
task.spawn(function()
while true do
local ok, st = pcall(function() return ClientStore:getState() end)
if ok and type(st) == 'table' then
local oi = st.Inventory and st.Inventory.observedInventory
local inv = oi and oi.inventory
if inv then
Store.inventory = Store.inventory or {}
Store.inventory.inventory = Store.inventory.inventory or {}
Store.inventory.inventory.items = inv.items or {}
Store.inventory.inventory.armor = inv.armor or {}
Store.inventory.hotbar = oi.hotbar or {}
Store.inventory.hotbarSlot = oi.hotbarSlot or 0
local h = inv.hand
if type(h) == 'table' then
local meta = ItemMeta and h.itemType and ItemMeta[h.itemType] or nil
Store.hand = { itemType = h.itemType, amount = h.amount, tool = h.tool, toolType = toolTypeOf(h.itemType, meta) }
else
Store.hand = nil
end
end
if st.Game then Store.matchState = st.Game.matchState or 0 Store.queueType = st.Game.queueType or Store.queueType end
end
task.wait(0.5)
end
end)
task.wait(1)
local h = Store.hand
print('[FIX] sync-hand ' .. (type(h) == 'table' and ('PASS type=' .. tostring(h.toolType) .. ' item=' .. tostring(h.itemType)) or 'EMPTY'))
print('[FIX] sync-done')