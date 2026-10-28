-- Information block for the plugin
--[[ #include "info.lua" ]]

-- Resources (palette, page list)
--[[ #include "resources.lua" ]]

-- Define the colour of the plugin object in the design
function GetColor(props)
	return Palette.navy
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
