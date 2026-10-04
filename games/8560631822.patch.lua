-- Forwarder: sub-place patch loads the canonical BedWars patch (fixes + modules).
local license = ... or {}
local ok, src = pcall(function()
if isfile('aetherv2/games/6872274481.patch.lua') then
return readfile('aetherv2/games/6872274481.patch.lua')
end
return shared.AetherV2FetchSource('aetherv2/games/6872274481.patch.lua')
end)
if ok and type(src) == 'string' and #src > 0 then
local chunk, err = loadstring(src, '6872274481-patch')
if chunk then
local ok2, err2 = pcall(chunk, license)
if not ok2 then warn('[Uranium] canonical patch failed: ' .. tostring(err2)) end
else
warn('[Uranium] canonical patch compile failed: ' .. tostring(err))
end
else
warn('[Uranium] canonical patch unavailable')
end
