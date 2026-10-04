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
print('[FIX] sync-done')-- P1 FINAL — ACTrigger: no gpe filter (layer check), physical release, vape guard.
local g = getgenv()
if g.UraniumACTFVape == shared.vape and g.UraniumACTFOn then print('[FIX] actrigger already-on') return end
g.UraniumACTFVape = shared.vape g.UraniumACTFOn = true
local uis = game:GetService('UserInputService')
local lplr = game:GetService('Players').LocalPlayer
local runId = 0
local function mod() local v = shared.vape return v and v.Modules and v.Modules.AutoClicker or nil end
local function menuOpen() local bw = g.bedwars if not bw or not bw.AppController then return false end local ok, o = pcall(function() return bw.AppController:isLayerOpen(bw.UILayers.MAIN) end) return ok and o end
local function isAttack(input)
local bw = g.bedwars
local kb = bw and bw.KeybindLoadController and bw.KeybindLoadController:getKeybinds()
local a = kb and kb.keyboard and kb.keyboard.controlActions and kb.keyboard.controlActions.Attack or Enum.UserInputType.MouseButton1
return input.UserInputType == a or input.KeyCode == a
end
local function heldDown() local ok, d = pcall(function() return uis:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end) if not ok then return true end return d end
local function cpsDelay()
local cps = 7 local ac = mod()
pcall(function() local o = ac and ac.Options and ac.Options['CPS'] if o and o.GetRandomValue then cps = o:GetRandomValue() end end)
return 1 / math.max(cps or 7, 0.001)
end
local function step()
local ac = mod() if not (ac and ac.Enabled) then return end
if menuOpen() then return end
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
local function limitOk() local v = shared.vape local c = v and v.Modules and v.Modules.Clutch local o = c and c.Options and c.Options['Limit to items'] if o and o.Enabled then local st = g.store local h = st and st.hand return h ~= nil and h.toolType == 'block' end return true end
uis.InputBegan:Connect(function(input) if not isAttack(input) then return end if menuOpen() then return end local ac = mod() if not (ac and ac.Enabled) then return end runId = runId + 1 local mine = runId print('[FIX] actrigger start') task.spawn(function() task.wait(cpsDelay()) while mine == runId and mod() and mod().Enabled and heldDown() do local ok, err = pcall(step) if not ok then warn('[FIX] actrigger: ' .. tostring(err)) break end task.wait(cpsDelay()) end end) end)
uis.InputEnded:Connect(function(input) if isAttack(input) then runId = runId + 1 end end)
print('[FIX] actrigger armed')-- P2 v2 — ClutchV3 (vape guard). Lasso wall (Limit-honored) + AutoPearl link.
local g = getgenv()
if g.UraniumClutchV3Vape == shared.vape and g.UraniumClutchV3On then print('[FIX] clutchv3 already-on') return end
g.UraniumClutchV3Vape = shared.vape g.UraniumClutchV3On = true
local lplr = game:GetService('Players').LocalPlayer
local function limitOk() local v = shared.vape local c = v and v.Modules and v.Modules.Clutch local o = c and c.Options and c.Options['Limit to items'] if o and o.Enabled then local st = g.store local h = st and st.hand return h ~= nil and h.toolType == 'block' end return true end
local function mod(n) local v = shared.vape return v and v.Modules and v.Modules[n] or nil end
local function clutchOn() local c = mod('Clutch') return c ~= nil and c.Enabled end
local function getWool() local st = g.store local items = st and st.inventory and st.inventory.inventory and st.inventory.inventory.items or {} for _, it in pairs(items) do if type(it.itemType) == 'string' and it.itemType:find('wool') and (it.amount or 0) > 0 then return it.itemType end end return nil end
local function roundPos(p) return Vector3.new(math.round(p.X / 3) * 3, math.round(p.Y / 3) * 3, math.round(p.Z / 3) * 3) end
local function cellEmpty(bc, gp) local ok, st = pcall(bc.getStore, bc) if not ok or not st then return nil end local ok2, b = pcall(st.getBlockAt, st, gp) if not ok2 then return nil end return b == nil end
local lastWall = 0
local function wallAgainstLasso()
if os.clock() - lastWall < 3 then return end
if not limitOk() then return end
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
print('[FIX] clutchv3 armed')-- UraniumFix_ShimPack P3 v3 — DaveyBrake ext (no module). Kills slide after ANY cannon launch.
local g = getgenv()
if g.UraniumDaveyBrakeVape == shared.vape and g.UraniumDaveyBrakeOn then print('[FIX] daveybrake already-on') return end
g.UraniumDaveyBrakeVape = shared.vape g.UraniumDaveyBrakeOn = true
local lplr = game:GetService('Players').LocalPlayer
local launched = false local brakeCD = 0
task.spawn(function() while true do local ch = lplr.Character local root = ch and ch:FindFirstChild('HumanoidRootPart') local hum = ch and ch:FindFirstChildOfClass('Humanoid') if root and hum then local sp = root.AssemblyLinearVelocity.Magnitude local air = hum.FloorMaterial == Enum.Material.Air if air and sp > 65 then launched = true elseif launched and not air then launched = false if os.clock() - brakeCD >= 2 then local flat = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude if flat >= 25 then brakeCD = os.clock() print('[FIX] daveybrake stop') task.spawn(function() local t0 = os.clock() while os.clock() - t0 < 1 do local r2 = lplr.Character and lplr.Character:FindFirstChild('HumanoidRootPart') if not r2 then break end local v = r2.AssemblyLinearVelocity r2.AssemblyLinearVelocity = Vector3.new(v.X * 0.82, v.Y, v.Z * 0.82) task.wait() end end) end end end end task.wait(0.25) end end)
print('[FIX] daveybrake armed')-- UraniumFix_ShimPack P4 v3 — AutoDavey ext (no module). Wood-pickaxe swing on cannon place + land.
local g = getgenv()
if g.UraniumAutoDaveyXVape == shared.vape and g.UraniumAutoDaveyXOn then print('[FIX] autodavey already-on') return end
g.UraniumAutoDaveyXVape = shared.vape g.UraniumAutoDaveyXOn = true
local lplr = game:GetService('Players').LocalPlayer
local cs = game:GetService('CollectionService')
local lastSwing = 0 local launched = false
local function pickTool() local st = g.store local h = st and st.hand if h and h.itemType == 'wood_pickaxe' and h.tool ~= nil then return h.tool end return nil end
local function swingOnce(why) local t = pickTool() if not t then return end if os.clock() - lastSwing < 1 then return end lastSwing = os.clock() if pcall(function() t:Activate() end) then print('[FIX] autodavey swing ' .. tostring(why)) end end
local function nearRoot(model, maxD) local ch = lplr.Character local root = ch and ch:FindFirstChild('HumanoidRootPart') if not root then return false end local pos = (model:IsA('Model') and model:GetPivot().Position or model.Position) return (pos - root.Position).Magnitude <= (maxD or 14) end
cs:GetInstanceAddedSignal('cannon'):Connect(function(m) task.wait(0.5) if nearRoot(m, 14) then swingOnce('place') end end)
task.spawn(function() while true do local ch = lplr.Character local root = ch and ch:FindFirstChild('HumanoidRootPart') local hum = ch and ch:FindFirstChildOfClass('Humanoid') if root and hum then local sp = root.AssemblyLinearVelocity.Magnitude local air = hum.FloorMaterial == Enum.Material.Air if air and sp > 65 then launched = true elseif launched and not air then launched = false swingOnce('land') end end task.wait(0.25) end end)
print('[FIX] autodavey armed')-- UraniumFix_ShimPack P5 — Cannon enemy-aim assist (no module). While aiming, points cannon at nearest enemy.
local g = getgenv()
if g.UraniumAimAssistVape == shared.vape and g.UraniumAimAssistOn then print('[FIX] aimassist already-on') return end
g.UraniumAimAssistVape = shared.vape g.UraniumAimAssistOn = true
g.UraniumAimCount = 0
local lplr = game:GetService('Players').LocalPlayer
local cs = game:GetService('CollectionService')
local rs = game:GetService('ReplicatedStorage')
local Remotes = (function() local ok, m = pcall(function() return require(rs.TS.remotes) end) return ok and m or nil end)()
local function nearestEnemy(fromPos, maxD) local best, bestD = nil, maxD or 150 for _, p in ipairs(game:GetService('Players'):GetPlayers()) do if p ~= lplr then local ch = p.Character local hrp = ch and ch:FindFirstChild('HumanoidRootPart') local hum = ch and ch:FindFirstChildOfClass('Humanoid') if hrp and hum and hum.Health > 0 then if lplr.Team == nil or p.Team ~= lplr.Team then local d = (hrp.Position - fromPos).Magnitude if d < bestD then best, bestD = hrp, d end end end end end return best end
local function sessionCannon() local ch = lplr.Character local root = ch and ch:FindFirstChild('HumanoidRootPart') if not root then return nil end local best, bestD = nil, 14 for _, m in ipairs(cs:GetTagged('cannon')) do if m:IsA('Model') or m:IsA('BasePart') then local pos = (m:IsA('Model') and m:GetPivot().Position or m.Position) local d = (pos - root.Position).Magnitude if d < bestD then best, bestD = m, d end end end return best end
task.spawn(function() while true do local bw = g.bedwars local cc = bw and bw.CannonController if cc and cc.aiming then local cannon = sessionCannon() if cannon then local cpos = (cannon:IsA('Model') and cannon:GetPivot().Position or cannon.Position) local target = nearestEnemy(cpos, 150) if target then local dir = (target.Position - cpos) if dir.Magnitude > 1 then dir = dir.Unit local bp = bw.BlockController and bw.BlockController:getBlockPosition(cpos) local cli = Remotes and Remotes.default and Remotes.default.Client if bp and cli then local ok = pcall(function() cli:Get('AimCannon'):SendToServer({cannonBlockPos = bp, lookVector = dir}) end) if ok then g.UraniumAimCount = g.UraniumAimCount + 1 end end end end end end task.wait(0.15) end end)
print('[FIX] aimassist armed')-- UraniumFix_ShimPack P6 — void double-block safety (no module). Backup when falling hard with no ground.
local g = getgenv()
if g.UraniumDoubleBlockVape == shared.vape and g.UraniumDoubleBlockOn then print('[FIX] doubleblock already-on') return end
g.UraniumDoubleBlockVape = shared.vape g.UraniumDoubleBlockOn = true
local lplr = game:GetService('Players').LocalPlayer
local params = RaycastParams.new() params.FilterType = Enum.RaycastFilterType.Exclude params.RespectCanCollide = true
local function clutchOn() local v = shared.vape local c = v and v.Modules and v.Modules.Clutch return c ~= nil and c.Enabled end
local function woolCount() local n = 0 local st = g.store local items = st and st.inventory and st.inventory.inventory and st.inventory.inventory.items or {} for _, it in pairs(items) do if type(it.itemType) == 'string' and it.itemType:find('wool') then n = n + (it.amount or 0) end end return n end
local function roundPos(p) return Vector3.new(math.round(p.X / 3) * 3, math.round(p.Y / 3) * 3, math.round(p.Z / 3) * 3) end
local lastCD = 0
task.spawn(function() while true do if clutchOn() and os.clock() - lastCD > 5 then local ch = lplr.Character local root = ch and ch:FindFirstChild('HumanoidRootPart') if root and root.AssemblyLinearVelocity.Y < -45 then params.FilterDescendantsInstances = {ch} local hit = workspace:Raycast(root.Position, Vector3.new(0, -40, 0), params) if not hit and woolCount() >= 2 then local bw = g.bedwars local bc = bw and bw.BlockController if bc and bw.placeBlock then lastCD = os.clock() local wool = nil local st = g.store local items = st and st.inventory and st.inventory.inventory and st.inventory.inventory.items or {} for _, it in pairs(items) do if type(it.itemType) == 'string' and it.itemType:find('wool') and (it.amount or 0) > 0 then wool = it.itemType break end end if wool then task.spawn(function() for _, off in ipairs({Vector3.new(0, 0, 0), Vector3.new(0, -3, 0)}) do local target = roundPos(root.Position - Vector3.new(0, 3, 0) + off) local ok, gp = pcall(bc.getBlockPosition, bc, target) if ok then local ok2, st2 = pcall(bc.getStore, bc) if ok2 and st2 then local ok3, b = pcall(st2.getBlockAt, st2, gp) if ok3 and b == nil then pcall(bw.placeBlock, gp * 3, wool) end end end task.wait(0.35) end print('[FIX] doubleblock placed') end) end end end end end task.wait(0.2) end end)
print('[FIX] doubleblock armed')-- P7 v2 — tower-up + suffocate (Limit-honored). Bridge moved to P8.
local g = getgenv()
if g.UraniumP7Vape == shared.vape and g.UraniumP7On then print('[FIX] p7 already-on') return end
g.UraniumP7Vape = shared.vape g.UraniumP7On = true
local lplr = game:GetService('Players').LocalPlayer
local uis = game:GetService('UserInputService')
local function clutchOn() local v = shared.vape local c = v and v.Modules and v.Modules.Clutch return c ~= nil and c.Enabled end
local function limitOk() local v = shared.vape local c = v and v.Modules and v.Modules.Clutch local o = c and c.Options and c.Options['Limit to items'] if o and o.Enabled then local st = g.store local h = st and st.hand return h ~= nil and h.toolType == 'block' end return true end
local function roundPos(p) return Vector3.new(math.round(p.X / 3) * 3, math.round(p.Y / 3) * 3, math.round(p.Z / 3) * 3) end
local function tryPlace(worldPos) if not limitOk() then return false end local bw = g.bedwars local bc = bw and bw.BlockController if not bc or not bw.placeBlock then return false end local st = g.store local items = st and st.inventory and st.inventory.inventory and st.inventory.inventory.items or {} local wool = nil for _, it in pairs(items) do if type(it.itemType) == 'string' and it.itemType:find('wool') and (it.amount or 0) > 0 then wool = it.itemType break end end if not wool then return false end local ok, gp = pcall(bc.getBlockPosition, bc, worldPos) if not ok then return false end local ok2, st2 = pcall(bc.getStore, bc) if not ok2 or not st2 then return false end local ok3, b = pcall(st2.getBlockAt, st2, gp) if not ok3 or b ~= nil then return false end local ok4 = pcall(bw.placeBlock, gp * 3, wool) return ok4 end
task.spawn(function() while true do if clutchOn() then local ok, down = pcall(function() return uis:IsKeyDown(Enum.KeyCode.Space) end) local ch = lplr.Character local root = ch and ch:FindFirstChild('HumanoidRootPart') local hum = ch and ch:FindFirstChildOfClass('Humanoid') if ok and down and root and hum then local air = hum.FloorMaterial == Enum.Material.Air if not air or math.abs(root.AssemblyLinearVelocity.Y) < 8 then local below = roundPos(root.Position + Vector3.new(0, -3, 0)) if tryPlace(below) then task.wait(0.25) end end end end task.wait(0.12) end end)
local suffCD = {}
task.spawn(function() while true do if clutchOn() then local ch = lplr.Character local root = ch and ch:FindFirstChild('HumanoidRootPart') if root then for _, p in ipairs(game:GetService('Players'):GetPlayers()) do if p ~= lplr then local ec = p.Character local ehr = ec and ec:FindFirstChild('HumanoidRootPart') local ehum = ec and ec:FindFirstChildOfClass('Humanoid') if ehr and ehum and ehum.Health > 0 then if lplr.Team == nil or p.Team ~= lplr.Team then local d = (ehr.Position - root.Position).Magnitude if d < 8 and (os.clock() - (suffCD[p.Name] or 0)) > 5 then suffCD[p.Name] = os.clock() task.spawn(function() local f = roundPos(ehr.Position) tryPlace(f) task.wait(0.2) local h = roundPos(ehr.Position + Vector3.new(0, 3, 0)) tryPlace(h) print('[FIX] suffocate ' .. tostring(p.Name)) end) end end end end end end end task.wait(0.3) end end)
print('[FIX] p7 armed')-- P8 v2 — bridge/support-first + Limit honor + emergency pearl. Readable build.
local g = getgenv()
if g.UraniumP8Vape == shared.vape and g.UraniumP8On then
print('[FIX] p8 already-on') return end
g.UraniumP8Vape = shared.vape g.UraniumP8On = true
local lplr = game:GetService('Players').LocalPlayer
local rs = game:GetService('ReplicatedStorage')
local Knit = (function()
local ok, k = pcall(function()
return require(rs['rbxts_include']['node_modules']['@easy-games'].knit.src).KnitClient end)
return ok and k or nil end)()
local KC = Knit and Knit.Controllers or {}
local ProjMeta = (function()
local ok, m = pcall(function() return require(rs.TS.projectile['projectile-meta']) end)
return ok and m or nil end)()
local httpService = game:GetService('HttpService')
local function clutchOn()
local v = shared.vape local c = v and v.Modules and v.Modules.Clutch
return c ~= nil and c.Enabled end
local function limitOk()
local v = shared.vape local c = v and v.Modules and v.Modules.Clutch
local o = c and c.Options and c.Options['Limit to items']
if o and o.Enabled then
local st = g.store local h = st and st.hand
return h ~= nil and h.toolType == 'block' end
return true end
local function roundPos(p)
return Vector3.new(math.round(p.X/3)*3, math.round(p.Y/3)*3, math.round(p.Z/3)*3) end
local function invItems()
local st = g.store
return st and st.inventory and st.inventory.inventory and st.inventory.inventory.items or {} end
local function findItem(t)
for _, it in pairs(invItems()) do if it.itemType == t then return it end end
return nil end
local function woolType()
for _, it in pairs(invItems()) do
if type(it.itemType) == 'string' and it.itemType:find('wool') and (it.amount or 0) > 0 then
return it.itemType end end
return nil end
local function cellState(bc, gp)
local ok, st = pcall(bc.getStore, bc)
if not ok or not st then return nil end
local ok2, b = pcall(st.getBlockAt, st, gp)
if not ok2 then return nil end
return b ~= nil end
local function hasSupport(bc, gp)
local offs = {Vector3.new(3,0,0), Vector3.new(-3,0,0), Vector3.new(0,3,0)}
offs[#offs+1] = Vector3.new(0,-3,0)
offs[#offs+1] = Vector3.new(0,0,3)
offs[#offs+1] = Vector3.new(0,0,-3)
for _, o in ipairs(offs) do
local s = cellState(bc, gp + o)
if s == true then return true end
if s == nil then return nil end end
return false end
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = true
local lastGround = nil
task.spawn(function()
while true do
local ch = lplr.Character
local root = ch and ch:FindFirstChild('HumanoidRootPart')
local hum = ch and ch:FindFirstChildOfClass('Humanoid')
if clutchOn() and root and hum then
if hum.FloorMaterial ~= Enum.Material.Air then lastGround = root.CFrame end
if root.AssemblyLinearVelocity.Y < -12 then
params.FilterDescendantsInstances = {ch}
local down = workspace:Raycast(root.Position, Vector3.new(0,-30,0), params)
if not down and limitOk() then
local md = hum.MoveDirection local dir = nil
if md.Magnitude > 0.2 then dir = Vector3.new(md.X, 0, md.Z).Unit end
if not dir then
local bd, bn = 40, nil
local dirs = {Vector3.new(1,0,0), Vector3.new(-1,0,0)}
dirs[#dirs+1] = Vector3.new(0,0,1) dirs[#dirs+1] = Vector3.new(0,0,-1)
for _, d in ipairs(dirs) do
local hit = workspace:Raycast(root.Position + Vector3.new(0,1,0), d * 40, params)
if hit and hit.Distance < bd then bd, bn = hit.Distance, d end end
dir = bn or (root.CFrame.LookVector * Vector3.new(1,0,1)).Unit end
local bw = g.bedwars local bc = bw and bw.BlockController
if bc and bw.placeBlock then
local cells = {}
for k = 1, 5 do
local tp = roundPos(root.Position + dir * (3*k) + Vector3.new(0,-1,0))
local ok, gp = pcall(bc.getBlockPosition, bc, tp)
if ok and (root.Position - tp).Magnitude < 14 then cells[#cells+1] = gp end end
for idx = #cells, 1, -1 do
local gp = cells[idx]
if cellState(bc, gp) == false and hasSupport(bc, gp) == true then
local wool = woolType()
if wool then pcall(bw.placeBlock, gp * 3, wool) task.wait(0.12) end end end end end end end
task.wait(0.25) end end)
task.spawn(function()
while true do
local ch = lplr.Character
local root = ch and ch:FindFirstChild('HumanoidRootPart')
local hum = ch and ch:FindFirstChildOfClass('Humanoid')
if clutchOn() and root and hum and limitOk() then
if root.AssemblyLinearVelocity.Y < -60 then
params.FilterDescendantsInstances = {ch}
local down = workspace:Raycast(root.Position, Vector3.new(0,-150,0), params)
if not down then
local pearl = findItem('telepearl')
local meta = ProjMeta and ProjMeta.telepearl
local pc = KC.ProjectileController
if pearl and pearl.tool and meta and pc then
local spot = lastGround and lastGround.Position or (root.Position + Vector3.new(0,30,0))
local oldHand = nil
pcall(function() oldHand = g.store.hand end)
pcall(function() hum:EquipTool(pearl.tool) end)
task.wait(0.1)
local toT = spot - root.Position
local dir = nil
if toT.Magnitude < 1 then dir = Vector3.new(0,1,0)
else dir = toT.Unit * (tonumber(meta.launchVelocity) or 100) end
pcall(function()
pc:createLocalProjectile(meta, 'telepearl', 'telepearl', root.Position, nil, dir, {drawDurationSeconds = 1}) end)
local bw = g.bedwars local cli = bw and bw.Client
if cli then
local okR, rem = pcall(function() return cli:Get('FireProjectile') end)
if okR and rem and rem.instance then
pcall(function()
rem.instance:InvokeServer(pearl.tool, 'telepearl', 'telepearl', root.Position, root.Position, dir, httpService:GenerateGUID(true), {drawDurationSeconds = 1, shotId = httpService:GenerateGUID(false)}, workspace:GetServerTimeNow() - 0.045) end) end end
if oldHand and oldHand.tool then pcall(function() hum:EquipTool(oldHand.tool) end) end
print('[FIX] emergency pearl')
task.wait(5) end end end end
task.wait(0.2) end end)
print('[FIX] p8 armed')-- BedPlates3D v2 — modern bed replica (frame/mattress/blanket/pillow/legs, team color) + shell boxes.
local g = getgenv()
g.vape = shared.vape
local cs = game:GetService('CollectionService')
local BedPlates3D = nil local LayerOpt = {Value = 'All'} local MaxShell = {Value = 5} local ShowBed = {Enabled = true}
local Folder = nil local drawn = {}
local CAL = {frameH = 0.6, legH = 0.4, matH = 0.8, blankH = 0.9, pilH = 0.5, W = 4.2, L = 7.2, matW = 3.8, matL = 6.8, blankL = 4.6, pilW = 2.6, pilL = 1.4}
local function clearAll() for _, o in ipairs(drawn) do pcall(function() o:Destroy() end) end table.clear(drawn) end
local function part(parent, size, cf, color, trans) local p = Instance.new('Part') p.Anchored = true p.CanCollide = false p.CanQuery = false p.CanTouch = false p.Size = size p.CFrame = cf p.Color = color p.Material = Enum.Material.SmoothPlastic p.Transparency = trans or 0 p.Parent = parent drawn[#drawn + 1] = p return p end
local function shellOf(dx, dy, dz) local m = math.abs(dx) if math.abs(dy) > m then m = math.abs(dy) end if math.abs(dz) > m then m = math.abs(dz) end return m end
local function bedColor(bed) local c = nil pcall(function() c = bed:GetAttribute('TeamColor') end) if typeof(c) == 'Color3' then return c end pcall(function() local s = bed:GetAttribute('Team') if typeof(s) == 'string' then local cols = {Red = Color3.fromRGB(220, 40, 40), Blue = Color3.fromRGB(40, 120, 220), Green = Color3.fromRGB(40, 180, 70), Yellow = Color3.fromRGB(230, 200, 40)} c = cols[s] end end) return c or Color3.fromRGB(220, 40, 40) end
local function buildBedReplica(bed, baseCF, teamC) local fw = baseCF.LookVector local fwF = Vector3.new(fw.X, 0, fw.Z) if fwF.Magnitude < 0.01 then fwF = Vector3.new(0, 0, 1) end fwF = fwF.Unit local right = Vector3.new(-fwF.Z, 0, fwF.X) local P = baseCF.Position local y0 = P.Y local wood = Color3.fromRGB(101, 67, 33) local white = Color3.fromRGB(245, 245, 245) for _, sx in ipairs({-1, 1}) do for _, sz in ipairs({-1, 1}) do local lp = P + right * (sx * (CAL.W / 2 - 0.3)) + fwF * (sz * (CAL.L / 2 - 0.3)) + Vector3.new(0, CAL.legH / 2, 0) part(Folder, Vector3.new(0.5, CAL.legH, 0.5), CFrame.new(lp), wood) end end part(Folder, Vector3.new(CAL.W, CAL.frameH, CAL.L), CFrame.new(P + Vector3.new(0, CAL.legH + CAL.frameH / 2, 0), fwF), wood) local matY = CAL.legH + CAL.frameH + CAL.matH / 2 part(Folder, Vector3.new(CAL.matW, CAL.matH, CAL.matL), CFrame.new(P + Vector3.new(0, matY, 0), fwF), white) local blankC = P + fwF * (CAL.matL / 2 - CAL.blankL / 2) + Vector3.new(0, CAL.legH + CAL.frameH + CAL.blankH / 2 + 0.05, 0) part(Folder, Vector3.new(CAL.matW + 0.1, CAL.blankH, CAL.blankL), CFrame.new(blankC, fwF), teamC) local pilC = P - fwF * (CAL.matL / 2 - CAL.pilL / 2) + Vector3.new(0, CAL.legH + CAL.frameH + CAL.matH + CAL.pilH / 2 - 0.1, 0) part(Folder, Vector3.new(CAL.pilW, CAL.pilH, CAL.pilL), CFrame.new(pilC, fwF), white) end
local function rebuild() clearAll() if not BedPlates3D or not BedPlates3D.Enabled then return end local bw = g.bedwars local bc = bw and bw.BlockController if not bc then return end local okS, store = pcall(bc.getStore, bc) if not okS or not store then return end local R = math.clamp(MaxShell.Value or 5, 1, 6) local want = LayerOpt.Value or 'All' for _, bed in ipairs(cs:GetTagged('bed')) do local mp = nil local okP = pcall(function() mp = (bed:IsA('Model') and bed:GetPivot() or bed.CFrame) end) if okP and mp then if ShowBed.Enabled then local teamC = bedColor(bed) local groundY = mp.Position.Y pcall(function() local hit = workspace:Raycast(mp.Position + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0)) if hit then groundY = hit.Position.Y end end) buildBedReplica(bed, CFrame.new(Vector3.new(mp.Position.X, groundY, mp.Position.Z), Vector3.new(mp.Position.X, groundY, mp.Position.Z) + Vector3.new(mp.LookVector.X, 0, mp.LookVector.Z)), teamC) end local bp = nil pcall(function() bp = bc:getBlockPosition(mp.Position) end) if bp then for dx = -R, R do for dy = -R, R do for dz = -R, R do local sh = shellOf(dx, dy, dz) if sh >= 1 and sh <= R and (want == 'All' or tonumber(want) == sh) then local gp = bp + Vector3.new(dx, dy, dz) local okB, b = pcall(store.getBlockAt, store, gp) if okB and b ~= nil then local box = Instance.new('BoxHandleAdornment') box.AlwaysOnTop = true box.ZIndex = 4 box.Size = Vector3.new(3, 3, 3) box.CFrame = CFrame.new(gp * 3) box.Color3 = Color3.fromHSV((sh * 0.13) % 1, 0.85, 1) box.Transparency = 0.45 box.Adornee = workspace.CurrentCamera box.Parent = Folder drawn[#drawn + 1] = box end end end end end end end end end
task.spawn(function() local vape = shared.vape Folder = Instance.new('Folder') Folder.Name = 'BedPlates3D' Folder.Parent = workspace BedPlates3D = vape.Categories.Render:CreateModule({Name = 'BedPlates3D', Function = function(cb) if cb then rebuild() else clearAll() end end, Tooltip = 'Modern 3D bed + defense shells with layer selection'}) LayerOpt = BedPlates3D:CreateDropdown({Name = 'Layer', List = {'All', '1', '2', '3', '4', '5', '6'}, Default = 'All', Tooltip = 'Which defense shell to show', Function = function() rebuild() end}) MaxShell = BedPlates3D:CreateSlider({Name = 'Max Shell', Min = 1, Max = 6, Default = 5, Function = function() rebuild() end}) ShowBed = BedPlates3D:CreateToggle({Name = 'Bed Model', Default = true, Tooltip = 'Show the 3D bed replica', Function = function() rebuild() end}) print('[FIX] bedplates3d registered') end)
task.spawn(function() while true do if BedPlates3D ~= nil and BedPlates3D.Enabled then pcall(rebuild) end task.wait(4) end end)
print('[FIX] bedplates3d armed')-- UraniumFix_PlayerDisplay v1 — match-history scout: kits, W/L, RP trend, frequent teammates (party).
local g = getgenv()
g.vape = shared.vape
local rs = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')
local lplr = Players.LocalPlayer
local PlayerDisplay = nil local Target = {Value = ''}
local function notif(a, b) local v = shared.vape if v and type(v.CreateNotification) == 'function' then return v:CreateNotification('PlayerDisplay', tostring(a) .. ' ' .. tostring(b), 6) end print('[PlayerDisplay] ' .. tostring(a) .. ' ' .. tostring(b)) end
local function summarize(userId, name, hist) local n = #hist local wins, kits, mates, rps = 0, {}, {}, {} for _, m in ipairs(hist) do local me = nil if m.players then for _, p in ipairs(m.players) do local id = p.userId or (p.player and p.player.userId) or (p.generic and p.generic.userId) if tostring(id) == tostring(userId) then me = p break end end end if me then local out = me.generic and me.generic.matchOutcome if out == 'WIN' or out == 1 then wins = wins + 1 end local kit = me.bedwars and me.bedwars.kit if kit then kits[tostring(kit)] = (kits[tostring(kit)] or 0) + 1 end local rp = me.ranked and me.ranked.rpDelta if rp then rps[#rps + 1] = tonumber(rp) or 0 end end if m.teams then for _, t in ipairs(m.teams) do local mine = false if t.members then for id, _ in pairs(t.members) do if tostring(id) == tostring(userId) then mine = true break end end end if mine then for id, pl in pairs(t.members) do if tostring(id) ~= tostring(userId) then local nm = type(pl) == 'table' and (pl.name or pl.displayName) or tostring(id) mates[nm] = (mates[nm] or 0) + 1 end end end end end end local function top(tb, k) local arr = {} for name2, c in pairs(tb) do arr[#arr + 1] = {name2, c} end table.sort(arr, function(a, b) return a[2] > b[2] end) local out = {} for i = 1, math.min(k, #arr) do out[#out + 1] = tostring(arr[i][1]) .. 'x' .. tostring(arr[i][2]) end return table.concat(out, ', ') end local rpLast = {} for i = math.max(1, #rps - 4), #rps do rpLast[#rpLast + 1] = tostring(rps[i]) end return name .. ': ' .. tostring(n) .. ' games, ' .. tostring(wins) .. 'W', 'kits: ' .. (top(kits, 3) == '' and '?' or top(kits, 3)), 'rp: ' .. (table.concat(rpLast, '/') == '' and '?' or table.concat(rpLast, '/')), 'often with: ' .. (top(mates, 4) == '' and '?' or top(mates, 4)) end
local function scout() local name = Target.Value or '' if name == '' then notif('set Target username first', '') return end local ok, uid = pcall(function() return Players:GetUserIdFromNameAsync(name) end) if not ok or not uid then notif('unknown user', tostring(name)) return end local Knit = nil pcall(function() Knit = require(rs['rbxts_include']['node_modules']['@easy-games'].knit.src).KnitClient end) local mc = Knit and Knit.Controllers and Knit.Controllers.MatchHistoryController if not mc then notif('no history controller', '') return end notif('fetching', tostring(name) .. '...') task.spawn(function() local ok2, hist = pcall(function() return mc:requestMatchHistory(uid) end) if not ok2 or type(hist) ~= 'table' then notif('request refused/empty', tostring(name)) return end if #hist == 0 then notif('no matches', tostring(name)) return end local l1, l2, l3, l4 = summarize(uid, name, hist) notif(l1, l2) task.wait(1) notif(l3, l4) print('[PlayerDisplay] ' .. l1 .. ' | ' .. l2 .. ' | ' .. l3 .. ' | ' .. l4) end) end
task.spawn(function() local vape = shared.vape PlayerDisplay = vape.Categories.Utility:CreateModule({Name = 'PlayerDisplay', Function = function(cb) if cb then scout() end end, Tooltip = 'Scout a player: recent kits, W/L, RP trend, frequent teammates'}) Target = PlayerDisplay:CreateTextBox({Name = 'Target', Placeholder = 'username', Tooltip = 'Username to scout, then toggle ON'}) print('[FIX] playerdisplay registered') end)
print('[FIX] playerdisplay armed')-- UraniumFix_StoreSync v1 — keeps getgenv().store live (hand+toolType, inventory, match).
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