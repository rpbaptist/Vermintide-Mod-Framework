local vmf = get_mod("VMF")

--[[ Valid locale codes:

  en      English
  fr      French
  de      German
  es      Spanish
  ru      Russian
  br-pt   Portuguese-Brazil
  it      Italian
  pl      Polish
]]

local _language_id = Application.user_setting("language_id")
local _injected_text_ids = {}

-- ####################################################################################################################
-- ##### Local functions ##########################################################################################{{{1
-- ####################################################################################################################

local function safe_string_format(mod, str, ...)

  -- An invalid format specifier may cause a crash by sending the error handler into an infinite recursion.
  local success, message = pcall(string.format, str, ...)

  if success then
    return message
  else
    mod:error("(localize) \"%s\": %s", tostring(str), tostring(message))
  end
end

-- ####################################################################################################################
-- ##### VMFMod ###################################################################################################{{{1
-- ####################################################################################################################

function VMFMod:localize_raw(text_id)

  local mod_localization_table = self:get_internal_data("localization_database")

  if mod_localization_table then
  
    local text_translations = mod_localization_table[text_id]
    if text_translations then
      return text_translations[_language_id] or text_translations["en"]
    end
  end
end

function VMFMod:localize(text_id, ...)

  local mod_localization_table = self:get_internal_data("localization_database")
  if mod_localization_table then

    local text_translations = mod_localization_table[text_id]
    if text_translations then

      local message

      if text_translations[_language_id] then

        message = safe_string_format(self, text_translations[_language_id], ...)
        if message then
          return message
        end
      end

      if text_translations["en"] then

        message = safe_string_format(self, text_translations["en"], ...)
        if message then
          return message
        end
      end
    end
  else
    self:error("(localize): localization file was not loaded for this mod")
  end

  return "<" .. tostring(text_id) .. ">"
end

-- ####################################################################################################################
-- ##### VMF internal functions and variables #####################################################################{{{1
-- ####################################################################################################################

function vmf.initialize_mod_localization(mod, localization_table)

  if type(localization_table) ~= "table" then
    mod:error("(localization): localization file should return table")
    return false
  end

  if mod:get_internal_data("localization_database") then
    mod:warning("(localization): overwritting already loaded localization file")
  end

  vmf.set_internal_data(mod, "localization_database", localization_table)

  -- Register the global localizations.
  for text_id, text_translations in pairs(localization_table) do
    if text_translations.global then
      if _injected_text_ids[text_id] then
        local other_mod_name = _injected_text_ids[text_id]:get_name()
        mod:error("(load_mod_localization): Attempting to redefine global text_id `%s` already defined by `%s`",
                  text_id, other_mod_name)
      else
        _injected_text_ids[text_id] = mod
      end
    end
  end

  return true
end

-- ####################################################################################################################
-- ##### Script ###################################################################################################{{{1
-- ####################################################################################################################

local localization_table = vmf:dofile("localization/vmf")
vmf.initialize_mod_localization(vmf, localization_table)

-- ####################################################################################################################
-- ##### Hooks ####################################################################################################{{{1
-- ####################################################################################################################

vmf:hook(LocalizationManager, "_base_lookup", function (func, self, text_id)
  local mod = _injected_text_ids[text_id]
  if mod then
    local text = mod:localize_raw(text_id)
    if text then
      return text
    end
  end

  return func(self, text_id)
end)
