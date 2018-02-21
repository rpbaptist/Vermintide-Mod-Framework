local manager = new_mod("vmf_mutator_manager")


-- List of mods that are also mutators in order in which they should be enabled
-- This is populated via VMFMod.register_as_mutator
manager.mutators = {}
local mutators = manager.mutators

local mutators_config = {}
local default_config = manager:dofile("scripts/mods/vmf/modules/mutators/mutator_default_config")

-- This lists mutators and which ones should be enabled after them
-- This is populated via VMFMod.register_as_mutator
local mutators_sequence = {
	--[[
	this_mutator = {
		"will be enabled",
		"before these ones"
	}
	]]--
}

-- So we don't sort after each one is added
local mutators_sorted = false


--[[
	PUBLIC METHODS
]]--

-- Sorts mutators in order they should be enabled
manager.sort_mutators = function()

	if mutators_sorted then return end

	-- LOG --
	manager:dump(mutators_sequence, "seq", 5)
	for i, v in ipairs(mutators) do
		print(i, v:get_name())
	end
	print("-----------")
	-- /LOG --

	-- Preventing endless loops (worst case is n*(n+1)/2 I believe)
	local maxIter = #mutators * (#mutators + 1)/2
	local numIter = 0

	-- The idea is that all mutators before the current one are already in the right order
	-- Starting from second mutator
	local i = 2
	while i <= #mutators do
		local mutator = mutators[i]
		local mutator_name = mutator:get_name()
		local enable_these_after = mutators_sequence[mutator_name] or {}

		-- Going back from the previous mutator to the start of the list
		local j = i - 1
		while j > 0 do
			local other_mutator = mutators[j]

			-- Moving it after the current one if it is to be enabled after it
			if table.has_item(enable_these_after, other_mutator:get_name()) then
				table.remove(mutators, j)
				table.insert(mutators, i, other_mutator)

				-- This will shift the current mutator back, so adjust the index
				i = i - 1
			end
			j = j - 1
		end

		i = i + 1

		numIter = numIter + 1
		if numIter > maxIter then
			manager:error("Mutators: too many iterations. Check for loops in 'enable_before_these'/'enable_after_these'.")
			return
		end
	end
	mutators_sorted = true

	-- LOG --
	for k, v in ipairs(mutators) do
		print(k, v:get_name())
	end
	print("-----------")
	-- /LOG --
end

-- Disables mutators that cannot be enabled right now
manager.disable_impossible_mutators = function()
	local disabled_mutators = {}
	for _, mutator in pairs(mutators) do
		if mutator:is_enabled() and not mutator:can_be_enabled() then
			mutator:disable()
			table.insert(disabled_mutators, mutator)
		end
	end
	return disabled_mutators
end


--[[
	PRIVATE METHODS
]]--

local mutators_view = manager:dofile("scripts/mods/vmf/modules/mutators/mutator_gui")
local addDice, removeDice = manager:dofile("scripts/mods/vmf/modules/mutators/mutator_dice")
local set_lobby_data = manager:dofile("scripts/mods/vmf/modules/mutators/mutator_info")

-- Adds mutator names from enable_these_after to the list of mutators that should be enabled after the mutator_name
local function update_mutators_sequence(mutator_name, enable_these_after)
	if not mutators_sequence[mutator_name] then
		mutators_sequence[mutator_name] = {}
	end
	for _, other_mutator_name in ipairs(enable_these_after) do

		if mutators_sequence[other_mutator_name] and table.has_item(mutators_sequence[other_mutator_name], mutator_name) then
			manager:error("Mutators '" .. mutator_name .. "' and '" .. other_mutator_name .. "' are both set to load after the other one.")
		elseif not table.has_item(mutators_sequence[mutator_name], other_mutator_name) then
			table.insert(mutators_sequence[mutator_name], other_mutator_name)
		end

	end
	table.combine(mutators_sequence[mutator_name], enable_these_after)
end

-- Checks if mutators are compatible both ways
local function is_compatible(mutator, other_mutator)
	local config = mutator:get_config()
	local name = mutator:get_name()
	local other_config = other_mutator:get_config()
	local other_name = other_mutator:get_name()

	local incompatible_specifically = (
		#config.incompatible_with > 0 and (
			table.has_item(config.incompatible_with, other_name)
		) or
		#other_config.incompatible_with > 0 and (
			table.has_item(other_config.incompatible_with, name)
		)
	)

	local compatible_specifically = (
		#config.compatible_with > 0 and (
			table.has_item(config.compatible_with, other_name)
		) or
		#other_config.compatible_with > 0 and (
			table.has_item(other_config.compatible_with, name)
		)
	)

	local compatible
	if incompatible_specifically then
		compatible = false
	elseif compatible_specifically then
		compatible = true
	elseif config.compatible_with_all or other_config.compatible_with_all then
		compatible = true
	elseif config.incompatible_with_all or other_config.incompatible_with_all then
		compatible = false
	else
		compatible = true
	end

	return compatible
end

-- Disables enabled mutators that aren't compatible with the specified
local function disable_incompatible_with(mutator)
	local names = nil
	for _, other_mutator in ipairs(mutators) do
		if (
			other_mutator ~= mutator and
			other_mutator:is_enabled() and
			not is_compatible(mutator, other_mutator)
		) then
			other_mutator:disable()
			local name = other_mutator:get_config().title or other_mutator:get_name()
			if names then
				names = names .. " " .. name
			else
				names = name
			end
		end
	end
	if names then
		-- TODO: output this to the menu instead of chat
		manager:echo("These mutators are incompatible with " .. mutator:get_name() .. " and were disabled: " .. names)
	end
end

-- Called after mutator is enabled
local function on_enabled(mutator)
	local config = mutator:get_config()
	addDice(config.dice)
	set_lobby_data()
end

-- Called after mutator is disabled
local function on_disabled(mutator)
	local config = mutator:get_config()
	removeDice(config.dice)
	set_lobby_data()
end

-- Enables/disables mutator while preserving the sequence in which they were enabled
local function set_mutator_state(mutator, state)

	local i = table.index_of(mutators, mutator)
	if i == nil then
		mutator:error("Mutator isn't in the list")
		return
	end

	if state == mutator:is_enabled() then
		return
	end

	if state and not mutator:can_be_enabled() then
		return
	end

	-- Sort mutators if this is the first call
	if not mutators_sorted then
		manager.sort_mutators()
	end

	-- Disable mutators that aren't compatible
	if state then
		disable_incompatible_with(mutator)
	end

	local disabled_mutators = {}
	local enable_these_after = mutators_sequence[mutator:get_name()]

	-- Disable mutators that were and are required to be enabled after the current one
	-- This will be recursive so that if mutator2 requires mutator3 to be enabled after it, mutator3 will be disabled before mutator2
	-- Yeah this is super confusing
	if enable_these_after and #mutators > i then
		for j = #mutators, i + 1, -1 do
			if mutators[j]:is_enabled() and table.has_item(enable_these_after, mutators[j]:get_name()) then
				print("Disabled ", mutators[j]:get_name())
				mutators[j]:disable()
				table.insert(disabled_mutators, 1, mutators[j])
			end
		end
	end

	-- Enable/disable current mutator
	-- We're calling methods on the class object because we've overwritten them on the current one
	if state then
		print("Enabled ", mutator:get_name(), "!")
		VMFMod.enable(mutator)
		on_enabled(mutator)
	else
		print("Disabled ", mutator:get_name(), "!")
		VMFMod.disable(mutator)
		on_disabled(mutator)
	end

	-- Re-enable disabled mutators
	-- This will be recursive
	if #disabled_mutators > 0 then
		for j = #disabled_mutators, 1, -1 do
			print("Enabled ", disabled_mutators[j]:get_name())
			disabled_mutators[j]:enable()
		end
	end

	print("---------")
end


--[[
	MUTATOR'S OWN METHODS
]]--

-- Enables mutator (pcall for now)
local function enable_mutator(self)
	manager:pcall(function() set_mutator_state(self, true) end)
end

-- Disables mutator (pcall for now)
local function disable_mutator(self)
	manager:pcall(function() set_mutator_state(self, false) end)
end

-- Checks current difficulty and map selection screen settings to determine if a mutator can be enabled
local function can_be_enabled(self)

	local mutator_difficulties = self:get_config().difficulties

	local actual_difficulty = Managers.state and Managers.state.difficulty:get_difficulty()
	local right_difficulty = not actual_difficulty or table.has_item(mutator_difficulties, actual_difficulty)

	local map_view = mutators_view.map_view
	local map_view_active = map_view and map_view.active
	local right_unapplied_difficulty = false

	if map_view_active then

		local difficulty_data = map_view.selected_level_index and map_view:get_difficulty_data(map_view.selected_level_index)
		local difficulty_layout = difficulty_data and difficulty_data[map_view.selected_difficulty_stepper_index]
		local difficulty_key = difficulty_layout and difficulty_layout.key
		right_unapplied_difficulty = difficulty_key and table.has_item(mutator_difficulties, difficulty_key)
	end

	return (map_view_active and right_unapplied_difficulty) or (not map_view_active and right_difficulty)
end

-- Returns the config object for mutator from mutators_config
local function get_config(self)
	return mutators_config[self:get_name()]
end

-- Turns a mod into a mutator
VMFMod.register_as_mutator = function(self, config)
	if not config then config = {} end

	local mod_name = self:get_name()

	if table.has_item(mutators, self) then
		self:error("Mod is already registered as mutator")
		return
	end

	table.insert(mutators, self)

	-- Save config
	mutators_config[mod_name] = table.clone(default_config)
	local _config = mutators_config[mod_name]
	for k, _ in pairs(_config) do
		if config[k] ~= nil then
			_config[k] = config[k]
		end
	end
	if _config.short_title == "" then _config.short_title = nil end
	if _config.title == "" then _config.title = nil end

	if config.enable_before_these then
		update_mutators_sequence(mod_name, config.enable_before_these)
	end

	if config.enable_after_these then
		for _, other_mod_name in ipairs(config.enable_after_these) do
			update_mutators_sequence(other_mod_name, {mod_name})
		end
	end

	self.enable = enable_mutator
	self.disable = disable_mutator
	self.can_be_enabled = can_be_enabled

	self.get_config = get_config

	mutators_sorted = false

	-- Always init in the off state
	self:init_state(false)
end


--[[
	HOOKS
]]--
manager:hook("DifficultyManager.set_difficulty", function(func, self, difficulty)
	local disabled_mutators = manager.disable_impossible_mutators()
	if #disabled_mutators > 0 then
		local message = "MUTATORS DISABLED DUE TO DIFFICULTY CHANGE:"
		for _, mutator in ipairs(disabled_mutators) do
			message = message .. " " .. mutator:get_config().title or mutator:get_name()
		end
		Managers.chat:send_system_chat_message(1, message, 0, true)
	end
	return func(self, difficulty)
end)


















--[[
	Testing
--]]
local mutator2 = new_mod("mutator2")
local mutator3 = new_mod("mutator3")
local mutator555 = new_mod("mutator555")

mutator555:register_as_mutator({
	compatible_with_all = true,
	incompatible_with = {
		"mutator2"
	}
})
mutator555:create_options({}, true, "mutator555", "mutator555 description")
mutator555.on_enabled = function() end
mutator555.on_disabled = function() end


mutator3:register_as_mutator({
	compatible_with_all = true,
	incompatible_with = {
		"mutator555"
	}
})
mutator3:create_options({}, true, "mutator3", "mutator3 description")
mutator3.on_enabled = function() end
mutator3.on_disabled = function() end

mutator2:register_as_mutator({
	difficulties = {
		"hardest"
	}
})
mutator2:create_options({}, true, "mutator2", "mutator2 description")
mutator2.on_enabled = function() end
mutator2.on_disabled = function() end