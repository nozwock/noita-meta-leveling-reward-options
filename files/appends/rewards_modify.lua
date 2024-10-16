local const = dofile_once("mods/meta-leveling-reward-options/files/const.lua") ---@type const
local utils = dofile_once("mods/meta-leveling-reward-options/files/utils.lua") ---@type utils

local rewards_deck = dofile_once("mods/meta_leveling/files/scripts/classes/private/rewards_deck.lua") ---@type rewards_deck
for _, reward in ipairs(rewards_deck.reward_definition_list) do
  reward.mlro_state = {}
  if type(reward.probability) ~= "function" then
    reward.mlro_state.probability = reward.probability
    reward.probability = function()
      return ModSettingGet(utils:ResolveModSettingId(const.reward_setting_prefix ..
            reward.id .. const.reward_setting_suffix.probability)) or
          reward.mlro_state.probability
    end
  end
  if type(reward.custom_check) ~= "function" then
    reward.mlro_state.custom_check = true --- reward always available
    reward.custom_check = function()
      local enable = ModSettingGet(utils:ResolveModSettingId(const.reward_setting_prefix ..
        reward.id .. const.reward_setting_suffix.enable))
      if enable ~= nil then
        return enable
      end
      return true
    end
  end
end
