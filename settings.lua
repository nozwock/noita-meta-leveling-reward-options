---@diagnostic disable: lowercase-global
dofile("data/scripts/lib/mod_settings.lua")

local MOD_ID = "meta-leveling-reward-options" -- This should match the name of your mod's folder.

local utils = {}

---@param id string
function utils:ResolveModSettingId(id)
  return MOD_ID .. "." .. id
end

---For printing.
---@param t table
---@param depth integer|nil
function utils:DumbSerializeTable(t, depth)
  if not depth then
    depth = 1
  end
  local t_prefix = "\n"
  local t_end = "\n}"
  if depth ~= 1 then
    t_prefix = ""
    t_end = "\n" .. string.rep("\t", depth - 1) .. "}"
  end
  local s = { t_prefix .. "{" }
  for k, v in pairs(t) do
    k = tostring(k)
    if type(v) == "table" then
      v = self:DumbSerializeTable(v, depth + 1)
    else
      v = tostring(v)
    end
    table.insert(s, "\n" .. string.rep("\t", depth) .. k .. " = " .. v .. ",")
  end
  s[#s] = s[#s]:gsub(",$", "")
  table.insert(s, t_end)
  return table.concat(s)
end

---@param number number
---@param decimal? integer
function utils:TruncateNumber(number, decimal)
  if decimal <= 0 then
    decimal = nil
  end
  local pow = 10 ^ (decimal or 0)
  return math.floor(number * pow) / pow
end

---@param number number
function utils:FloorSliderValueInteger(number)
  return math.floor(number + 0.5) -- Because the slider can return ranging from 1.8 to 2.3 while showing 2, just as an example
end

---@param number number
---@param decimal? integer
function utils:FloorSliderValueFloat(number, decimal)
  if decimal <= 0 or not decimal then
    decimal = 0
  end
  local pow = 10 ^ (decimal + 1)
  return self:TruncateNumber(number + 5 / pow, decimal)
end

---Both `enum_values` and `info` must have the same size and keys of `info` should be the values in `enum_values`.
---The values in the `info` table must have two items, the option name and its tooltip.
---
---**NOTE:** Order of `enum_values` must be consistent, so don't derive it using `pairs` over a `table`.
---@param enum_values integer[]|string[]
---@param info table
local function CreateGuiSettingEnum(enum_values, info)
  return function(mod_id, gui, in_main_menu, im_id, setting)
    local setting_id = mod_setting_get_id(mod_id, setting)
    local prev_value = ModSettingGetNextValue(setting_id) or setting.value_default

    GuiLayoutBeginHorizontal(gui, mod_setting_group_x_offset, 0, true)

    local value = nil

    if info[prev_value] == nil then
      prev_value = setting.value_default
    end

    if GuiButton(gui, im_id, 0, 0, setting.ui_name .. ": " .. info[prev_value][1]) then
      for i, v in ipairs(enum_values) do
        if prev_value == v then
          value = enum_values[i % #enum_values + 1]
          break
        end
      end
    end
    local right_clicked, hovered = select(2, GuiGetPreviousWidgetInfo(gui))
    if right_clicked then
      value = setting.value_default
      GamePlaySound("data/audio/Desktop/ui.bank", "ui/button_click", 0, 0)
    end
    if hovered then
      GuiTooltip(gui, info[prev_value][2], "")
    end

    GuiLayoutEnd(gui)

    if value ~= nil then
      ModSettingSetNextValue(setting_id, value, false)
      mod_setting_handle_change_callback(mod_id, gui, in_main_menu, setting, prev_value, value)
    end
  end
end


---@param mod_id string
---@param gui gui
---@param in_main_menu boolean
---@param im_id integer
---@param setting mod_setting_number
---@param value_formatting string
---@param value_display_multiplier? number
---@param value_map? fun(value:number):number
local function ModSettingSlider(mod_id, gui, in_main_menu, im_id, setting, value_formatting, value_display_multiplier,
                                value_map)
  local empty = "data/ui_gfx/empty.png"
  local setting_id = mod_setting_get_id(mod_id, setting)
  local value = ModSettingGetNextValue(mod_setting_get_id(mod_id, setting))
  if type(value) ~= "number" then value = setting.value_default or 0.0 end
  setting.ui_name = setting.ui_name or ""

  GuiLayoutBeginHorizontal(gui, mod_setting_group_x_offset, 0, true)

  if setting.value_min == nil or setting.value_max == nil or setting.value_default == nil then
    GuiText(gui, 0, 0, setting.ui_name .. " - not all required values are defined in setting definition")
    return
  end

  GuiText(gui, 0, 0, "")
  local x_start, y_start = select(4, GuiGetPreviousWidgetInfo(gui))

  GuiIdPushString(gui, MOD_ID .. setting_id)

  local value_new = GuiSlider(gui, im_id, 0, 0, setting.ui_name, value, setting.value_min,
    setting.value_max, setting.value_default, setting.value_slider_multiplier or 1, -- This affects the steps for slider aswell, so it's not just a visual thing.
    " ", 64)
  if value_map then
    value_new = value_map(value_new)
  end

  local x_end, _, w = select(4, GuiGetPreviousWidgetInfo(gui))
  local display_text = string.format(value_formatting, value_new * (value_display_multiplier or 1))
  local tw = GuiGetTextDimensions(gui, display_text)
  GuiImageNinePiece(gui, im_id + 1, x_start, y_start, x_end - x_start + w + tw - 2, 8, 0, empty, empty)
  local hovered = select(3, GuiGetPreviousWidgetInfo(gui))

  mod_setting_tooltip(mod_id, gui, in_main_menu, setting)

  if hovered then
    GuiColorSetForNextWidget(gui, 0.8, 0.8, 0.8, 1)
    GuiText(gui, 0, 0, display_text)
  end

  GuiIdPop(gui)
  GuiLayoutEnd(gui)

  if value ~= value_new then
    ModSettingSetNextValue(mod_setting_get_id(mod_id, setting), value_new, false)
    mod_setting_handle_change_callback(mod_id, gui, in_main_menu, setting, value, value_new)
  end
end

local function mod_setting_integer(mod_id, gui, in_main_menu, im_id, setting)
  ModSettingSlider(mod_id, gui, in_main_menu, im_id, setting, setting.value_display_formatting or "%d",
    setting.value_display_multiplier, function(value)
      return utils:FloorSliderValueInteger(value)
    end)
end

local function mod_setting_float(mod_id, gui, in_main_menu, im_id, setting)
  ModSettingSlider(mod_id, gui, in_main_menu, im_id, setting, setting.value_display_formatting or "%.1f",
    setting.value_display_multiplier, function(value)
      return utils:FloorSliderValueFloat(value, setting.value_precision)
    end)
end


-- This is a magic global that can be used to migrate settings to new mod versions.
-- Call mod_settings_get_version() before mod_settings_update() to get the old value.
mod_settings_version = 1

local TYPE = {
  boolean = 1,
  string = 2,
  number = 3,
  table = 4,
  ["nil"] = 5
}

local INIT_FLAG = false
local RUNTIME_FLAG = false
local rewards_deck = {}

---@class setting
---@field id string
---@field type integer
---@field value_default any
---@field ui_fn function

---@class reward_setting
---@field name_key string
---@field settings setting[]
---@field hidden boolean

---@type reward_setting[]
local reward_settings = {}
local reward_setting_prefix = "reward_"
local reward_setting_suffix = {
  probability = "_probability",
  enable = "_enable"
}

---@param reward_settings reward_setting[]
---@param fn fun(setting:setting)
function ForEachSetting(reward_settings, fn)
  for _, reward_setting in ipairs(reward_settings) do
    for _, setting in ipairs(reward_setting.settings) do
      fn(setting)
    end
  end
end

-- todo error handling for when meta leveling isn't enabled
local function RewardsInit()
  rewards_deck = dofile_once("mods/meta_leveling/files/scripts/classes/private/rewards_deck.lua")
  rewards_deck:GatherData()
end

local function GetRewardsList()
  return rewards_deck.reward_definition_list
end

--- Lazy check, checking for only the first item.
---@param list table
local function ValidateRewardsList(list)
  return list[1] and list[1].mlro_state ~= nil
end

---@param settings setting[]
---@param id string
---@param type integer
---@param value_default any
---@param ui_fn function
local function AddToSettings(settings, id, type, value_default, ui_fn)
  table.insert(settings, {
    id = id,
    type = type,
    value_default = value_default,
    ui_fn = ui_fn
  })
  ModSettingSetNextValue(utils:ResolveModSettingId(id), value_default, true) -- set default
end

-- This function is called to ensure the correct setting values are visible to the game. your mod's settings don't work if you don't have a function like this defined in settings.lua.
function ModSettingsUpdate(init_scope)
  local old_version = mod_settings_get_version(MOD_ID) -- This can be used to migrate some settings between mod versions.

  -- Don't do migrations before mod_settings_update. since if it breaks, it'll prevent mod_settings_update from executing.

  if init_scope >= MOD_SETTING_SCOPE_RUNTIME and ModIsEnabled(MOD_ID) then
    if not INIT_FLAG then
      RewardsInit()
      local reward_list = GetRewardsList()
      if ValidateRewardsList(reward_list) then
        for _, reward in ipairs(reward_list) do
          local settings = {} ---@type setting[]
          if reward.mlro_state.custom_check then
            AddToSettings(settings, reward_setting_prefix .. reward.id .. reward_setting_suffix.enable,
              TYPE.boolean, reward.mlro_state.custom_check, function(mod_id, gui, in_main_menu, im_id, setting)
                local value = ModSettingGetNextValue(mod_setting_get_id(mod_id, setting))
                if type(value) ~= "boolean" then value = setting.value_default or false end

                local text = GameTextGet(value and "$option_on" or "$option_off")
                local clicked, right_clicked = GuiButton(gui, im_id, 0, 0, text)
                if clicked then
                  ModSettingSetNextValue(mod_setting_get_id(mod_id, setting), not value, false)
                end
                if right_clicked then
                  local new_value = setting.value_default or false
                  ModSettingSetNextValue(mod_setting_get_id(mod_id, setting), new_value, false)
                end

                mod_setting_tooltip(mod_id, gui, in_main_menu, setting)
              end)
          end
          if reward.mlro_state.probability then
            AddToSettings(settings, reward_setting_prefix .. reward.id .. reward_setting_suffix.probability,
              TYPE.number, reward.mlro_state.probability, function(mod_id, gui, in_main_menu, im_id, setting)
                mod_setting_float(mod_id, gui, in_main_menu, im_id, {
                  id = setting.id,
                  value_default = setting.value_default,
                  value_min = 0,
                  value_max = 1,
                  value_precision = 2,
                  value_display_multiplier = 100,
                  value_display_formatting = " %d%%",
                })
              end)
          end
          if #settings ~= 0 then
            table.insert(reward_settings, {
              name_key = reward.ui_name,
              settings = settings,
              hidden = false
            })
          end
        end

        table.sort(reward_settings, function(a, b)
          return GameTextGetTranslatedOrNot(a.name_key)
              < GameTextGetTranslatedOrNot(b.name_key)
        end)
      end

      INIT_FLAG = true
    end

    ForEachSetting(reward_settings, function(setting)
      local id = utils:ResolveModSettingId(setting.id)
      local next_value = ModSettingGetNextValue(id)
      if next_value ~= nil then
        ModSettingSet(id, next_value)
      end
    end)

    RUNTIME_FLAG = true
  else
    RUNTIME_FLAG = false
  end

  ModSettingSet(utils:ResolveModSettingId("_version"), mod_settings_version)

  -- mod_settings_update(MOD_ID, mod_settings, init_scope)
end

-- This function should return the number of visible setting UI elements.
-- Your mod's settings wont be visible in the mod settings menu if this function isn't defined correctly.
-- If your mod changes the displayed settings dynamically, you might need to implement custom logic for this function.
function ModSettingsGuiCount()
  return 1 -- da fk?
  -- local count = 0
  -- for _, setting in ipairs(reward_settings) do
  --   if not setting.hidden then
  --     count = count + #setting.group
  --   end
  -- end
  -- return count
  -- return mod_settings_gui_count(MOD_ID, mod_settings)
end

local function IdFactory()
  local id = 1000

  return function()
    id = id + 1
    return id
  end
end

local search_text = ""

-- This function is called to display the settings UI for this mod. your mod's settings wont be visible in the mod settings menu if this function isn't defined correctly.
function ModSettingsGui(gui, in_main_menu)
  --- tell that setting is only available in-game in ModSettingGui
  -- mod_settings_gui(MOD_ID, mod_settings, gui, in_main_menu)
  GuiIdPushString(gui, MOD_ID)

  if not in_main_menu and RUNTIME_FLAG and INIT_FLAG then
    local id = IdFactory()
    GuiOptionsAdd(gui, GUI_OPTION.DrawActiveWidgetCursorOnBothSides)
    GuiLayoutBeginHorizontal(gui, 0, 0, true)
    local clicked_clear_search = GuiButton(gui, id(), 0, 0, "Clear search")
    GuiText(gui, 0, 0, "  ")
    local clicked_reset = GuiButton(gui, id(), 0, 0, "Reset all")
    GuiLayoutEnd(gui)
    local new_search_text = GuiTextInput(gui, id(), 0, 0, search_text, 130, 30)
    GuiOptionsRemove(gui, GUI_OPTION.DrawActiveWidgetCursorOnBothSides)

    if clicked_clear_search then
      new_search_text = ""
    elseif clicked_reset then
      ForEachSetting(reward_settings, function(setting)
        ModSettingSetNextValue(utils:ResolveModSettingId(setting.id), setting.value_default, false)
      end)
    end

    if new_search_text ~= search_text then
      search_text = new_search_text
      new_search_text = new_search_text:lower():gsub("%s+", " ")
      if new_search_text == "" then
        for _, reward_setting in ipairs(reward_settings) do reward_setting.hidden = false end
      else
        for _, reward_setting in ipairs(reward_settings) do
          local setting_name = GameTextGetTranslatedOrNot(reward_setting.name_key):lower():gsub("%s+", " ")
          reward_setting.hidden = setting_name:find(new_search_text, 0, true) == nil
        end
      end
    end

    GuiLayoutBeginVertical(gui, 0, 0, true)

    for _, reward_setting in ipairs(reward_settings) do
      if reward_setting.hidden then goto continue end

      GuiLayoutBeginHorizontal(gui, 0, 0, true)

      GuiOptionsAdd(gui, GUI_OPTION.Layout_InsertOutsideLeft)
      GuiText(gui, 0, 0, GameTextGetTranslatedOrNot(reward_setting.name_key))
      GuiOptionsRemove(gui, GUI_OPTION.Layout_InsertOutsideLeft)

      for _, setting in ipairs(reward_setting.settings) do
        setting.ui_fn(MOD_ID, gui, in_main_menu, id(), setting)
      end

      GuiLayoutEnd(gui)

      ::continue::
    end

    GuiLayoutEnd(gui)
  else
    GuiColorSetForNextWidget(gui, 1, 1, 1, 0.5)
    GuiText(gui, 0, 0, "Rewards can only be configured in-game.")
  end

  GuiIdPop(gui)
end
