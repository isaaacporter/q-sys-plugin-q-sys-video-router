"""
Out-of-Designer test harness for QsysVideoRouter.qplug.

Runs the compiled plugin under lupa (Lua 5.5) against mocked Q-SYS globals
(Controls / Properties / Component / Timer), then mutation-tests itself so a
green run means something. See qsys_preferences.md.
"""
import sys
import re
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path
from lupa import LuaRuntime

QPLUG = Path(__file__).resolve().parent.parent / "src" / "QsysVideoRouter" / "QsysVideoRouter.qplug"

HARNESS_LUA = r"""
-- ===== mock plumbing =====
EVENTS = 0
PER_CONTROL = {}
STORM = false
QUEUE = {}
DEPTH = 0
INTERNAL_HOOK = setmetatable({}, {__mode = "k"})
CTRL_LIST = setmetatable({}, {__mode = "k"})

local function dispatch(handler, ctl)
	if handler == nil then return end
	if DISPATCH_MODE == "deferred" then
		QUEUE[#QUEUE + 1] = {handler, ctl}
		return
	end
	DEPTH = DEPTH + 1
	if DEPTH > 150 then
		STORM = true
		DEPTH = DEPTH - 1
		return
	end
	handler(ctl)
	DEPTH = DEPTH - 1
end

function Drain()
	local guard = 0
	while #QUEUE > 0 do
		guard = guard + 1
		if guard > 5000 then STORM = true break end
		local job = table.remove(QUEUE, 1)
		job[1](job[2])
	end
end

function MakeControl(name)
	local data = {
		Boolean = false, Value = 0, String = "",
		IsInvisible = false, IsDisabled = false,
		Choices = {}, Legend = "", EventHandler = nil
	}
	local ctl = {}
	setmetatable(ctl, {
		__index = function(_, k) return data[k] end,
		__newindex = function(t, k, v)
			local old = data[k]
			data[k] = v
			-- Q-SYS keeps Boolean and Value coherent on a button.
			if k == "Boolean" then data.Value = v and 1 or 0 end
			if k == "Value" then data.Boolean = (v ~= 0 and v ~= false) end
			-- Q-SYS fires the handler on any value change, including String
			-- (a ComboBox selection or a script write). Only the display-state
			-- flags are inert.
			if k == "Boolean" or k == "Value" or k == "String" then
				local changed = (old ~= v)
				if changed or FIRE_ALWAYS then
					EVENTS = EVENTS + 1
					PER_CONTROL[name] = (PER_CONTROL[name] or 0) + 1
					local hook = INTERNAL_HOOK[t]
					if hook then hook(t) end
					dispatch(data.EventHandler, t)
				end
			end
		end
	})
	return ctl
end

-- ===== mock router component =====
function MakeRouter(outputs, style)
	local proxy = {}
	local list = {}
	local selNames = {}
	for thisDest = 1, outputs do
		local selName
		if style == "mediacast" then
			selName = "output." .. thisDest .. ".select"
		else
			selName = "select." .. thisDest
		end
		local nameName = "output." .. thisDest .. ".source.name"
		local selCtl = MakeControl(selName)
		local nameCtl = MakeControl(nameName)
		rawset(proxy, selName, selCtl)
		rawset(proxy, nameName, nameCtl)
		list[#list + 1] = {Name = selName}
		list[#list + 1] = {Name = nameName}
		selNames[thisDest] = selName
		-- Emulate the router updating its own source-name readout on a route
		-- change. Kept separate from EventHandler, which the plugin owns.
		INTERNAL_HOOK[selCtl] = function(c)
			local routed = math.floor(c.Value or 0)
			if routed >= 1 then
				nameCtl.String = "Src" .. routed
			else
				nameCtl.String = ""
			end
		end
	end
	CTRL_LIST[proxy] = list
	ROUTER_SEL_NAMES = selNames
	return proxy
end

ROUTER = MakeRouter(ROUTER_OUTPUTS, ROUTER_STYLE)
local decoy = {}
CTRL_LIST[decoy] = {{Name = "gain"}, {Name = "mute"}}

COMPONENTS = {["VideoRouter"] = ROUTER, ["SomeGain"] = decoy}
COMPONENT_LIST = {
	{Name = "VideoRouter", Type = "mediacast_router"},
	{Name = "SomeGain", Type = "gain"}
}

Component = {
	New = function(name) return COMPONENTS[name] end,
	GetComponents = function() return COMPONENT_LIST end,
	GetControls = function(proxy) return CTRL_LIST[proxy] end
}

-- ===== mock Timer =====
TIMERS = {}
Timer = {
	New = function()
		local t = {running = false, period = 0, EventHandler = nil}
		t.Start = function(self, p) self.period = p self.running = true end
		t.Stop = function(self) self.running = false end
		TIMERS[#TIMERS + 1] = t
		return t
	end
}
function FireTimers()
	for _, t in ipairs(TIMERS) do
		if t.running and t.EventHandler then t.EventHandler() end
	end
	if DISPATCH_MODE == "deferred" then Drain() end
end

-- ===== properties =====
local function MakeProps()
	return {
		["Source Count"]      = {Value = SRC_COUNT},
		["Destination Count"] = {Value = DST_COUNT},
		["Default Mode"]      = {Value = DEFAULT_MODE},
		["Matrix Select Order"] = {Value = SELECT_ORDER},
		["Debug Print"]       = {Value = "None"},
		["page_index"]        = {Value = 1}
	}
end

-- ===== pass 1: design time (Controls absent) =====
Controls = nil
Properties = MakeProps()
local chunk = assert(load(PLUGIN_SRC, "plugin"))
chunk()

DESIGN_CONTROLS = GetControls(MakeProps())
DESIGN_PAGES = GetPages(MakeProps())

-- Validate every page's layout: numeric geometry, and every laid-out key is a
-- real control.
function ValidateLayout(srcN, dstN)
	local problems = {}
	local names = {}
	local props = MakeProps()
	props["Source Count"] = {Value = srcN}
	props["Destination Count"] = {Value = dstN}
	local ctrls = GetControls(props)
	for _, c in ipairs(ctrls) do names[c.Name] = true end
	local pages = GetPages(props)
	local seen = {}
	for pageIx = 1, #pages do
		props["page_index"] = {Value = pageIx}
		local layout, graphics = GetControlLayout(props)
		for key, entry in pairs(layout) do
			seen[key] = true
			if not names[key] then
				problems[#problems + 1] = "layout key not a control: " .. key
			end
			for _, field in ipairs({"Position", "Size"}) do
				local v = entry[field]
				if v ~= nil then
					if type(v[1]) ~= "number" or type(v[2]) ~= "number" then
						problems[#problems + 1] = key .. " has non-numeric " .. field
					end
				end
			end
		end
		for gIx, g in ipairs(graphics) do
			for _, field in ipairs({"Position", "Size"}) do
				local v = g[field]
				if v ~= nil and (type(v[1]) ~= "number" or type(v[2]) ~= "number") then
					problems[#problems + 1] = "graphic " .. gIx .. " bad " .. field
				end
			end
		end
	end
	return problems, names, seen
end

-- ===== pass 2: runtime =====
local mockControls = {}
for _, c in ipairs(DESIGN_CONTROLS) do
	mockControls[c.Name] = MakeControl(c.Name)
	if c.DefaultValue == true then
		rawget(getmetatable(mockControls[c.Name]), "__newindex")(mockControls[c.Name], "Boolean", true)
	end
end
Controls = mockControls
Properties = MakeProps()
EVENTS = 0
PER_CONTROL = {}

local chunk2 = assert(load(PLUGIN_SRC, "plugin_rt"))
chunk2()
if DISPATCH_MODE == "deferred" then Drain() end

-- ===== test helpers =====
local fmt = string.format
FAILS = {}
function check(name, cond, msg)
	if not cond then FAILS[#FAILS + 1] = name .. (msg and (" -- " .. msg) or "") end
end

function C(n) return Controls[n] end
function Press(n)
	local ctl = Controls[n]
	ctl.Boolean = not ctl.Boolean
	if DISPATCH_MODE == "deferred" then Drain() end
end
function SetCtl(n, field, v)
	Controls[n][field] = v
	if DISPATCH_MODE == "deferred" then Drain() end
end
function RouterSel(thisDest) return ROUTER[ROUTER_SEL_NAMES[thisDest]] end
function SetRouterExternal(thisDest, src)
	RouterSel(thisDest).Value = src
	if DISPATCH_MODE == "deferred" then Drain() end
end
function HighDestCount()
	local n = 0
	for d = 1, DST_COUNT do
		if C(fmt("dest_select_%03d", d)).Boolean then n = n + 1 end
	end
	return n
end
function HighSourceCount()
	local n = 0
	for s = 1, SRC_COUNT do
		if C(fmt("source_select_%03d", s)).Boolean then n = n + 1 end
	end
	return n
end
function LitSourceIx()
	for s = 1, SRC_COUNT do
		if C(fmt("source_select_%03d", s)).Boolean then return s end
	end
	return nil
end
function SelectDest(d) Press(fmt("dest_select_%03d", d)) end
function PressSource(s) Press(fmt("source_select_%03d", s)) end
function MaxPerControl()
	local worst, name = 0, nil
	for k, v in pairs(PER_CONTROL) do
		if v > worst then worst = v name = k end
	end
	return worst, name
end
"""

TESTS_LUA = r"""
local fmt = string.format

-- bind the router
SetCtl("router_select", "String", "VideoRouter")

check("T1 router bound", C("router_found").Boolean, "router_found low")
check("T2 status ok", C("status").Value == 0, "status=" .. tostring(C("status").Value))
local expectStyle = (ROUTER_STYLE == "mediacast") and "output.N.select" or "select.N"
check("T3 naming resolved", C("router_style").String == expectStyle,
	"got '" .. tostring(C("router_style").String) .. "' want '" .. expectStyle .. "'")

check("T5 mode exclusive at init",
	not (C("mode_matrix").Boolean and C("mode_all").Boolean), "both mode buttons high")
check("T6 mode is matrix", C("mode_matrix").Boolean, "matrix not lit")

if SELECT_ORDER == "Destination First" then

	check("T4 one dest high at init", HighDestCount() == 1, "count=" .. HighDestCount())

	SelectDest(3)
	check("T7 dest 3 selected only", HighDestCount() == 1 and C("dest_select_003").Boolean,
		"count=" .. HighDestCount())
	PressSource(5)
	check("T8 route applied to selected dest", math.floor(RouterSel(3).Value) == 5,
		"select.3=" .. tostring(RouterSel(3).Value))
	check("T9 other dests untouched", math.floor(RouterSel(1).Value) == 0,
		"select.1=" .. tostring(RouterSel(1).Value))
	check("T10 source 5 lit", LitSourceIx() == 5, "lit=" .. tostring(LitSourceIx()))
	check("T11 exactly one source lit", HighSourceCount() == 1, "count=" .. HighSourceCount())
	check("T12 route readout", math.floor(C("dest_route_003").Value) == 5,
		"dest_route_003=" .. tostring(C("dest_route_003").Value))
	check("T13 routed source readout", C("dest_source_003").String == "Source 5",
		"got '" .. tostring(C("dest_source_003").String) .. "'")

	-- switching destination highlights ITS current source
	SetRouterExternal(1, 2)
	SelectDest(1)
	check("T14 dest switch highlights its routed source", LitSourceIx() == 2,
		"lit=" .. tostring(LitSourceIx()))
	SelectDest(3)
	check("T15 switching back highlights dest 3 source", LitSourceIx() == 5,
		"lit=" .. tostring(LitSourceIx()))

	SetRouterExternal(3, 7)
	check("T16 external change tracked", LitSourceIx() == 7, "lit=" .. tostring(LitSourceIx()))

	SelectDest(4)
	check("T17 unrouted dest lights nothing", LitSourceIx() == nil,
		"lit=" .. tostring(LitSourceIx()))

	for _, d in ipairs({1, 2, 3, 4, 2, 1, 4, 3}) do
		SelectDest(d)
		check("T18 dest interlock holds (dest " .. d .. ")", HighDestCount() == 1,
			"count=" .. HighDestCount())
	end
	check("T18b selected dest readout populated", C("selected_dest_name").String ~= "",
		"empty")
	check("T18c source readout unused in dest-first",
		C("selected_source_name").String == "",
		"got '" .. tostring(C("selected_source_name").String) .. "'")

	-- ===== selection combo: routes a source to the selected destination =====
	-- Routes here: dest 1 <- 2, dest 3 <- 7, dest 4 unrouted.
	local sel = "selected_dest_source"
	local function SelOffered(label)
		for _, ch in ipairs(C(sel).Choices or {}) do
			if ch == label then return true end
		end
		return false
	end

	SelectDest(3)
	check("S1 selection combo choices populated", #(C(sel).Choices or {}) == SRC_COUNT,
		"#choices=" .. tostring(#(C(sel).Choices or {})))
	check("S2 reads the selected destination's route", C(sel).String == "Source 7",
		"got '" .. tostring(C(sel).String) .. "'")
	SelectDest(1)
	check("S3 follows a destination change", C(sel).String == "Source 2",
		"got '" .. tostring(C(sel).String) .. "'")
	SelectDest(4)
	check("S4 unrouted destination reads blank", C(sel).String == "",
		"got '" .. tostring(C(sel).String) .. "'")

	SetCtl(sel, "String", "Source 6")
	check("S5 pick routes the selected destination", math.floor(RouterSel(4).Value) == 6,
		"select.4=" .. tostring(RouterSel(4).Value))
	check("S6 other destinations untouched",
		math.floor(RouterSel(1).Value) == 2 and math.floor(RouterSel(3).Value) == 7,
		"select.1=" .. tostring(RouterSel(1).Value)
			.. " select.3=" .. tostring(RouterSel(3).Value))
	check("S7 source button follows the pick", LitSourceIx() == 6,
		"lit=" .. tostring(LitSourceIx()))
	check("S8 per-destination combo agrees", C("dest_source_004").String == "Source 6",
		"got '" .. tostring(C("dest_source_004").String) .. "'")
	check("S9 destination selection unchanged by a pick",
		C("dest_select_004").Boolean and HighDestCount() == 1, "count=" .. HighDestCount())

	SetCtl(sel, "String", "None")
	check("S10 non-source string cannot clear a route", math.floor(RouterSel(4).Value) == 6,
		"select.4=" .. tostring(RouterSel(4).Value))
	check("S11 refused string snaps back", C(sel).String == "Source 6",
		"got '" .. tostring(C(sel).String) .. "'")

	SetRouterExternal(4, 8)
	check("S12 follows an external route change", C(sel).String == "Source 8",
		"got '" .. tostring(C(sel).String) .. "'")

	SetCtl("source_visible_005", "Boolean", false)
	check("S13 hidden source not offered", not SelOffered("Source 5"),
		"'Source 5' still offered")
	SetCtl(sel, "String", "Source 5")
	check("S14 hidden source cannot be routed", math.floor(RouterSel(4).Value) == 8,
		"select.4=" .. tostring(RouterSel(4).Value))
	check("S15 rejected pick snaps back", C(sel).String == "Source 8",
		"got '" .. tostring(C(sel).String) .. "'")
	SetCtl("source_visible_005", "Boolean", true)

	SetCtl("source_name_008", "String", "Roku")
	check("S16 rename relabels the readout", C(sel).String == "Roku",
		"got '" .. tostring(C(sel).String) .. "'")
	check("S17 rename relabels the choice list", SelOffered("Roku"), "'Roku' not offered")
	SetCtl("source_name_008", "String", "")

else  -- Source First

	check("S0 no selection combo in source-first", C("selected_dest_source") == nil,
		"selected_dest_source exists")

	check("T4 one source high at init", HighSourceCount() == 1,
		"count=" .. HighSourceCount())
	check("T4b no dest lit at init (nothing routed)", HighDestCount() == 0,
		"count=" .. HighDestCount())

	-- arming a source must NOT route anything
	PressSource(5)
	check("T7 source 5 armed", LitSourceIx() == 5, "lit=" .. tostring(LitSourceIx()))
	check("T7b source interlock exclusive", HighSourceCount() == 1,
		"count=" .. HighSourceCount())
	check("T8 arming a source routes nothing",
		math.floor(RouterSel(1).Value) == 0 and math.floor(RouterSel(3).Value) == 0,
		"select.1=" .. tostring(RouterSel(1).Value)
			.. " select.3=" .. tostring(RouterSel(3).Value))

	-- destination press is the route action
	SelectDest(3)
	check("T9 dest press routes armed source", math.floor(RouterSel(3).Value) == 5,
		"select.3=" .. tostring(RouterSel(3).Value))
	check("T10 routed dest lit", C("dest_select_003").Boolean, "dest 3 not lit")
	check("T11 armed source stays lit", LitSourceIx() == 5, "lit=" .. tostring(LitSourceIx()))
	check("T12 route readout", math.floor(C("dest_route_003").Value) == 5,
		"dest_route_003=" .. tostring(C("dest_route_003").Value))
	check("T13 routed source readout", C("dest_source_003").String == "Source 5",
		"got '" .. tostring(C("dest_source_003").String) .. "'")

	-- a second destination for the same source: BOTH light
	SelectDest(2)
	check("T14 second dest routed", math.floor(RouterSel(2).Value) == 5,
		"select.2=" .. tostring(RouterSel(2).Value))
	check("T15 both dests carrying armed source are lit",
		C("dest_select_002").Boolean and C("dest_select_003").Boolean
			and HighDestCount() == 2,
		"count=" .. HighDestCount())

	-- arming a different source re-lights destinations by that source
	PressSource(2)
	check("T16 dest highlight follows armed source", HighDestCount() == 0,
		"count=" .. HighDestCount())
	SetRouterExternal(4, 2)
	check("T17 external route lights dest for armed source",
		C("dest_select_004").Boolean and HighDestCount() == 1,
		"count=" .. HighDestCount())

	-- source interlock invariant under a burst
	for _, s in ipairs({1, 6, 3, 8, 2, 5, 1, 7}) do
		PressSource(s)
		check("T18 source interlock holds (source " .. s .. ")", HighSourceCount() == 1,
			"count=" .. HighSourceCount())
	end
	check("T18b selected source readout populated", C("selected_source_name").String ~= "",
		"empty")
	check("T18c dest readout unused in source-first",
		C("selected_dest_name").String == "",
		"got '" .. tostring(C("selected_dest_name").String) .. "'")

end

-- ===== routed-source ComboBox (order-agnostic; still in matrix mode) =====
local combo = "dest_source_001"

local function Offered(label)
	local list = C(combo).Choices
	if list == nil then return false end
	for _, ch in ipairs(list) do
		if ch == label then return true end
	end
	return false
end

local choices = C(combo).Choices
check("C1 combo choices populated", choices ~= nil and #choices == SRC_COUNT,
	"#choices=" .. tostring(choices and #choices))
-- A router output has no "off" position, so there is nothing to offer but sources.
check("C2 None not offered", not Offered("None"), "'None' offered as a source")
check("C3 every visible source offered", Offered("Source 6"), "'Source 6' missing")

local otherBefore = math.floor(RouterSel(DST_COUNT).Value)
SetCtl(combo, "String", "Source 6")
check("C4 combo pick routes the destination", math.floor(RouterSel(1).Value) == 6,
	"dest 1 route=" .. tostring(RouterSel(1).Value))
check("C5 combo reads the route back", C(combo).String == "Source 6",
	"got '" .. tostring(C(combo).String) .. "'")
check("C6 other destinations untouched by a combo pick",
	math.floor(RouterSel(DST_COUNT).Value) == otherBefore,
	"dest " .. DST_COUNT .. " route=" .. tostring(RouterSel(DST_COUNT).Value))

-- forcing a non-source string must never unroute the output
SetCtl(combo, "String", "None")
check("C7 None cannot clear a route", math.floor(RouterSel(1).Value) == 6,
	"dest 1 route=" .. tostring(RouterSel(1).Value))
check("C8 refused None snaps back", C(combo).String == "Source 6",
	"got '" .. tostring(C(combo).String) .. "'")

SetRouterExternal(1, 3)
check("C9 combo follows an external route change", C(combo).String == "Source 3",
	"got '" .. tostring(C(combo).String) .. "'")

-- a source rename re-labels both the choice list and the readout
SetCtl("source_name_003", "String", "Roku")
check("C10 rename relabels the readout", C(combo).String == "Roku",
	"got '" .. tostring(C(combo).String) .. "'")
check("C11 rename relabels the choice list", Offered("Roku"), "'Roku' not offered")
SetCtl("source_name_003", "String", "")

-- a hidden source is neither offered nor routable through the combo
SetCtl("source_visible_004", "Boolean", false)
check("C12 hidden source not offered", not Offered("Source 4"),
	"'Source 4' still offered")
local beforeForce = math.floor(RouterSel(1).Value)
SetCtl(combo, "String", "Source 4")
check("C13 hidden source cannot be routed via the combo",
	math.floor(RouterSel(1).Value) == beforeForce,
	"dest 1 route=" .. tostring(RouterSel(1).Value))
check("C14 rejected pick snaps back to the real route", C(combo).String == "Source 3",
	"got '" .. tostring(C(combo).String) .. "'")
SetCtl("source_visible_004", "Boolean", true)

-- two sources sharing a name must stay distinguishable
SetCtl("source_name_001", "String", "Dup")
SetCtl("source_name_002", "String", "Dup")
check("C15 duplicate name disambiguated in the list", Offered("Dup (2)"),
	"'Dup (2)' not offered")
SetCtl(combo, "String", "Dup (2)")
check("C16 disambiguated pick routes the right source",
	math.floor(RouterSel(1).Value) == 2, "dest 1 route=" .. tostring(RouterSel(1).Value))
SetCtl("source_name_001", "String", "")
SetCtl("source_name_002", "String", "")

-- One-To-All
Press("mode_all")
check("T19 mode_all lit", C("mode_all").Boolean, "mode_all low")
check("T20 mode_matrix cleared", not C("mode_matrix").Boolean, "both modes lit")
check("T21 mode name", C("mode_name").String == "All",
	"got '" .. tostring(C("mode_name").String) .. "'")
check("T22 dest buttons cleared in one-to-all", HighDestCount() == 0,
	"count=" .. HighDestCount())
check("T23 dest buttons disabled in one-to-all", C("dest_select_001").IsDisabled,
	"not disabled")
check("T23b routed-source combo disabled in one-to-all",
	C("dest_source_001").IsDisabled, "not disabled")

PressSource(4)
local allFour = true
for d = 1, DST_COUNT do
	if math.floor(RouterSel(d).Value) ~= 4 then allFour = false end
end
check("T24 one-to-all routes every output", allFour, "not all outputs on source 4")
check("T25 common source lit", LitSourceIx() == 4, "lit=" .. tostring(LitSourceIx()))

-- a single-output route contradicts one-to-all, so the combo must refuse
SetCtl("dest_source_001", "String", "Source 2")
check("T25b combo refuses to route one output in one-to-all",
	math.floor(RouterSel(1).Value) == 4, "dest 1 route=" .. tostring(RouterSel(1).Value))
check("T25c refused combo pick snaps back", C("dest_source_001").String == "Source 4",
	"got '" .. tostring(C("dest_source_001").String) .. "'")

if SELECT_ORDER == "Destination First" then
	local sel = "selected_dest_source"
	check("S20 selection combo disabled in one-to-all", C(sel).IsDisabled, "not disabled")
	check("S21 selection combo shows the common source", C(sel).String == "Source 4",
		"got '" .. tostring(C(sel).String) .. "'")
	SetCtl(sel, "String", "Source 2")
	local stillFour = true
	for d = 1, DST_COUNT do
		if math.floor(RouterSel(d).Value) ~= 4 then stillFour = false end
	end
	check("S22 selection combo refuses to route in one-to-all", stillFour,
		"an output left source 4")
	check("S23 refused pick snaps back", C(sel).String == "Source 4",
		"got '" .. tostring(C(sel).String) .. "'")
end

-- break the common route: nothing should be lit
SetRouterExternal(2, 6)
check("T26 no lit source when routes differ", LitSourceIx() == nil,
	"lit=" .. tostring(LitSourceIx()))
if SELECT_ORDER == "Destination First" then
	check("S24 no common source reads blank", C("selected_dest_source").String == "",
		"got '" .. tostring(C("selected_dest_source").String) .. "'")
end

-- back to matrix
Press("mode_matrix")
check("T27 matrix restored", C("mode_matrix").Boolean and not C("mode_all").Boolean,
	"mode flags wrong")
if SELECT_ORDER == "Destination First" then
	check("T28 one dest high again", HighDestCount() == 1, "count=" .. HighDestCount())
else
	check("T28 one source high again", HighSourceCount() == 1,
		"count=" .. HighSourceCount())
end
check("T29 dest buttons re-enabled", not C("dest_select_001").IsDisabled, "still disabled")
check("T29b routed-source combo re-enabled", not C("dest_source_001").IsDisabled,
	"still disabled")
if SELECT_ORDER == "Destination First" then
	check("S25 selection combo re-enabled", not C("selected_dest_source").IsDisabled,
		"still disabled")
end

-- visibility: sources
SetCtl("source_visible_003", "Boolean", false)
check("T30 hidden source invisible", C("source_select_003").IsInvisible, "not invisible")
check("T31 hidden source disabled", C("source_select_003").IsDisabled, "not disabled")
SelectDest(1)
local beforeHide = math.floor(RouterSel(1).Value)
PressSource(3)
check("T32 hidden source cannot route", math.floor(RouterSel(1).Value) == beforeHide,
	"route changed to " .. tostring(RouterSel(1).Value))
SetCtl("source_visible_003", "Boolean", true)
check("T33 source visible again", not C("source_select_003").IsInvisible, "still invisible")

-- a hidden source must not remain LIT, not merely become invisible
if SELECT_ORDER == "Destination First" then
	SelectDest(1)
	PressSource(6)
	check("T33b routed source lit before hiding", LitSourceIx() == 6,
		"lit=" .. tostring(LitSourceIx()))
	SetCtl("source_visible_006", "Boolean", false)
	check("T33c hidden source goes dark", not C("source_select_006").Boolean,
		"source 6 still lit while hidden")
	SetCtl("source_visible_006", "Boolean", true)
	check("T33d source relights when shown again", LitSourceIx() == 6,
		"lit=" .. tostring(LitSourceIx()))
else
	PressSource(6)
	check("T33b armed source lit before hiding", LitSourceIx() == 6,
		"lit=" .. tostring(LitSourceIx()))
	SetCtl("source_visible_006", "Boolean", false)
	check("T33c hidden armed source goes dark", not C("source_select_006").Boolean,
		"source 6 still lit while hidden")
	check("T33d arming moved to a visible source", HighSourceCount() == 1,
		"count=" .. HighSourceCount())
	SetCtl("source_visible_006", "Boolean", true)
end

-- visibility: destinations
SelectDest(2)
check("T34 dest 2 selected", C("dest_select_002").Boolean, "not selected")
SetCtl("dest_visible_002", "Boolean", false)
check("T35 hidden dest invisible", C("dest_select_002").IsInvisible, "not invisible")
check("T36 hidden dest not left lit", not C("dest_select_002").Boolean,
	"still lit while hidden")
if SELECT_ORDER == "Destination First" then
	check("T37 selection moved to a visible dest", HighDestCount() == 1,
		"count=" .. HighDestCount())
end
SetCtl("dest_visible_002", "Boolean", true)

-- names feed the labels
SetCtl("dest_name_001", "String", "Lobby TV")
SetCtl("source_name_005", "String", "Apple TV")
if SELECT_ORDER == "Destination First" then
	SelectDest(1)
	check("T38 selected dest name echoed", C("selected_dest_name").String == "Lobby TV",
		"got '" .. tostring(C("selected_dest_name").String) .. "'")
else
	PressSource(5)
	check("T38 selected source name echoed",
		C("selected_source_name").String == "Apple TV",
		"got '" .. tostring(C("selected_source_name").String) .. "'")
end

-- poll timer must not disturb a settled system
FireTimers()
if SELECT_ORDER == "Destination First" then
	check("T39 poll timer keeps dest interlock", HighDestCount() == 1,
		"count=" .. HighDestCount())
else
	check("T39 poll timer keeps source interlock", HighSourceCount() == 1,
		"count=" .. HighSourceCount())
end

-- settle / storm check
local before = EVENTS
FireTimers()
FireTimers()
local churn = EVENTS - before
check("T40 settled system is quiet", churn == 0, "poll produced " .. churn .. " control events")
check("T41 no event storm", not STORM, "dispatch storm detected")
local worst, worstName = MaxPerControl()
check("T42 no control thrashing", worst < 400,
	"control '" .. tostring(worstName) .. "' saw " .. worst .. " events")
"""

LAYOUT_LUA = r"""
-- Deliberately pin-only: the mode pair is set by Default Mode or driven by room
-- logic, and has no home on either page.
local PIN_ONLY = {mode_matrix = true, mode_all = true, mode_name = true}
-- Destination first draws the selection combo in its place; it is never
-- populated in that order.
if SELECT_ORDER == "Destination First" then PIN_ONLY.selected_source_name = true end

local out = {}
for _, dims in ipairs({{1, 1}, {8, 4}, {64, 64}, {17, 33}}) do
	local problems, names, seen = ValidateLayout(dims[1], dims[2])
	for _, p in ipairs(problems) do
		out[#out + 1] = fmt and "" or ""
		out[#out + 1] = string.format("[%dx%d] %s", dims[1], dims[2], p)
	end
	-- every laid-out control resolves, and the interactive ones are all drawn
	for name in pairs(names) do
		if not seen[name] and not PIN_ONLY[name] then
			out[#out + 1] = string.format("[%dx%d] control never laid out: %s",
				dims[1], dims[2], name)
		end
	end
end
return table.concat(out, "\n")
"""


def run_case(src, dispatch, fire_always, style, order="Destination First",
             src_count=8, dst_count=4, default_mode="One-To-One (Matrix)",
             router_outputs=None):
    lua = LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.PLUGIN_SRC = src
    g.DISPATCH_MODE = dispatch
    g.FIRE_ALWAYS = fire_always
    g.SRC_COUNT = src_count
    g.DST_COUNT = dst_count
    g.DEFAULT_MODE = default_mode
    g.SELECT_ORDER = order
    g.ROUTER_STYLE = style
    g.ROUTER_OUTPUTS = router_outputs or dst_count
    lua.execute(HARNESS_LUA)
    lua.execute(TESTS_LUA)
    fails = list(g.FAILS.values()) if g.FAILS else []
    return fails


def run_layout(src, order="Destination First"):
    lua = LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.PLUGIN_SRC = src
    g.DISPATCH_MODE = "sync"
    g.FIRE_ALWAYS = False
    g.SRC_COUNT = 8
    g.DST_COUNT = 4
    g.DEFAULT_MODE = "One-To-One (Matrix)"
    g.SELECT_ORDER = order
    g.ROUTER_STYLE = "classic"
    g.ROUTER_OUTPUTS = 4
    lua.execute(HARNESS_LUA)
    return lua.execute(LAYOUT_LUA)


MATRIX = [
    ("sync",     False),
    ("sync",     True),
    ("deferred", False),
    ("deferred", True),
]


ORDERS = ("Destination First", "Source First")


def full_run(src, stop_early=False):
    """Returns dict of case -> failures. stop_early quits at the first failing case."""
    results = {}
    for order in ORDERS:
        for style in ("classic", "mediacast"):
            for dispatch, fire_always in MATRIX:
                tag = "dest-first" if order == "Destination First" else "src-first"
                fire = "fire-always" if fire_always else "on-change"
                key = f"{tag}/{style}/{dispatch}/{fire}"
                try:
                    results[key] = run_case(src, dispatch, fire_always, style, order)
                except Exception as exc:  # lua error counts as a failure
                    results[key] = [f"EXCEPTION: {exc}"]
                if stop_early and results[key]:
                    return results
    return results


def main():
    src = QPLUG.read_text(encoding="utf-8")

    print("=" * 78)
    print("BASELINE")
    print("=" * 78)
    results = full_run(src)
    total = 0
    for key, fails in results.items():
        total += len(fails)
        status = "PASS" if not fails else f"FAIL ({len(fails)})"
        print(f"  {key:46s} {status}")
        for f in fails:
            print(f"        - {f}")

    print("\n  design-time layout validation:")
    for order in ORDERS:
        layout_problems = run_layout(src, order)
        if layout_problems.strip():
            for line in layout_problems.strip().splitlines():
                print(f"        - [{order}] {line}")
            total += len(layout_problems.strip().splitlines())
        else:
            print(f"        {order:20s} clean at 1x1, 8x4, 64x64, 17x33")

    print(f"\n  baseline failures: {total}")

    # ===== mutation tests =====
    print()
    print("=" * 78)
    print("MUTATIONS (each must break the suite)")
    print("=" * 78)

    def sub(pattern, repl, count=1):
        """Whitespace-tolerant single substitution."""
        rx = re.compile(pattern, re.DOTALL)
        return lambda s: rx.sub(repl.replace("\\", "\\\\"), s, count=count)

    mutations = [
        (
            "drop MediaCast output.N.select candidate",
            sub(r'\{fmt\("select\.%d", thisDest\), fmt\("output\.%d\.select", thisDest\)\}',
                '{fmt("select.%d", thisDest)}'),
        ),
        (
            "make feedback writes unconditional (SetBool)",
            sub(r'if ctl ~= nil and ctl\.Boolean ~= want then ctl\.Boolean = want end',
                'if ctl ~= nil then ctl.Boolean = want end'),
        ),
        (
            "break destination interlock (light all)",
            sub(r'lit = \(thisDest == SelectedDest\)', 'lit = true'),
        ),
        (
            "one-to-all routes only selected dest",
            sub(r'for eachDest = 1, DestCount do\s+SetRoute\(eachDest, thisSource\)\s+end',
                'SetRoute(SelectedDest, thisSource)'),
        ),
        (
            "CommonRoute ignores route mismatch",
            sub(r'elseif common ~= routed then\s+return nil\s+end', 'end'),
        ),
        (
            "source handler drops go-high gating",
            sub(r'if not ctl\.Boolean then\s+WriteSourceButtons\(\)\s+return\s+end', ''),
        ),
        (
            "dest handler drops go-high gating",
            sub(r'if not ctl\.Boolean then\s+WriteDestButtons\(\)\s+return\s+end', ''),
        ),
        (
            "mode handler drops go-high gating",
            sub(r'if not ctl\.Boolean then\s+ApplyMode\(\)\s+return\s+end', '', count=2),
        ),
        (
            "ignore visibility when routing",
            sub(r'if not SourceVisible\(thisSource\) then\s+WriteSourceButtons\(\)\s+return\s+end',
                ''),
        ),
        (
            "never move selection off a hidden destination",
            sub(r'if not DestVisible\(SelectedDest\) then', 'if false then'),
        ),
        # --- source-first order ---
        (
            "source-first arms AND routes immediately",
            sub(r'-- Source-first: the press only arms the source.*?'
                r'SelectedSource = thisSource',
                'SelectedSource = thisSource\n\t\t\t\t\tSetRoute(SelectedDest, thisSource)'),
        ),
        (
            "source-first dest press does not route",
            sub(r'if SelectedSource ~= nil then SetRoute\(thisDest, SelectedSource\) end', ''),
        ),
        (
            "source-first dest highlight ignores armed source",
            sub(r'lit = \(SelectedSource ~= nil\) and \(GetRoute\(thisDest\) == SelectedSource\)',
                'lit = (thisDest == SelectedDest)'),
        ),
        (
            "hidden destination may stay lit",
            sub(r'SetBool\(DestCtl\("select", thisDest\), lit and DestVisible\(thisDest\)\)',
                'SetBool(DestCtl("select", thisDest), lit)'),
        ),
        (
            "hidden source may stay lit",
            sub(r'\(thisSource == lit\) and SourceVisible\(thisSource\)',
                '(thisSource == lit)'),
        ),
        # --- routed-source combo boxes ---
        (
            "combo pick does not route",
            sub(r'SetRoute\(thisDest, wanted\)', ''),
        ),
        (
            "combo routes a single output in one-to-all",
            sub(r'or Mode ~= MODE_MATRIX\s*or not DestVisible\(thisDest\)',
                'or not DestVisible(thisDest)'),
        ),
        (
            "combo offers hidden sources",
            sub(r'if SourceVisible\(thisSource\) then table\.insert\(ChoiceList, label\) end',
                'table.insert(ChoiceList, label)'),
        ),
        (
            "combo choices not rebuilt on a rename",
            sub(r'-- A source name is also a choice on every routed-source combo\.\s*'
                r'RefreshSourceChoices\(\)', ''),
        ),
        (
            "routed-source readout ignores the choice labels",
            sub(r'return ChoiceLabel\[routed\] or fmt\("Source %d", routed\)',
                'return fmt("Source %d", routed)'),
        ),
        (
            "combo re-offers an unroute (source 0) choice",
            sub(r'ChoiceIndex = \{\}\s*ChoiceList  = \{\}',
                'ChoiceIndex = {["None"] = 0}\n\t\tChoiceList  = {"None"}'),
        ),
        (
            "duplicate source names not disambiguated",
            sub(r'if taken\[label\] then label = fmt\("%s \(%d\)", label, thisSource\) end',
                ''),
        ),
        # --- destination-first selection combo ---
        (
            "selection combo pick does not route",
            sub(r'SetRoute\(SelectedDest, wanted\)', ''),
        ),
        (
            "selection combo routes destination 1, not the selected one",
            sub(r'SetRoute\(SelectedDest, wanted\)', 'SetRoute(1, wanted)'),
        ),
        (
            "selection combo reads destination 1, not the selected one",
            sub(r'routed = GetRoute\(SelectedDest\)', 'routed = GetRoute(1)'),
        ),
        (
            "selection combo falls back to the selected route in one-to-all",
            sub(r'routed = CommonRoute\(\)\s*else', 'routed = CommonRoute() or GetRoute(SelectedDest)\n\t\t\telse'),
        ),
        (
            "selection combo routes in one-to-all",
            sub(r'or Mode ~= MODE_MATRIX\s*or not DestVisible\(SelectedDest\)',
                'or not DestVisible(SelectedDest)'),
        ),
        (
            "selection combo offers no choices",
            sub(r'if selectedCtl ~= nil then selectedCtl\.Choices = ChoiceList end', ''),
        ),
        (
            "selection combo ignores source visibility",
            sub(r'or not DestVisible\(SelectedDest\)\s*or not SourceVisible\(wanted\)',
                'or not DestVisible(SelectedDest)'),
        ),
        (
            "selection combo not locked out in one-to-all",
            sub(r'SetFlag\(Controls\["selected_dest_source"\], "IsDisabled", Mode == MODE_ALL\)',
                ''),
        ),
    ]

    def sample_of(r):
        return next((f for v in r.values() for f in v), "")

    # Mutations are independent, so they run across cores. Workers get the
    # already-mutated source because the patch lambdas cannot be pickled.
    # Results are read back in list order, so output order is unchanged.
    mut_ok = 0
    with ProcessPoolExecutor() as pool:
        pending = []
        for name, patch in mutations:
            mutated = patch(src)
            fut = None if mutated == src else pool.submit(run_mutation, mutated)
            pending.append((name, fut))

        for name, fut in pending:
            if fut is None:
                print(f"  {name:52s} NOT APPLIED (pattern miss)", flush=True)
                continue
            res = fut.result()
            nfails = sum(len(v) for v in res.values())
            if nfails > 0:
                case = next((k for k, v in res.items() if v), "?")
                parts = case.split("/")
                where = f"{parts[0]}/{parts[2]}" if len(parts) > 2 else case
                print(f"  {name:50s} caught in {where:22s} e.g. {sample_of(res)[:40]}",
                      flush=True)
                mut_ok += 1
            else:
                print(f"  {name:52s} *** SURVIVED -- harness blind spot ***", flush=True)

    print(f"\n  mutations caught: {mut_ok}/{len(mutations)}")
    return 0 if total == 0 and mut_ok == len(mutations) else 1


def run_mutation(mutated):
    """Worker entry point: the full suite against one mutated source."""
    return full_run(mutated, stop_early=True)


if __name__ == "__main__":
    sys.exit(main())
