	local fmt = string.format

	local SourceCount = Properties["Source Count"].Value
	local DestCount   = Properties["Destination Count"].Value
	local DefaultMode = Properties["Default Mode"].Value
	local DebugMode   = Properties["Debug Print"].Value

	local function dbg(...)
		if DebugMode ~= "None" then print("[VidRouter]", ...) end
	end

	local function dbgRoute(...)
		if DebugMode == "Routes" or DebugMode == "All" then print("[VidRouter]", ...) end
	end

	local STATUS = {OK = 0, COMPROMISED = 1, FAULT = 2, NOT_PRESENT = 3, MISSING = 5}

	local MODE_MATRIX = "matrix"
	local MODE_ALL    = "all"

	-- Which axis is the interlocked selector in One-To-One mode.
	--   ORDER_SOURCE -- pick a source, then pick the destinations to send it to
	--                   (default)
	--   ORDER_DEST   -- pick a destination, then pick its source
	local ORDER_DEST   = "dest"
	local ORDER_SOURCE = "source"
	local SelectOrder  =
		(Properties["Matrix Select Order"].Value == "Source First") and ORDER_SOURCE or ORDER_DEST

	local RouterProxy     = nil    -- bound router component, or nil
	local SelectCtlCache  = {}     -- [destination] = resolved select control name
	local BoundSelectCtls = {}     -- [destination] = control name we subscribed to
	local SelectedDest    = 1      -- interlocked selection when ORDER_DEST
	local SelectedSource  = 1      -- interlocked selection when ORDER_SOURCE
	local Mode            = (DefaultMode == "One-To-All") and MODE_ALL or MODE_MATRIX

	-- Depth counter, not a boolean: nested feedback writes must not clear the
	-- guard early. See qsys_preferences.md (write-suppression rules).
	local Suppress = 0
	local function BeginSuppress() Suppress = Suppress + 1 end
	local function EndSuppress()
		Suppress = Suppress - 1
		if Suppress < 0 then Suppress = 0 end
	end
	local function Suppressed() return Suppress > 0 end

	-- ===== Conditional writers =====
	-- Every feedback write is conditional so a settled control emits no events
	-- at all. This is the load-bearing protection against feedback loops; the
	-- suppression counter above is only a fast path.
	local function SetBool(ctl, want)
		if ctl ~= nil and ctl.Boolean ~= want then ctl.Boolean = want end
	end

	local function SetString(ctl, want)
		if ctl ~= nil and ctl.String ~= want then ctl.String = want end
	end

	local function SetValue(ctl, want)
		if ctl ~= nil and ctl.Value ~= want then ctl.Value = want end
	end

	local function SetFlag(ctl, flag, want)
		if ctl ~= nil and ctl[flag] ~= want then ctl[flag] = want end
	end

	local function SetStatus(code, message)
		local ctl = Controls["status"]
		if ctl == nil then return end
		SetValue(ctl, code)
		SetString(ctl, message)
	end

	-- ===== Control accessors =====
	local function DestCtl(kind, thisDest)
		return Controls[fmt("dest_%s_%03d", kind, thisDest)]
	end

	local function SourceCtl(kind, thisSource)
		return Controls[fmt("source_%s_%03d", kind, thisSource)]
	end

	local function DestVisible(thisDest)
		local ctl = DestCtl("visible", thisDest)
		return (ctl == nil) or ctl.Boolean
	end

	local function SourceVisible(thisSource)
		local ctl = SourceCtl("visible", thisSource)
		return (ctl == nil) or ctl.Boolean
	end

	local function SourceLabel(thisSource)
		if thisSource == nil then return "" end
		local ctl = SourceCtl("name", thisSource)
		if ctl ~= nil and ctl.String ~= nil and ctl.String ~= "" then return ctl.String end
		return fmt("Source %d", thisSource)
	end

	local function DestLabel(thisDest)
		if thisDest == nil then return "" end
		local ctl = DestCtl("name", thisDest)
		if ctl ~= nil and ctl.String ~= nil and ctl.String ~= "" then return ctl.String end
		return fmt("Destination %d", thisDest)
	end

	local function FirstVisibleDest()
		for thisDest = 1, DestCount do
			if DestVisible(thisDest) then return thisDest end
		end
		return 1
	end

	local function FirstVisibleSource()
		for thisSource = 1, SourceCount do
			if SourceVisible(thisSource) then return thisSource end
		end
		return 1
	end

	-- ===== Routed-source combo boxes =====
	-- Each destination's routed-source field is a ComboBox: it reads the route
	-- back and can also set it. A choice string has to map back to exactly one
	-- source, so two sources sharing a name are disambiguated by index.
	--
	-- A router output cannot be unrouted -- select is 1-based with no "off"
	-- position -- so the list carries sources only. An output whose route cannot
	-- be read reads back blank rather than offering a way to clear it.
	local ChoiceLabel = {}     -- [source] = unique label for that source
	local ChoiceIndex = {}     -- [label]  = source index
	local ChoiceList  = {}     -- ordered choices offered on every destination
	local ChoiceSig   = nil    -- signature of the last list written

	local function BuildSourceChoices()
		ChoiceLabel = {}
		ChoiceIndex = {}
		ChoiceList  = {}
		local taken = {}
		for thisSource = 1, SourceCount do
			local label = SourceLabel(thisSource)
			if taken[label] then label = fmt("%s (%d)", label, thisSource) end
			taken[label] = true
			ChoiceLabel[thisSource] = label
			ChoiceIndex[label] = thisSource
			-- A hidden source is not part of the surface, so it is not offered.
			if SourceVisible(thisSource) then table.insert(ChoiceList, label) end
		end
	end

	-- Writing Choices raises no control event, but the list only changes when a
	-- name or a visibility flag does, so skip the write while it is settled.
	local function WriteSourceChoices()
		local sig = table.concat(ChoiceList, "\n")
		if sig == ChoiceSig then return end
		ChoiceSig = sig
		BeginSuppress()
		for thisDest = 1, DestCount do
			local ctl = DestCtl("source", thisDest)
			if ctl ~= nil then ctl.Choices = ChoiceList end
		end
		local selectedCtl = Controls["selected_dest_source"]
		if selectedCtl ~= nil then selectedCtl.Choices = ChoiceList end
		EndSuppress()
	end

	local function RefreshSourceChoices()
		BuildSourceChoices()
		WriteSourceChoices()
	end

	-- ===== Router component access =====
	local function HasControl(comp, name)
		if comp == nil then return false end
		local ok, ctl = pcall(function() return comp[name] end)
		return ok and ctl ~= nil
	end

	-- The classic Router / Router with Mixer names the output selector
	-- "select.N". The MediaCast Router renamed it to "output.N.select" -- the
	-- index comes BEFORE "select". Hardcoding either form silently fails on the
	-- other (no error, the control just never resolves), so probe both and
	-- cache the winner per destination.
	local function ResolveSelectCtl(thisDest)
		if SelectCtlCache[thisDest] ~= nil then return SelectCtlCache[thisDest] end
		if RouterProxy == nil then return nil end
		local candidates = {fmt("select.%d", thisDest), fmt("output.%d.select", thisDest)}
		for _, thisCandidate in ipairs(candidates) do
			if HasControl(RouterProxy, thisCandidate) then
				SelectCtlCache[thisDest] = thisCandidate
				return thisCandidate
			end
		end
		return nil
	end

	local function GetRoute(thisDest)
		local selCtl = ResolveSelectCtl(thisDest)
		if selCtl == nil then return nil end
		local routed
		local ok = pcall(function() routed = RouterProxy[selCtl].Value end)
		if not ok or routed == nil then return nil end
		return math.floor(routed)
	end

	local function SetRoute(thisDest, thisSource)
		local selCtl = ResolveSelectCtl(thisDest)
		if selCtl == nil then return false end
		local applied = false
		pcall(function()
			local current = RouterProxy[selCtl].Value
			if current == nil or math.floor(current) ~= thisSource then
				RouterProxy[selCtl].Value = thisSource
			end
			applied = true
		end)
		if applied then dbgRoute("routed destination", thisDest, "<- source", thisSource) end
		return applied
	end

	-- ===== Feedback =====
	-- In One-To-All mode a source lights only when every destination sits on it.
	local function CommonRoute()
		local common = nil
		for thisDest = 1, DestCount do
			local routed = GetRoute(thisDest)
			if routed == nil then return nil end
			if common == nil then
				common = routed
			elseif common ~= routed then
				return nil
			end
		end
		return common
	end

	-- Source buttons are the interlocked selector in source-first order, and a
	-- readout of the selected destination's route otherwise.
	local function WriteSourceButtons()
		local lit
		if Mode == MODE_ALL then
			lit = CommonRoute()
		elseif SelectOrder == ORDER_SOURCE then
			lit = SelectedSource
		else
			lit = GetRoute(SelectedDest)
		end
		BeginSuppress()
		for thisSource = 1, SourceCount do
			-- A hidden entry is not part of the surface, so it never stays lit.
			SetBool(SourceCtl("select", thisSource),
				(thisSource == lit) and SourceVisible(thisSource))
		end
		EndSuppress()
	end

	-- Destination buttons are the interlocked selector in destination-first
	-- order. In source-first order they instead show every output that already
	-- carries the selected source, so more than one can be lit.
	local function WriteDestButtons()
		local destText, sourceText = "", ""
		if Mode == MODE_ALL then
			destText = "All"
		elseif SelectOrder == ORDER_SOURCE then
			sourceText = SourceLabel(SelectedSource)
		else
			destText = DestLabel(SelectedDest)
		end

		BeginSuppress()
		for thisDest = 1, DestCount do
			local lit = false
			if Mode == MODE_MATRIX then
				if SelectOrder == ORDER_SOURCE then
					lit = (SelectedSource ~= nil) and (GetRoute(thisDest) == SelectedSource)
				else
					lit = (thisDest == SelectedDest)
				end
			end
			-- A hidden entry is not part of the surface, so it never stays lit.
			SetBool(DestCtl("select", thisDest), lit and DestVisible(thisDest))
		end
		SetString(Controls["selected_dest_name"], destText)
		SetString(Controls["selected_source_name"], sourceText)
		EndSuppress()
	end

	-- The routed-source combo must read back a string from its own choice list,
	-- so the label comes from this plugin's source names, not from whatever the
	-- router calls the source.
	local function RouteLabel(routed)
		if routed == nil or routed < 1 then return "" end  -- unbound or unresolved
		return ChoiceLabel[routed] or fmt("Source %d", routed)
	end

	local function WriteRouteReadouts()
		BeginSuppress()
		for thisDest = 1, DestCount do
			local routed = GetRoute(thisDest)
			SetString(DestCtl("source", thisDest), RouteLabel(routed))
			SetValue(DestCtl("route", thisDest), routed or 0)
		end
		-- Destination-first selection combo: the selected destination's route,
		-- or in One-To-All (where it is locked out) the source every output
		-- shares, matching what the source buttons light.
		local selectedCtl = Controls["selected_dest_source"]
		if selectedCtl ~= nil then
			-- Not "a and b or c": CommonRoute() is nil when outputs differ.
			local routed
			if Mode == MODE_ALL then
				routed = CommonRoute()
			else
				routed = GetRoute(SelectedDest)
			end
			SetString(selectedCtl, RouteLabel(routed))
		end
		EndSuppress()
	end

	-- Single idempotent refresh. Every write inside is conditional, so calling
	-- this more often than strictly needed costs a few comparisons and cannot
	-- generate control events on a settled system.
	local function RefreshAll()
		WriteDestButtons()
		WriteSourceButtons()
		WriteRouteReadouts()
	end

	-- ===== Visibility =====
	-- Sources / destinations that are not physically connected are hidden. The
	-- same pins are exposed so a UCI can bind element visibility to them.
	local function ApplyVisibility()
		-- The routed-source combos only offer visible sources, so their choice
		-- list is rebuilt whenever visibility changes.
		RefreshSourceChoices()
		for thisSource = 1, SourceCount do
			local hidden = not SourceVisible(thisSource)
			SetFlag(SourceCtl("select", thisSource), "IsInvisible", hidden)
			SetFlag(SourceCtl("select", thisSource), "IsDisabled", hidden)
			SetFlag(SourceCtl("name", thisSource), "IsInvisible", hidden)
		end
		for thisDest = 1, DestCount do
			local hidden = not DestVisible(thisDest)
			SetFlag(DestCtl("select", thisDest), "IsInvisible", hidden)
			-- Destination selection is also meaningless in One-To-All mode.
			SetFlag(DestCtl("select", thisDest), "IsDisabled", hidden or (Mode == MODE_ALL))
			SetFlag(DestCtl("name", thisDest), "IsInvisible", hidden)
			SetFlag(DestCtl("source", thisDest), "IsInvisible", hidden)
			-- Routing one output on its own contradicts One-To-All, so the combo
			-- is locked out there just like the destination button.
			SetFlag(DestCtl("source", thisDest), "IsDisabled", hidden or (Mode == MODE_ALL))
		end
		SetFlag(Controls["selected_dest_source"], "IsDisabled", Mode == MODE_ALL)
		-- Never leave a selection parked on a hidden entry.
		if not DestVisible(SelectedDest) then SelectedDest = FirstVisibleDest() end
		if not SourceVisible(SelectedSource) then SelectedSource = FirstVisibleSource() end
		-- Visibility also gates the lit state, so always re-assert the surface.
		RefreshAll()
	end

	local function ApplyMode()
		BeginSuppress()
		SetBool(Controls["mode_matrix"], Mode == MODE_MATRIX)
		SetBool(Controls["mode_all"], Mode == MODE_ALL)
		SetString(Controls["mode_name"], (Mode == MODE_MATRIX) and "Matrix" or "All")
		EndSuppress()
		ApplyVisibility()
		RefreshAll()
		dbg("mode", Mode, "order", SelectOrder)
	end

	-- ===== Router binding =====
	local function UnbindRouter()
		for _, thisCtlName in pairs(BoundSelectCtls) do
			if HasControl(RouterProxy, thisCtlName) then
				pcall(function() RouterProxy[thisCtlName].EventHandler = nil end)
			end
		end
		BoundSelectCtls = {}
	end

	-- Track routes changed anywhere else in the design, not just by this plugin.
	local function BindRouter()
		UnbindRouter()
		if RouterProxy == nil then return end
		for thisDest = 1, DestCount do
			local selCtl = ResolveSelectCtl(thisDest)
			if selCtl ~= nil then
				pcall(function()
					RouterProxy[selCtl].EventHandler = function() RefreshAll() end
				end)
				BoundSelectCtls[thisDest] = selCtl
			end
		end
	end

	local function ReportBinding()
		if RouterProxy == nil then
			SetString(Controls["router_style"], "")
			SetStatus(STATUS.MISSING, "No router selected")
			return
		end
		local resolved = 0
		for thisDest = 1, DestCount do
			if ResolveSelectCtl(thisDest) ~= nil then resolved = resolved + 1 end
		end
		local firstCtl = ResolveSelectCtl(1)
		if firstCtl == nil then
			SetString(Controls["router_style"], "unresolved")
			SetStatus(STATUS.FAULT, "No output select control found on router")
		elseif string.find(firstCtl, "output.", 1, true) then
			SetString(Controls["router_style"], "output.N.select")
		else
			SetString(Controls["router_style"], "select.N")
		end
		if firstCtl ~= nil then
			if resolved < DestCount then
				SetStatus(STATUS.COMPROMISED,
					fmt("Router has %d of %d configured outputs", resolved, DestCount))
			else
				SetStatus(STATUS.OK, fmt("%d outputs bound", resolved))
			end
		end
		dbg("router outputs resolved", resolved, "of", DestCount, "style", firstCtl or "none")
	end

	local function RebuildRouterProxy()
		UnbindRouter()
		RouterProxy    = nil
		SelectCtlCache = {}
		local sel = Controls["router_select"]
		local name = (sel ~= nil and sel.String) or ""
		if name ~= "" then
			local ok, comp = pcall(Component.New, name)
			if ok and comp ~= nil then RouterProxy = comp end
		end
		SetBool(Controls["router_found"], RouterProxy ~= nil)
		ReportBinding()
		BindRouter()
		RefreshAll()
	end

	-- Accept a component as a router if its Type says so, or if either select
	-- naming form is present on it.
	local function LooksLikeRouter(comp)
		local ok, ctrls = pcall(Component.GetControls, comp)
		if not ok or ctrls == nil then return false end
		for _, thisCtl in ipairs(ctrls) do
			if thisCtl.Name == "select.1" or thisCtl.Name == "output.1.select" then
				return true
			end
		end
		return false
	end

	local function DiscoverRouters()
		local list = {}
		local ok, comps = pcall(Component.GetComponents)
		if not ok or comps == nil then return list end
		for _, thisComp in ipairs(comps) do
			local isRouter = false
			if type(thisComp.Type) == "string"
				and string.find(string.lower(thisComp.Type), "router", 1, true) then
				isRouter = true
			end
			if not isRouter then
				local okNew, proxy = pcall(Component.New, thisComp.Name)
				if okNew and proxy ~= nil then isRouter = LooksLikeRouter(proxy) end
			end
			if isRouter then table.insert(list, thisComp.Name) end
		end
		table.sort(list)
		return list
	end

	local function RefreshRouterList()
		local sel = Controls["router_select"]
		if sel == nil then return end
		local list = DiscoverRouters()
		local current = sel.String
		if current ~= nil and current ~= "" then
			local present = false
			for _, thisName in ipairs(list) do
				if thisName == current then present = true end
			end
			if not present then table.insert(list, current) end
		end
		table.insert(list, 1, "")   -- blank option = not bound
		sel.Choices = list
		RebuildRouterProxy()
	end

	-- ===== Event handlers =====
	if Controls["router_select"] ~= nil then
		Controls["router_select"].EventHandler = function()
			RebuildRouterProxy()
		end
	end

	-- Mode buttons re-assert the authoritative mode state rather than forcing
	-- the pressed button, so the pair cannot latch both on.
	--
	-- Only a button going HIGH is a request. A low event is either this plugin's
	-- own exclusivity write arriving after the suppression guard dropped, or the
	-- operator pressing the already-active button. Adopting a low event as a
	-- request makes the pair fight each other and thrash.
	if Controls["mode_matrix"] ~= nil then
		Controls["mode_matrix"].EventHandler = function(ctl)
			if Suppressed() then return end
			if not ctl.Boolean then
				ApplyMode()
				return
			end
			Mode = MODE_MATRIX
			ApplyMode()
		end
	end
	if Controls["mode_all"] ~= nil then
		Controls["mode_all"].EventHandler = function(ctl)
			if Suppressed() then return end
			if not ctl.Boolean then
				ApplyMode()
				return
			end
			Mode = MODE_ALL
			ApplyMode()
		end
	end

	-- Destination-first selection combo. Picking a source routes the selected
	-- destination to it -- the same action as pressing that source's button.
	if Controls["selected_dest_source"] ~= nil then
		Controls["selected_dest_source"].EventHandler = function(ctl)
			if Suppressed() then return end
			local wanted = ChoiceIndex[ctl.String or ""]
			-- Same refusals as the per-destination combos: anything else is a
			-- stale readout, not a request, and snaps back to the real route.
			if wanted == nil
				or Mode ~= MODE_MATRIX
				or not DestVisible(SelectedDest)
				or not SourceVisible(wanted) then
				WriteRouteReadouts()
				return
			end
			SetRoute(SelectedDest, wanted)
			RefreshAll()
		end
	end

	for thisDest = 1, DestCount do
		local selectCtl = DestCtl("select", thisDest)
		if selectCtl ~= nil then
			selectCtl.EventHandler = function(ctl)
				if Suppressed() then return end
				-- A low event is a feedback write clearing this button, not a
				-- press. Re-assert authoritative state only.
				if not ctl.Boolean then
					WriteDestButtons()
					return
				end
				if Mode == MODE_MATRIX and DestVisible(thisDest) then
					if SelectOrder == ORDER_SOURCE then
						-- Source-first: the destination press is the route action.
						if SelectedSource ~= nil then SetRoute(thisDest, SelectedSource) end
					else
						SelectedDest = thisDest
					end
				end
				RefreshAll()
			end
		end

		-- Routed-source ComboBox. Picking a source routes this destination to it.
		local sourceCtl = DestCtl("source", thisDest)
		if sourceCtl ~= nil then
			sourceCtl.EventHandler = function(ctl)
				if Suppressed() then return end
				local wanted = ChoiceIndex[ctl.String or ""]
				-- Anything else is a stale readout rather than a request: an
				-- unrecognised string, a hidden entry, or One-To-All mode, where a
				-- single output cannot be routed on its own.
				if wanted == nil
					or Mode ~= MODE_MATRIX
					or not DestVisible(thisDest)
					or not SourceVisible(wanted) then
					WriteRouteReadouts()
					return
				end
				SetRoute(thisDest, wanted)
				RefreshAll()
			end
		end

		local visibleCtl = DestCtl("visible", thisDest)
		if visibleCtl ~= nil then
			visibleCtl.EventHandler = function()
				ApplyVisibility()
			end
		end

		local nameCtl = DestCtl("name", thisDest)
		if nameCtl ~= nil then
			nameCtl.EventHandler = function()
				if Suppressed() then return end
				WriteDestButtons()
				WriteRouteReadouts()
			end
		end
	end

	for thisSource = 1, SourceCount do
		local selectCtl = SourceCtl("select", thisSource)
		if selectCtl ~= nil then
			selectCtl.EventHandler = function(ctl)
				if Suppressed() then return end
				-- Only a press (going high) is a request. Clearing a previously
				-- lit source must never re-route to it.
				if not ctl.Boolean then
					WriteSourceButtons()
					return
				end
				if not SourceVisible(thisSource) then
					WriteSourceButtons()
					return
				end
				if Mode == MODE_MATRIX and SelectOrder == ORDER_SOURCE then
					-- Source-first: the press only arms the source; routing waits
					-- for a destination press.
					SelectedSource = thisSource
				elseif Mode == MODE_ALL then
					for eachDest = 1, DestCount do
						SetRoute(eachDest, thisSource)
					end
					dbgRoute("routed all destinations <- source", thisSource)
				elseif RouterProxy ~= nil then
					-- Destination-first: the press routes to the armed destination.
					SetRoute(SelectedDest, thisSource)
				else
					dbg("route ignored, no router bound")
				end
				-- Lit state comes from the router (or the arming selection),
				-- never from the press itself.
				RefreshAll()
			end
		end

		local visibleCtl = SourceCtl("visible", thisSource)
		if visibleCtl ~= nil then
			visibleCtl.EventHandler = function()
				ApplyVisibility()
			end
		end

		local nameCtl = SourceCtl("name", thisSource)
		if nameCtl ~= nil then
			nameCtl.EventHandler = function()
				if Suppressed() then return end
				-- A source name is also a choice on every routed-source combo.
				RefreshSourceChoices()
				WriteDestButtons()
				WriteRouteReadouts()
			end
		end
	end

	-- ===== Initialise =====
	SelectedDest   = FirstVisibleDest()
	SelectedSource = FirstVisibleSource()
	RefreshSourceChoices()
	ApplyMode()
	RefreshRouterList()

	-- Safety net: a router variant that does not raise change events on its
	-- select controls still gets picked up here. All writes are conditional, so
	-- a settled system produces no control events from this poll.
	local pollTimer = Timer.New()
	pollTimer.EventHandler = function()
		RefreshAll()
	end
	pollTimer:Start(2)

	dbg("initialised", SourceCount, "sources x", DestCount, "destinations, mode", Mode,
		"order", SelectOrder)
