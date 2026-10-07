	local fmt = string.format
	local SourceCount = props["Source Count"].Value
	local DestCount   = props["Destination Count"].Value

	-- Router binding and diagnostics ---------------------------------------------
	table.insert(ctrls, {
		Name = "router_select",
		ControlType = "Text",
		Count = 1,
		UserPin = true,
		PinStyle = "Both"
	})
	table.insert(ctrls, {
		Name = "router_found",
		ControlType = "Indicator",
		IndicatorType = "Led",
		DefaultValue = false,
		Count = 1,
		UserPin = true,
		PinStyle = "Output"
	})
	-- Which select-control naming form resolved on the bound component.
	-- Classic Router = "select.N", MediaCast Router = "output.N.select".
	table.insert(ctrls, {
		Name = "router_style",
		ControlType = "Indicator",
		IndicatorType = "Text",
		Count = 1,
		UserPin = true,
		PinStyle = "Output"
	})
	table.insert(ctrls, {
		Name = "status",
		ControlType = "Indicator",
		IndicatorType = "Status",
		Count = 1,
		UserPin = true,
		PinStyle = "Output"
	})

	-- Mode selection -------------------------------------------------------------
	table.insert(ctrls, {
		Name = "mode_matrix",
		ControlType = "Button",
		ButtonType = "Toggle",
		Count = 1,
		UserPin = true,
		PinStyle = "Both"
	})
	table.insert(ctrls, {
		Name = "mode_all",
		ControlType = "Button",
		ButtonType = "Toggle",
		Count = 1,
		UserPin = true,
		PinStyle = "Both"
	})
	table.insert(ctrls, {
		Name = "mode_name",
		ControlType = "Indicator",
		IndicatorType = "Text",
		Count = 1,
		UserPin = true,
		PinStyle = "Output"
	})
	-- Whichever axis is the interlocked selector reports its selection here. In
	-- destination-first order only selected_dest_name is populated; in
	-- source-first order only selected_source_name is.
	table.insert(ctrls, {
		Name = "selected_dest_name",
		ControlType = "Indicator",
		IndicatorType = "Text",
		Count = 1,
		UserPin = true,
		PinStyle = "Output"
	})
	table.insert(ctrls, {
		Name = "selected_source_name",
		ControlType = "Indicator",
		IndicatorType = "Text",
		Count = 1,
		UserPin = true,
		PinStyle = "Output"
	})

	-- Destinations ---------------------------------------------------------------
	for thisDest = 1, DestCount do
		-- Interlocked destination selector (One-To-One mode).
		table.insert(ctrls, {
			Name = fmt("dest_select_%03d", thisDest),
			ControlType = "Button",
			ButtonType = "Toggle",
			Count = 1,
			UserPin = true,
			PinStyle = "Both"
		})
		-- User-supplied destination label.
		table.insert(ctrls, {
			Name = fmt("dest_name_%03d", thisDest),
			ControlType = "Text",
			Count = 1,
			UserPin = true,
			PinStyle = "Both"
		})
		-- Drive low to hide this destination (nothing plugged in).
		table.insert(ctrls, {
			Name = fmt("dest_visible_%03d", thisDest),
			ControlType = "Button",
			ButtonType = "Toggle",
			DefaultValue = true,
			Count = 1,
			UserPin = true,
			PinStyle = "Both"
		})
		-- Source currently routed to this destination. Laid out as a ComboBox, so
		-- it both reads the route back and sets it.
		table.insert(ctrls, {
			Name = fmt("dest_source_%03d", thisDest),
			ControlType = "Text",
			Count = 1,
			UserPin = true,
			PinStyle = "Both"
		})
		-- Numeric readout of the routed source index (0 = none / unknown).
		table.insert(ctrls, {
			Name = fmt("dest_route_%03d", thisDest),
			ControlType = "Knob",
			ControlUnit = "Integer",
			Min = 0,
			Max = 64,
			DefaultValue = 0,
			Count = 1,
			UserPin = true,
			PinStyle = "Output"
		})
	end

	-- Sources --------------------------------------------------------------------
	for thisSource = 1, SourceCount do
		-- Press to route. Lit state is driven from router feedback, never from
		-- the press itself.
		table.insert(ctrls, {
			Name = fmt("source_select_%03d", thisSource),
			ControlType = "Button",
			ButtonType = "Toggle",
			Count = 1,
			UserPin = true,
			PinStyle = "Both"
		})
		table.insert(ctrls, {
			Name = fmt("source_name_%03d", thisSource),
			ControlType = "Text",
			Count = 1,
			UserPin = true,
			PinStyle = "Both"
		})
		-- Drive low to hide this source (nothing plugged in).
		table.insert(ctrls, {
			Name = fmt("source_visible_%03d", thisSource),
			ControlType = "Button",
			ButtonType = "Toggle",
			DefaultValue = true,
			Count = 1,
			UserPin = true,
			PinStyle = "Both"
		})
	end
