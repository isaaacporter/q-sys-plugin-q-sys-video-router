# Q-SYS Video Router

A Q-SYS plugin that drives a **Router component already in the design** (Router,
Router with Mixer, or MediaCast Router) through the `Component` library. It gives
an operator a source-first matrix surface plus a one-to-all mode, and hides
sources and destinations that are not physically connected.

The Control page reads left to right the way signal flows: **sources on the
left, destinations on the right**, with each destination carrying its own
routed-source ComboBox.

## Routing modes

**One-To-One (Matrix)** -- full matrix. `Matrix Select Order` picks which axis the
operator touches first, and that choice decides which axis is the interlock.

*Source First* (default):

1. Press a source. Source buttons are **interlocked** -- exactly one is armed.
   Arming a source **does not route anything** on its own.
2. Every destination already carrying that source **highlights**. More than one
   can be lit, which is the point -- it shows the source's current fan-out.
3. Press a destination to send the armed source there. Press several to fan out.

Arming a different source re-lights the destination row against that source, so
the surface reads as "where is this source going right now".

*Destination First*:

1. Press a destination. Destination buttons are **interlocked** -- exactly one is
   ever selected.
2. The source currently routed to that destination **highlights** immediately.
3. Press a source to route it to the selected destination.

Switching destinations re-highlights to show that destination's current source,
so the surface always reads as "what is this output watching right now".

On the **Setup** page, destination-first order also replaces the Selection
row's source readout with a **Source ComboBox** (`selected_dest_source`), drawn
after the selected destination so it reads in step order. It shows the source
routed to the selected destination, and picking a source from it routes it
there -- the same action as pressing that source's button. It follows the same
rules as the per-destination combos below (visible sources only, no "None",
locked out in One-To-All, refused picks snap back). In One-To-All it shows the
source every output shares, or blank if they differ. The control only exists in
destination-first order.

**One-To-All** -- press a source and it is routed to **every** output on the
router. A source lights only when *all* outputs sit on it; if any output differs
(routed elsewhere in the design, say) nothing is lit, because no single source
describes the state.

Mode is chosen by the `mode_matrix` / `mode_all` buttons (interlocked), with
`Default Mode` setting the power-on state. Those buttons are **pin-only** -- they
are not drawn on either page, because the operator surface is fixed-mode. Set
the mode with `Default Mode` at commissioning, or drive the pins from room
logic. Destination selection is disabled in One-To-All, where it has no meaning.

## Routed Source combo box

Each destination has a `dest_source_NNN` **ComboBox** rather than a read-only
name field. It does two jobs:

- **Reads back** the source currently routed to that output.
- **Sets** the route: pick a source from the list and that output follows it,
  with no need to touch the source/destination buttons at all.

The list is built from this plugin's own source names (`source_name_NNN`,
falling back to `Source N`), because a ComboBox can only read back a string that
is in its own choice list. Consequences worth knowing:

- **The list is sources only -- there is no "None".** A router output has no off
  position (select is 1-based), so nothing can unroute an output and the combo
  does not pretend otherwise. An output whose route cannot be read (no router
  bound yet) reads back blank.
- **Only visible sources are offered.** Hiding a source removes it from every
  combo, and forcing the string anyway is refused.
- **Duplicate names are disambiguated by index** (`Blu-ray`, `Blu-ray (4)`), so a
  choice string always maps back to exactly one source.
- **The combo is disabled in One-To-All mode**, where routing a single output on
  its own would contradict the mode.
- A rejected or stale pick **snaps back** to the route the router actually
  reports, so the field never lies about the current state.

The list is only rewritten when a name or a visibility flag changes, so a
settled system does no work.

## Visibility

Every source and destination has a **visibility input pin**
(`source_visible_NNN`, `dest_visible_NNN`, default high). Drive one low -- from a
sync-detect, an HDMI hotplug flag, or room logic -- and that entry is hidden from
the plugin panel and refuses to route. The pins are also readable, so a UCI can
bind its own element visibility to the same state.

A hidden entry is fully out of the surface: it is invisible, refuses to route,
is dropped from the routed-source combo lists, and **never stays lit**. If the
hidden entry was the interlocked selection, the selection moves to the first
visible one rather than parking on something the operator cannot see.

## Properties

| Property | Range | Purpose |
|---|---|---|
| `Source Count` | 1-64 | Router inputs to expose |
| `Destination Count` | 1-64 | Router outputs to expose |
| `Default Mode` | Matrix / All | Power-on mode |
| `Matrix Select Order` | Source First (default) / Destination First | Which axis is the interlock in One-To-One |
| `Debug Print` | None / Function Calls / Routes / All | Console verbosity |

Grids wrap into columns of 16 entries, so a 64-output router still lays out
sensibly.

## Control naming: the trap this plugin avoids

The classic **Router** / **Router with Mixer** names each output selector
`select.N`. The **MediaCast Router** renamed the same control to
**`output.N.select`** -- the index comes *before* `select`. A plugin that
hardcodes either form **silently fails** on the other: no error, the control just
never resolves and nothing routes.

This plugin therefore **probes both forms** per output and caches the winner,
re-resolving whenever the bound component changes. The resolved form is displayed
in the **Naming** readout (`select.N` or `output.N.select`) so a mis-binding is
visible at a glance instead of presenting as "the buttons do nothing".

Nothing else about the router's control naming is assumed. The routed source is
read as an index from the select control and labelled from this plugin's own
source names, so router variants that name their source-name readout differently
(or do not have one) make no difference.

Discovery accepts a component as a router if its `Type` contains `router`, or if
either select-naming form is present on it.

## Pins

Per destination: `dest_select_NNN`, `dest_name_NNN`, `dest_visible_NNN`,
`dest_source_NNN` (routed source, **input and output** -- writing a valid choice
string routes that output), `dest_route_NNN` (routed source index, 0 = none).

Per source: `source_select_NNN`, `source_name_NNN`, `source_visible_NNN`.

Global: `router_select`, `router_found`, `router_style`, `status`,
`selected_dest_name`, `selected_source_name`, plus the pin-only `mode_matrix`,
`mode_all` and `mode_name`. Only the interlocked axis populates its `selected_*`
readout; the other stays empty. In destination-first order `selected_source_name`
is pin-only (not drawn), since `selected_dest_source` takes its place.

Destination-first only: `selected_dest_source` (source routed to the selected
destination, **input and output** -- writing a valid choice string routes the
selected destination).

## Feedback correctness

Routes are read back from the router, never inferred from the press, so routes
changed anywhere else in the design track correctly. Two rules from
`qsys_preferences.md` are load-bearing here:

- **All feedback writes are conditional** (`if ctl.Boolean ~= want then ...`), so
  a settled control emits no events at all. The suppression depth counter is only
  a fast path. This matters doubly for the routed-source combo: Q-SYS fires a
  handler on a script `String` write too, so an unconditional write would turn
  every feedback refresh into a re-route request.
- **Only a button going high is treated as a request.** A low event is either the
  interlock clearing that button or the operator pressing the already-active one,
  so it re-asserts authoritative state instead of being adopted. Without this, a
  deferred-dispatch runtime turns "clear the old source button" into "route to
  that source", and the mode pair fights itself.

A 2 s poll refreshes feedback as a safety net for router variants that do not
raise change events on their select controls. Because every write is conditional,
a settled system produces zero control events from that poll.

## Build

`.vscode` task **Compile QSD Plugin** (PLUGCC + copy into the Designer plugins
folder), or directly:

```
plugincompile\PLUGCC.exe QsysVideoRouter <folder>\plugin.lua
```

## Tests

`tests/harness.py` runs the compiled `.qplug` outside Designer under `lupa`
(see `qsys_preferences.md`), mocking `Controls` / `Properties` / `Component` /
`Timer`. Run it with `python tests/harness.py`.

It executes the full cross product of:

- select order: source-first and destination-first
- router naming: `select.N` and `output.N.select`
- event dispatch: synchronous and deferred
- event firing: on-change and fire-always

16 cases, plus design-time layout validation at 1x1, 8x4, 64x64 and 17x33 (every
laid-out key resolves to a real control; all geometry numeric).

All four dispatch/firing permutations matter -- **three real bugs appeared only
under deferred dispatch**, where the suppression guard has already dropped by the
time a handler runs:

- clearing a source button re-routed to that source
- clearing a mode button flipped the mode back, latching both lit
- the destination interlock thrashed (149,980 events on one control)

The suite is mutation-tested: 30 mutations, all caught. Mutation testing earned
its place here -- it exposed a blind spot where nothing asserted that a hidden
source *goes dark* rather than merely turning invisible.

The destination-first selection combo tests (`S*`) caught a Lua `a and b or c`
trap on the way in: in One-To-All, `CommonRoute()` returns nil when outputs
differ, which silently fell through to the selected destination's route. The
readout now branches explicitly, and a mutation re-introduces the trap to keep
it caught.
