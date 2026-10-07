	local fmt = string.format
	local pidx = (props["page_index"] and props["page_index"].Value) or 1
	local CurrentPage = PageNames[pidx]

	local SourceCount = props["Source Count"].Value
	local DestCount   = props["Destination Count"].Value
	local SourceFirst = (props["Matrix Select Order"].Value == "Source First")

	local G       = Geometry
	local fs      = G.fs
	local rowH    = G.rowH
	local btnW    = G.btnW
	local btnH    = G.btnH
	local nameW   = G.nameW
	local labelH  = G.labelH
	local colRows = G.COLUMN_ROWS

	-- Grid geometry. Both grids wrap into columns of COLUMN_ROWS entries.
	local destCols = math.ceil(DestCount / colRows)
	local destRows = math.min(DestCount, colRows)
	local srcCols  = math.ceil(SourceCount / colRows)
	local srcRows  = math.min(SourceCount, colRows)

	local destCellW = btnW + 6 + nameW + 6 + nameW
	local srcCellW  = btnW + 6 + G.srcNameW

	local destGW = 16 + destCols * destCellW + (destCols - 1) * 12
	local srcGW  = 16 + srcCols * srcCellW + (srcCols - 1) * 12

	-- Sources on the left, destinations on the right: signal flows left to right.
	local gridY = 34
	local srcGX, srcGY = 0, gridY
	local srcGH = 28 + srcRows * rowH + 10
	local destGX, destGY = srcGX + srcGW + 14, gridY
	local destGH = 28 + destRows * rowH + 10

	local totalW = destGX + destGW
	local footY  = gridY + math.max(destGH, srcGH) + 14

	-- Shared cell-position helper for a wrapping grid.
	local function CellPos(index, originX, originY, cellW)
		local col = math.floor((index - 1) / colRows)
		local row = (index - 1) % colRows
		return originX + 8 + col * (cellW + 12), originY + 28 + row * rowH
	end

	local function TitleBlock(width)
		table.insert(graphics, {
			Type = "Text", Text = "Q-SYS Video Router", FontSize = 16,
			FontStyle = "Bold", HTextAlign = "Left", Color = Palette.cti_navy,
			Position = {0, 4}, Size = {320, 24}
		})
		table.insert(graphics, {
			Type = "Text", Text = "v" .. PluginInfo.BuildVersion, FontSize = fs,
			HTextAlign = "Right", Color = Palette.Gray,
			Position = {width - 120, 8}, Size = {120, labelH}
		})
	end

	if CurrentPage == "Control" then

		TitleBlock(totalW)

		-- Sources --------------------------------------------------------------
		-- Group titles carry the step order so the surface reads correctly
		-- without a separate instruction line.
		table.insert(graphics, {
			Type = "GroupBox",
			Text = SourceFirst and "Sources (1. select)" or "Sources (2. route)",
			FontSize = fs, HTextAlign = "Left",
			Fill = Palette.White, StrokeColor = Palette.cti_navy, StrokeWidth = 1,
			CornerRadius = 8, Position = {srcGX, srcGY}, Size = {srcGW, srcGH}
		})
		for thisSource = 1, SourceCount do
			local cellX, cellY = CellPos(thisSource, srcGX, srcGY, srcCellW)
			layout[fmt("source_select_%03d", thisSource)] = {
				PrettyName = fmt("Sources~%d Select", thisSource),
				Legend = tostring(thisSource), FontSize = fs, Style = "Button",
				Color = Palette.green_on, OffColor = Palette.cti_navy, UnlinkOffColor = true,
				Margin = 3, Position = {cellX, cellY}, Size = {btnW, btnH}
			}
			layout[fmt("source_name_%03d", thisSource)] = {
				PrettyName = fmt("Sources~%d Name", thisSource),
				Style = "Text", FontSize = fs, HTextAlign = "Left",
				Color = Palette.White, Padding = 2, StrokeWidth = 1,
				Position = {cellX + btnW + 6, cellY + 1}, Size = {G.srcNameW, btnH - 2}
			}
		end

		-- Destinations ---------------------------------------------------------
		table.insert(graphics, {
			Type = "GroupBox",
			Text = SourceFirst and "Destinations (2. route to)" or "Destinations (1. select)",
			FontSize = fs, HTextAlign = "Left",
			Fill = Palette.White, StrokeColor = Palette.cti_navy, StrokeWidth = 1,
			CornerRadius = 8, Position = {destGX, destGY}, Size = {destGW, destGH}
		})
		for thisCol = 0, destCols - 1 do
			local headX = destGX + 8 + thisCol * (destCellW + 12)
			table.insert(graphics, {
				Type = "Text", Text = "Routed Source", FontSize = 10, HTextAlign = "Left",
				Color = Palette.Gray,
				Position = {headX + btnW + 12 + nameW, destGY + 12}, Size = {nameW, 14}
			})
		end

		for thisDest = 1, DestCount do
			local cellX, cellY = CellPos(thisDest, destGX, destGY, destCellW)
			layout[fmt("dest_select_%03d", thisDest)] = {
				PrettyName = fmt("Destinations~%d Select", thisDest),
				Legend = tostring(thisDest), FontSize = fs, Style = "Button",
				Color = Palette.cti_amber, OffColor = Palette.cti_navy, UnlinkOffColor = true,
				Margin = 3, Position = {cellX, cellY}, Size = {btnW, btnH}
			}
			layout[fmt("dest_name_%03d", thisDest)] = {
				PrettyName = fmt("Destinations~%d Name", thisDest),
				Style = "Text", FontSize = fs, HTextAlign = "Left",
				Color = Palette.White, Padding = 2, StrokeWidth = 1,
				Position = {cellX + btnW + 6, cellY + 1}, Size = {nameW, btnH - 2}
			}
			-- ComboBox, not a readout: picking a source here routes this output.
			layout[fmt("dest_source_%03d", thisDest)] = {
				PrettyName = fmt("Destinations~%d Routed Source", thisDest),
				Style = "ComboBox", FontSize = fs,
				Color = Palette.White, Padding = 2, StrokeWidth = 1,
				Position = {cellX + btnW + 6 + nameW + 6, cellY + 1}, Size = {nameW, btnH - 2}
			}
		end

		-- Footer: bound router and status --------------------------------------
		table.insert(graphics, {
			Type = "GroupBox", Text = "Router", FontSize = fs, HTextAlign = "Left",
			Fill = Palette.White, StrokeColor = Palette.cti_navy, StrokeWidth = 1,
			CornerRadius = 8, Position = {0, footY}, Size = {totalW, 58}
		})
		layout["status"] = {
			PrettyName = "Router~Status", Style = "Text", FontSize = fs,
			HTextAlign = "Left", Color = Palette.White, Padding = 2, StrokeWidth = 1,
			Position = {12, footY + 22}, Size = {totalW - 220, btnH}
		}
		table.insert(graphics, {
			Type = "Text", Text = "Naming", FontSize = fs, HTextAlign = "Right",
			Color = Palette.cti_navy, Position = {totalW - 202, footY + 25}, Size = {56, labelH}
		})
		layout["router_style"] = {
			PrettyName = "Router~Control Naming", Style = "Text", FontSize = fs,
			HTextAlign = "Center", Color = Palette.White, Padding = 2, StrokeWidth = 1,
			Position = {totalW - 142, footY + 22}, Size = {104, btnH}
		}
		layout["router_found"] = {
			PrettyName = "Router~Found", Style = "Indicator",
			Color = Palette.Green, OffColor = Palette.led_off, UnlinkOffColor = true,
			StrokeWidth = 1, Margin = 2,
			Position = {totalW - 28, footY + 26}, Size = {18, 18}
		}

	elseif CurrentPage == "Setup" then

		local setupW = 470
		TitleBlock(setupW)

		-- Router binding -------------------------------------------------------
		table.insert(graphics, {
			Type = "GroupBox", Text = "Router Component", FontSize = fs, HTextAlign = "Left",
			Fill = Palette.White, StrokeColor = Palette.cti_navy, StrokeWidth = 1,
			CornerRadius = 8, Position = {0, 34}, Size = {setupW, 92}
		})
		table.insert(graphics, {
			Type = "Text", Text = "Router", FontSize = fs, HTextAlign = "Left",
			Color = Palette.cti_navy, Position = {12, 59}, Size = {50, labelH}
		})
		layout["router_select"] = {
			PrettyName = "Router~Component", Style = "ComboBox", FontSize = fs,
			Color = Palette.White, Padding = 2, StrokeWidth = 1,
			Position = {64, 56}, Size = {setupW - 104, 24}
		}
		layout["router_found"] = {
			PrettyName = "Router~Found", Style = "Indicator",
			Color = Palette.Green, OffColor = Palette.led_off, UnlinkOffColor = true,
			StrokeWidth = 1, Margin = 2, Position = {setupW - 28, 59}, Size = {18, 18}
		}
		layout["status"] = {
			PrettyName = "Router~Status", Style = "Text", FontSize = fs,
			HTextAlign = "Left", Color = Palette.White, Padding = 2, StrokeWidth = 1,
			Position = {12, 90}, Size = {setupW - 140, 24}
		}
		layout["router_style"] = {
			PrettyName = "Router~Control Naming", Style = "Text", FontSize = fs,
			HTextAlign = "Center", Color = Palette.White, Padding = 2, StrokeWidth = 1,
			Position = {setupW - 120, 90}, Size = {108, 24}
		}

		-- Current selection ----------------------------------------------------
		-- Only the interlocked axis has a meaningful selection, so the other
		-- readout stays empty; both are drawn so neither pin is hidden.
		table.insert(graphics, {
			Type = "GroupBox",
			Text = SourceFirst and "Selection (source first)" or "Selection (destination first)",
			FontSize = fs, HTextAlign = "Left",
			Fill = Palette.White, StrokeColor = Palette.cti_navy, StrokeWidth = 1,
			CornerRadius = 8, Position = {0, 134}, Size = {setupW, 58}
		})
		table.insert(graphics, {
			Type = "Text", Text = "Source", FontSize = 10, HTextAlign = "Left",
			Color = Palette.Gray, Position = {12, 156}, Size = {50, 14}
		})
		layout["selected_source_name"] = {
			PrettyName = "Mode~Selected Source", Style = "Text", FontSize = fs,
			HTextAlign = "Center", Color = Palette.White, Padding = 2, StrokeWidth = 1,
			Position = {64, 154}, Size = {140, 24}
		}
		table.insert(graphics, {
			Type = "Text", Text = "Destination", FontSize = 10, HTextAlign = "Left",
			Color = Palette.Gray, Position = {216, 156}, Size = {70, 14}
		})
		layout["selected_dest_name"] = {
			PrettyName = "Mode~Selected Destination", Style = "Text", FontSize = fs,
			HTextAlign = "Center", Color = Palette.White, Padding = 2, StrokeWidth = 1,
			Position = {288, 154}, Size = {setupW - 300, 24}
		}

		-- Source setup ---------------------------------------------------------
		-- A GroupBox title is drawn as a tab hanging down from the top border, so
		-- the column headers sit below it (hdrDY) rather than beside it, where the
		-- "Name" header collided with the "Sources" / "Destinations" title.
		local hdrDY = 18
		local rowDY = 36
		local sSetupY = 200
		local sSetupH = rowDY + SourceCount * rowH + 10
		table.insert(graphics, {
			Type = "GroupBox", Text = "Sources", FontSize = fs, HTextAlign = "Left",
			Fill = Palette.White, StrokeColor = Palette.cti_navy, StrokeWidth = 1,
			CornerRadius = 8, Position = {0, sSetupY}, Size = {setupW, sSetupH}
		})
		table.insert(graphics, {
			Type = "Text", Text = "Name", FontSize = 10, HTextAlign = "Left",
			Color = Palette.Gray, Position = {44, sSetupY + hdrDY}, Size = {60, 14}
		})
		table.insert(graphics, {
			Type = "Text", Text = "Visible", FontSize = 10, HTextAlign = "Center",
			Color = Palette.Gray, Position = {setupW - 132, sSetupY + hdrDY}, Size = {56, 14}
		})
		for thisSource = 1, SourceCount do
			local rowY = sSetupY + rowDY + (thisSource - 1) * rowH
			table.insert(graphics, {
				Type = "Text", Text = tostring(thisSource), FontSize = fs, HTextAlign = "Right",
				Color = Palette.cti_navy, Position = {8, rowY + 3}, Size = {28, labelH}
			})
			layout[fmt("source_name_%03d", thisSource)] = {
				PrettyName = fmt("Sources~%d Name", thisSource),
				Style = "Text", FontSize = fs, HTextAlign = "Left",
				Color = Palette.White, Padding = 2, StrokeWidth = 1,
				Position = {44, rowY + 1}, Size = {setupW - 190, btnH - 2}
			}
			layout[fmt("source_visible_%03d", thisSource)] = {
				PrettyName = fmt("Sources~%d Visible", thisSource),
				Legend = "", Style = "Button",
				Color = Palette.green_on, OffColor = Palette.gray_off, UnlinkOffColor = true,
				Margin = 3, Position = {setupW - 122, rowY}, Size = {36, btnH}
			}
		end

		-- Destination setup ----------------------------------------------------
		local dSetupY = sSetupY + sSetupH + 14
		local dSetupH = rowDY + DestCount * rowH + 10
		table.insert(graphics, {
			Type = "GroupBox", Text = "Destinations", FontSize = fs, HTextAlign = "Left",
			Fill = Palette.White, StrokeColor = Palette.cti_navy, StrokeWidth = 1,
			CornerRadius = 8, Position = {0, dSetupY}, Size = {setupW, dSetupH}
		})
		table.insert(graphics, {
			Type = "Text", Text = "Name", FontSize = 10, HTextAlign = "Left",
			Color = Palette.Gray, Position = {44, dSetupY + hdrDY}, Size = {60, 14}
		})
		table.insert(graphics, {
			Type = "Text", Text = "Visible", FontSize = 10, HTextAlign = "Center",
			Color = Palette.Gray, Position = {setupW - 132, dSetupY + hdrDY}, Size = {56, 14}
		})
		table.insert(graphics, {
			Type = "Text", Text = "Route", FontSize = 10, HTextAlign = "Center",
			Color = Palette.Gray, Position = {setupW - 64, dSetupY + hdrDY}, Size = {52, 14}
		})
		for thisDest = 1, DestCount do
			local rowY = dSetupY + rowDY + (thisDest - 1) * rowH
			table.insert(graphics, {
				Type = "Text", Text = tostring(thisDest), FontSize = fs, HTextAlign = "Right",
				Color = Palette.cti_navy, Position = {8, rowY + 3}, Size = {28, labelH}
			})
			layout[fmt("dest_name_%03d", thisDest)] = {
				PrettyName = fmt("Destinations~%d Name", thisDest),
				Style = "Text", FontSize = fs, HTextAlign = "Left",
				Color = Palette.White, Padding = 2, StrokeWidth = 1,
				Position = {44, rowY + 1}, Size = {setupW - 190, btnH - 2}
			}
			layout[fmt("dest_visible_%03d", thisDest)] = {
				PrettyName = fmt("Destinations~%d Visible", thisDest),
				Legend = "", Style = "Button",
				Color = Palette.green_on, OffColor = Palette.gray_off, UnlinkOffColor = true,
				Margin = 3, Position = {setupW - 122, rowY}, Size = {36, btnH}
			}
			layout[fmt("dest_route_%03d", thisDest)] = {
				PrettyName = fmt("Destinations~%d Routed Index", thisDest),
				Style = "Text", FontSize = fs, HTextAlign = "Center",
				Color = Palette.White, OffColor = Palette.White, UnlinkOffColor = true,
				Padding = 2, StrokeWidth = 1,
				Position = {setupW - 64, rowY + 1}, Size = {52, btnH - 2}
			}
		end

	end
