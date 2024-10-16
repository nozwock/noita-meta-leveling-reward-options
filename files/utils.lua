local const = dofile_once("mods/noita/meta-leveling-reward-options/files/const.lua") ---@type const

---@class utils
local utils = {}

---@param id string
function utils:ResolveModSettingId(id)
  return const.MOD_ID .. "." .. id
end

return utils
