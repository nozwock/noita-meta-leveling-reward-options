---@diagnostic disable: lowercase-global
dofile("data/scripts/lib/mod_settings.lua")

local MOD_ID = "meta-leveling-reward-options" -- This should match the name of your mod's folder.

local utils = {}

---@param id string
function utils:ResolveModSettingId(id) return MOD_ID .. "." .. id end

--- Returns translated text from $string
--- @param string string should be in $string format
--- @return string
function Locale(string)
  local pattern = "%$%w[%w_]*"
  string = string:gsub(pattern, GameTextGetTranslatedOrNot, 1)
  if string:find(pattern) then
    return Locale(string)
  else
    return string
  end
end

---@param number number
---@param decimal? integer
function utils:TruncateNumber(number, decimal)
  if decimal <= 0 then decimal = nil end
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
  if decimal <= 0 or not decimal then decimal = 0 end
  local pow = 10 ^ (decimal + 1)
  return self:TruncateNumber(number + 5 / pow, decimal)
end

---@param gui gui
local function GetPreviousWidget(gui)
  local clicked, right_clicked, hovered, x, y, width, height = GuiGetPreviousWidgetInfo(gui)
  ---@class widget_info
  ---@field clicked boolean
  ---@field right_clicked  boolean
  ---@field hovered boolean
  ---@field x number
  ---@field y number
  ---@field width number
  ---@field height number
  return {
    clicked = clicked,
    right_clicked = right_clicked,
    hovered = hovered,
    x = x,
    y = y,
    width = width,
    height = height,
  }
end

---@param mod_id string
---@param gui gui
---@param in_main_menu boolean
---@param im_id integer
---@param setting mod_setting_number
---@param value_formatting string
---@param value_display_multiplier? number
---@param value_map? fun(value:number):number
---@param width? integer
local function ModSettingSlider(
  mod_id,
  gui,
  in_main_menu,
  im_id,
  setting,
  value_formatting,
  value_display_multiplier,
  value_map,
  width
)
  local empty = "data/ui_gfx/empty.png"
  local setting_id = mod_setting_get_id(mod_id, setting)
  local value = ModSettingGetNextValue(mod_setting_get_id(mod_id, setting))
  if type(value) ~= "number" then value = setting.value_default or 0.0 end
  setting.ui_name = setting.ui_name or ""

  if setting.value_min == nil or setting.value_max == nil or setting.value_default == nil then
    GuiText(
      gui,
      mod_setting_group_x_offset,
      0,
      setting.ui_name .. " - not all required values are defined in setting definition"
    )
    return
  end

  GuiText(gui, mod_setting_group_x_offset, 0, "")
  local start = GetPreviousWidget(gui)

  GuiIdPushString(gui, MOD_ID .. setting_id)

  width = width or 64
  local value_new = GuiSlider(
    gui,
    im_id,
    mod_setting_group_x_offset,
    0,
    setting.ui_name,
    value,
    setting.value_min,
    setting.value_max,
    setting.value_default,
    setting.value_slider_multiplier or 1, -- This affects the steps for slider aswell, so it's not just a visual thing.
    " ",
    width
  )
  if value_map then value_new = value_map(value_new) end

  local slider_info = GetPreviousWidget(gui)
  local display_text = string.format(value_formatting, value_new * (value_display_multiplier or 1))
  local tw = GuiGetTextDimensions(gui, display_text)

  mod_setting_tooltip(mod_id, gui, in_main_menu, setting)

  GuiColorSetForNextWidget(gui, 1, 1, 1, 0.5)
  GuiText(gui, mod_setting_group_x_offset + width + 4, 0, display_text) -- note: xy values from GetPrevious are on global coordinates system

  GuiImageNinePiece(
    gui,
    im_id + 2,
    start.x,
    start.y,
    slider_info.x - start.x + slider_info.width + tw - 2,
    slider_info.height,
    0,
    empty,
    empty
  )

  GuiIdPop(gui)

  if value ~= value_new then
    ModSettingSetNextValue(mod_setting_get_id(mod_id, setting), value_new, false)
    mod_setting_handle_change_callback(mod_id, gui, in_main_menu, setting, value, value_new)
  end
end

local function mod_setting_integer(mod_id, gui, in_main_menu, im_id, setting, width)
  ModSettingSlider(
    mod_id,
    gui,
    in_main_menu,
    im_id,
    setting,
    setting.value_display_formatting or "%d",
    setting.value_display_multiplier,
    function(value) return utils:FloorSliderValueInteger(value) end,
    width
  )
end

local function mod_setting_float(mod_id, gui, in_main_menu, im_id, setting, width)
  ModSettingSlider(
    mod_id,
    gui,
    in_main_menu,
    im_id,
    setting,
    setting.value_display_formatting or "%.1f",
    setting.value_display_multiplier,
    function(value) return utils:FloorSliderValueFloat(value, setting.value_precision) end,
    width
  )
end

-- This is a magic global that can be used to migrate settings to new mod versions.
-- Call mod_settings_get_version() before mod_settings_update() to get the old value.
mod_settings_version = 1

local TYPE = {
  boolean = 1,
  string = 2,
  number = 3,
  table = 4,
  ["nil"] = 5,
}

local ML_FLAG = {
  ENABLED = 1,
  DISABLED = 2,
  INIT_FAIL = 3,
}

local INIT_FLAG = false
local META_LEVELING = { flag = ML_FLAG.DISABLED }
local RUNTIME_FLAG = false
local rewards_deck = {}

---@class setting
---@field id string
---@field type integer
---@field value_default any
---@field ui_fn function

---@class reward_description
---@field key? string
---@field var? string

---@class reward_setting
---@field id string
---@field name_key string
---@field description reward_description
---@field ui_icon string
---@field settings setting[]
---@field hidden boolean
---@field _text? string
---@field _description? string

---@type reward_setting[]
local reward_settings = {}
local reward_setting_prefix = "reward_"
local reward_setting_suffix = {
  probability = "_probability",
  enable = "_enable",
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

-- todo: error handling for when meta leveling isn't enabled
local function RewardsInit()
  rewards_deck = dofile_once("mods/meta_leveling/files/scripts/classes/private/rewards_deck.lua")
  rewards_deck:GatherData()
end

local function GetRewardsList() return rewards_deck.reward_definition_list end

---@param settings setting[]
---@param id string
---@param type integer
---@param value_default any
---@param ui_fn function
local function AddToSettings(settings, id, type, value_default, ui_fn)
  settings[#settings + 1] = {
    id = id,
    type = type,
    value_default = value_default,
    ui_fn = ui_fn,
  }
  ModSettingSetNextValue(utils:ResolveModSettingId(id), value_default, true) -- set default
end

---@param reward_setting reward_setting
local function ResetTextStrings(reward_setting)
  -- Resetting cached translations
  local reward_name = Locale(reward_setting.name_key)
  if reward_name ~= "" then
    reward_setting._text = reward_name
  else
    reward_setting._text = reward_setting.id
  end
  reward_setting._description = rewards_deck:UnpackDescription(
    reward_setting.description.key,
    reward_setting.description.var
  ) or ""
end

-- This function is called to ensure the correct setting values are visible to the game. your mod's settings don't work if you don't have a function like this defined in settings.lua.
function ModSettingsUpdate(init_scope)
  local old_version = mod_settings_get_version(MOD_ID) -- This can be used to migrate some settings between mod versions.

  -- Don't do migrations before mod_settings_update. since if it breaks, it'll prevent mod_settings_update from executing.

  if init_scope >= MOD_SETTING_SCOPE_RUNTIME and ModIsEnabled(MOD_ID) then
    if not INIT_FLAG then
      if not ModIsEnabled("meta_leveling") then goto skip_init end
      META_LEVELING = { flag = ML_FLAG.ENABLED }

      do
        local ok, result = pcall(RewardsInit)
        if not ok then
          META_LEVELING = { flag = ML_FLAG.INIT_FAIL, extra = result }
          goto skip_init
        end
      end

      for _, reward in ipairs(GetRewardsList()) do
        if reward.mlro_state == nil then goto continue end

        local settings = {} ---@type setting[]
        if reward.mlro_state.custom_check then
          AddToSettings(
            settings,
            reward_setting_prefix .. reward.id .. reward_setting_suffix.enable,
            TYPE.boolean,
            true,
            function(mod_id, gui, in_main_menu, im_id, setting)
              local value = ModSettingGetNextValue(mod_setting_get_id(mod_id, setting))
              if type(value) ~= "boolean" then value = setting.value_default or false end

              local text = GameTextGet(value and "$option_on" or "$option_off")
              GuiOptionsAddForNextWidget(gui, GUI_OPTION.DrawActiveWidgetCursorOnBothSides)
              local clicked, right_clicked = GuiButton(gui, im_id, mod_setting_group_x_offset, 0, text)
              if clicked then ModSettingSetNextValue(mod_setting_get_id(mod_id, setting), not value, false) end
              if right_clicked then
                local new_value = setting.value_default or false
                ModSettingSetNextValue(mod_setting_get_id(mod_id, setting), new_value, false)
              end

              mod_setting_tooltip(mod_id, gui, in_main_menu, setting)
            end
          )
        end
        if reward.mlro_state.probability then
          AddToSettings(
            settings,
            reward_setting_prefix .. reward.id .. reward_setting_suffix.probability,
            TYPE.number,
            reward.mlro_state.probability,
            function(mod_id, gui, in_main_menu, im_id, setting)
              mod_setting_float(mod_id, gui, in_main_menu, im_id, {
                id = setting.id,
                value_default = setting.value_default,
                value_min = 0,
                value_max = 1,
                value_precision = 2,
                value_display_multiplier = 100,
                value_display_formatting = " %d%%",
              })
            end
          )
        end
        if #settings ~= 0 then
          reward_settings[#reward_settings + 1] = {
            id = reward.id,
            name_key = reward.ui_name,
            description = {
              key = reward.description,
              var = reward.description_var,
            },
            ui_icon = reward.ui_icon,
            settings = settings,
            hidden = false,
          }
        end

        ::continue::
      end

      -- todo? Add an option to toggle b/w sort by name and id
      table.sort(
        reward_settings,
        function(a, b) return GameTextGetTranslatedOrNot(a.id) < GameTextGetTranslatedOrNot(b.id) end
      )

      ::skip_init::

      INIT_FLAG = true
    end

    for _, reward_setting in ipairs(reward_settings) do
      ResetTextStrings(reward_setting)
      for _, setting in ipairs(reward_setting.settings) do
        local id = utils:ResolveModSettingId(setting.id)
        local next_value = ModSettingGetNextValue(id)
        if next_value ~= nil then ModSettingSet(id, next_value) end
      end
    end

    RUNTIME_FLAG = true
  else
    RUNTIME_FLAG = false
  end

  ModSettingSet(utils:ResolveModSettingId("_version"), mod_settings_version)
end

-- This function should return the number of visible setting UI elements.
-- Your mod's settings wont be visible in the mod settings menu if this function isn't defined correctly.
-- If your mod changes the displayed settings dynamically, you might need to implement custom logic for this function.
function ModSettingsGuiCount()
  return 1 -- No idea why I'm doing this, just copied it from 'Start With Any Perks'
end

local function IdFactory()
  local id = 1000

  return function()
    id = id + 1
    return id
  end
end

---@param gui gui
---@param id integer
---@param x integer
---@param y integer
---@param icon string
---@param alpha number
---@param scale number
function DrawRewardIcon(gui, id, x, y, icon, alpha, scale)
  scale = scale or 1
  if icon:find("%.xml") then
    GuiImage(gui, id, x, y, icon, alpha, scale, 0, 0, GUI_RECT_ANIMATION_PLAYBACK.Loop)
    return
  end
  local width, height = GuiGetImageDimensions(gui, icon, 1)
  local x_offset = (16 - width) / 2 * scale
  local y_offset = (16 - height) / 2 * scale
  GuiImage(gui, id, x + x_offset, y + y_offset, icon, alpha, scale, 0, 0, GUI_RECT_ANIMATION_PLAYBACK.Loop)
end

local search_text = ""

---@param text string
---@return string
function WrapText(text)
  text = text:gsub("\r+", ""):gsub("\n\n+", "\n")

  local words = {}
  for word in string.gmatch(text, "[^%s]+%s*") do
    table.insert(words, word)
  end

  local wrapped_text = unpack(words, 1, 1)
  local char_count = string.len(wrapped_text)
  for _, word in pairs({ unpack(words, 2) }) do
    char_count = char_count + string.len(word)
    if char_count > 80 then
      wrapped_text = string.gsub(wrapped_text, "%s+$", "") .. "\n"
      char_count = string.len(word)
    end
    wrapped_text = wrapped_text .. word
  end

  return wrapped_text
end

-- This function is called to display the settings UI for this mod. your mod's settings wont be visible in the mod settings menu if this function isn't defined correctly.
function ModSettingsGui(gui, in_main_menu)
  if META_LEVELING.flag == ML_FLAG.INIT_FAIL then
    GuiColorSetForNextWidget(gui, 1, 0.5, 0.5, 0.8)
    GuiText(
      gui,
      0,
      0,
      WrapText(
        "Some error occurred while patching Meta Leveling; either it's due to a bug on the Meta Leveling side, or this mod's logic needs to be updated."
      )
    )
    GuiText(gui, 0, 0, " ")
    GuiColorSetForNextWidget(gui, 1, 1, 1, 0.5)
    GuiText(gui, 0, 0, "Detailed error report:\n--------------")
    GuiColorSetForNextWidget(gui, 1, 1, 1, 0.5)
    GuiText(gui, 0, 0, WrapText(META_LEVELING.extra))
    return
  end

  if not in_main_menu and RUNTIME_FLAG and INIT_FLAG then
    if META_LEVELING.flag == ML_FLAG.DISABLED then
      GuiColorSetForNextWidget(gui, 1, 0.5, 0.5, 0.8)
      GuiText(gui, 0, 0, "This requires the Meta Leveling mod to be enabled.")
      return
    end

    GuiIdPushString(gui, MOD_ID)
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
      ForEachSetting(
        reward_settings,
        function(setting) ModSettingSetNextValue(utils:ResolveModSettingId(setting.id), setting.value_default, false) end
      )
    end

    if new_search_text ~= search_text then -- todo? Use distance based matching
      search_text = new_search_text
      new_search_text = new_search_text:lower():gsub("%s+", " ")
      if new_search_text == "" then
        for _, reward_setting in ipairs(reward_settings) do
          reward_setting.hidden = false
        end
      else
        for _, reward_setting in ipairs(reward_settings) do
          local setting_name = reward_setting._text:lower():gsub("%s+", " ")
          local setting_description = reward_setting._description:lower():gsub("%s+", " ")
          reward_setting.hidden = not (
            setting_name:find(new_search_text, 0, true) ~= nil
            or setting_description:find(new_search_text, 0, true) ~= nil
          )
        end
      end
    end

    GuiLayoutAddVerticalSpacing(gui, 2)

    for _, reward_setting in ipairs(reward_settings) do
      if reward_setting.hidden then goto continue end

      GuiLayoutAddVerticalSpacing(gui, 2)

      GuiOptionsAdd(gui, GUI_OPTION.Layout_NextSameLine)

      DrawRewardIcon(gui, id(), 0, 0, reward_setting.ui_icon, 1, 0.8)

      GuiText(gui, 18, 0, reward_setting._text)
      GuiTooltip(gui, reward_setting.id, reward_setting._description)

      local offset = 10
      mod_setting_group_x_offset = 150
      for _, setting in ipairs(reward_setting.settings) do
        if
          #reward_setting.settings == 1
          and reward_setting.settings[1].id:find(reward_setting_suffix.probability .. "$", 0) ~= nil
        then -- don't think about it, and give up the thought of doing nolla gui while you still can.
          mod_setting_group_x_offset = mod_setting_group_x_offset + offset + 10
        end
        setting.ui_fn(MOD_ID, gui, in_main_menu, id(), setting)
        mod_setting_group_x_offset = mod_setting_group_x_offset + offset + 10
      end
      GuiOptionsRemove(gui, GUI_OPTION.Layout_NextSameLine)
      mod_setting_group_x_offset = 0

      GuiText(gui, 0, 0, " ")

      ::continue::
    end

    GuiIdPop(gui)
  else
    GuiColorSetForNextWidget(gui, 1, 1, 1, 0.5)
    GuiText(gui, 0, 0, "Rewards can only be configured in-game.")
  end
end
