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
