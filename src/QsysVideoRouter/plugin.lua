-- Information block for the plugin
--[[ #include "info.lua" ]]

--[[
###############################################################################
#
# Q-SYS Video Router
# Copyright 2026 Communication Technologies, Inc. (CTI)
#
# Front end for a Router / Router with Mixer / MediaCast Router component in
# the design. Sources are on the left, destinations on the right. Two routing
# modes:
#
#   One-To-One (Matrix) -- pick a source, then the destinations to send it to.
#                          Source buttons are interlocked; every destination
#                          already carrying the armed source highlights.
#                          "Matrix Select Order" flips the two axes.
#   One-To-All          -- pick a source; it is routed to every router output.
#
# Each destination also carries a routed-source ComboBox, which both reads the
# route back and sets it.
#
# Per-source and per-destination visibility input pins hide entries that are
# not physically connected.
#
# Based on the QSC, LLC. plugin framework.
#
###############################################################################
]]

-- Resources (palette, page list)
--[[ #include "resources.lua" ]]

-- Define the colour of the plugin object in the design
function GetColor(props)
	return Palette.cti_navy
end

-- The name that initially displays when dragged into a design
function GetPrettyName(props)
	return "Q-SYS Video Router v" .. PluginInfo.Version
end

-- Optional function used if the plugin has multiple pages
function GetPages(props)
	local pages = {}
	--[[ #include "pages.lua" ]]
	return pages
end

-- Optional function to define model if the plugin supports more than one model
function GetModel(props)
	local model = {}
	--[[ #include "model.lua" ]]
	return model
end

-- Define user-configurable Properties of the plugin
function GetProperties()
	local props = {}
	--[[ #include "properties.lua" ]]
	return props
end

-- Optional function to define pins not connected to a Control
function GetPins(props)
	local pins = {}
	--[[ #include "pins.lua" ]]
	return pins
end

-- Optional function to update available properties when properties are altered
function RectifyProperties(props)
	--[[ #include "rectify_properties.lua" ]]
	return props
end

-- Optional function to define components used within the plugin
function GetComponents(props)
	local components = {}
	--[[ #include "components.lua" ]]
	return components
end

-- Optional function to define wiring of components used within the plugin
function GetWiring(props)
	local wiring = {}
	--[[ #include "wiring.lua" ]]
	return wiring
end

-- Defines the Controls used within the plugin
function GetControls(props)
	local ctrls = {}
	--[[ #include "controls.lua" ]]
	return ctrls
end

-- Layout of controls and graphics for the plugin UI
function GetControlLayout(props)
	local layout = {}
	local graphics = {}
	--[[ #include "layout.lua" ]]
	return layout, graphics
end

-- Start event-based logic
if Controls then
	--[[ #include "runtime.lua" ]]
end
