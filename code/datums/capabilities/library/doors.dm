// Door capabilities (doc/rewrite/dx_conventions.md §2; design review §5, "door behaviours").
//
//	/obj/machinery/door/airlock/capabilities()
//		. = ..()
//		. += bolts()
//		. += electrification()
//		. += weld_shut(offered_if = PROC_REF(can_weld_now))
//		. += pry()
//		. += emergency_access()
//		. += ai_control()
//
// These own the door's state bits (CAP_BOLTED, CAP_WELDED, CAP_EMERGENCY), its tool entries, the
// gating and the layers. The door's mechanism stays on the door: a capability moves it through the
// holder hooks below (set_bolted(), is_electrified(), electric_shock(), cap_pry_force()), which a door
// overrides with its own behaviour procs (airlock lock()/unlock(), shock(), open()/close()).

// ---- shared entry setup ----

/**
 * Finishes an entry a library capability built with hand()/tool()/use_on(): the stance it answers
 * (the resolver offers it only for that stance, and a hostile stance ranks by combat mode), the
 * holder proc that says whether it is offered at all, whether electrification() may zap it, the tool
 * sound (null keeps the pipeline's), and the legacy entry proc that runs it (click_ctrl()). Returns E.
 */
/proc/cap_entry_setup(datum/interaction/capability/E, stance, offered_if, insulated = FALSE, tool_volume, legacy_entry)
	if(stance)
		E.stance = stance
		E.apply_stance_tags()
	if(offered_if)
		E.offered_if = offered_if
	E.insulated = insulated
	if(!isnull(tool_volume))
		E.tool_volume = tool_volume
	if(legacy_entry)
		E.entry = legacy_entry
	return E

/// The stances a Use can have, in the order per-stance entries are listed.
GLOBAL_LIST_INIT(cap_all_stances, list(I_HELP, I_DISARM, I_GRAB, I_HURT))

// ============================================================================
// bolts(): CAP_BOLTED. Dropped and raised by the door's own controls (wires, the AI, a UI, a
// button): no entry of its own. The door refuses to open while bolted (its can_open() reads
// is_bolted()), and pry() refuses. Layer: `layer` while bolted (null: the holder draws its own).
// No examine line: bolt lights that are off hide the bolts on purpose.

/datum/capability/bolts
	/// The layer drawn while bolted, or null when the holder's draw() shows it (a door_locked state).
	var/layer = "bolts"

/// Door bolts. layer: the overlay while bolted (null: the holder draws the state itself).
/proc/bolts(layer = "bolts", log)
	var/datum/capability/bolts/C = new
	C.layer = layer
	C.log = log
	return C

/proc/is_bolted(atom/A)
	return !!(A.cap_state & CAP_BOLTED)

/datum/capability/bolts/draw(atom/holder, datum/look/look)
	if(layer)
		look.overlay(layer, when = is_bolted(holder))

/datum/capability/bolts/ui_data(atom/holder, mob/user, list/data)
	data["bolted"] = is_bolted(holder)

/// Drops (on) or raises the bolts through the holder's own mechanism. forced skips the mechanism's
/// refusals (a door mid-swing, no power, a cut bolt wire). TRUE when they moved. A holder with no
/// mechanism of its own just flips the bit.
/atom/proc/set_bolted(on, forced = FALSE)
	return cap_set(src, CAP_BOLTED, on)

// ============================================================================
// electrification(): an electrified holder zaps whoever touches it. Every entry of the holder that
// isn't `insulated` shocks a non-silicon user first: touch_chance for a bare hand, item_chance
// through a held item; a shock stops the entry. The state is the holder's (is_electrified(), usually a
// timed_set() var) and the shock is the holder's (electric_shock()). UI: electrified,
// electrified_left (seconds, -1 for permanent).

/datum/capability/electrification
	var/touch_chance = 100
	var/item_chance = 75

/// Zaps on touch while the holder is_electrified(): touch_chance by hand, item_chance with an item.
/proc/electrification(touch_chance = 100, item_chance = 75)
	var/datum/capability/electrification/C = new
	C.touch_chance = touch_chance
	C.item_chance = item_chance
	return C

/datum/capability/electrification/before_entry(atom/holder, mob/user, obj/item/held, datum/interaction/capability/entry)
	if(entry.insulated || issilicon(user) || !holder.is_electrified())
		return FALSE
	return holder.electric_shock(user, held ? item_chance : touch_chance)

/datum/capability/electrification/ui_data(atom/holder, mob/user, list/data)
	data["electrified"] = holder.is_electrified()
	data["electrified_left"] = holder.electrified_left()

/// Whether touching the holder shocks now (electrification()).
/atom/proc/is_electrified()
	return FALSE

/// Seconds until the holder stops being electrified: -1 while permanently, 0 while not.
/atom/proc/electrified_left()
	return 0

/// Shocks user with `chance` percent. TRUE when it did (the entry stops).
/atom/proc/electric_shock(mob/user, chance)
	return FALSE

/obj/machinery/electric_shock(mob/user, chance)
	return shock(user, chance)

// ============================================================================
// weld_shut(): CAP_WELDED, toggled with a welder. One entry per stance, as the airlock's old ones
// were: `offered_if` (a holder proc) says when welding is offered at all, and `help_offered_if`
// narrows it outside combat mode (an airlock that needs repair is repaired instead). An entry that
// isn't offered is hidden, so the welder falls through to the holder's other welder use. Layer:
// `layer` while welded. Examine: "It has been welded shut."

/datum/capability/weld_shut
	var/tool_quality = TOOL_WELDER
	var/offered_if
	var/help_offered_if
	var/layer = "welded"

/// Weld shut with `tool`. offered_if / help_offered_if: holder procs, () -> whether welding is offered.
/proc/weld_shut(tool = TOOL_WELDER, offered_if, help_offered_if, layer = "welded", log)
	var/datum/capability/weld_shut/C = new
	C.tool_quality = tool
	C.offered_if = offered_if
	C.help_offered_if = help_offered_if
	C.layer = layer
	C.log = log
	return C

/proc/is_welded(atom/A)
	return !!(A.cap_state & CAP_WELDED)

/// Welds A shut or unwelds it with no welder (a construct's spell, a mech clamp tearing it open).
/proc/set_welded(atom/A, on)
	return cap_set(A, CAP_WELDED, on)

/datum/capability/weld_shut/interactions(atom/holder)
	. = list()
	for(var/stance in GLOB.cap_all_stances)
		var/datum/capability/entry/wrapper = tool("Weld shut", tool_quality, TYPE_PROC_REF(/atom, cap_weld_toggle), works_broken = TRUE, works_unpowered = TRUE, log = log, name_proc = TYPE_PROC_REF(/atom, cap_weld_name))
		var/datum/interaction/capability/E = own_entry(wrapper, id = "weld_shut:[tool_quality]:[stance]")
		// The handler plays the welder's sound itself, louder, as the old weld did.
		cap_entry_setup(E, stance = stance, offered_if = (stance == I_HELP && help_offered_if) ? help_offered_if : offered_if, tool_volume = 0)
		. += E

/datum/capability/weld_shut/examine(atom/holder, mob/user)
	if(is_welded(holder))
		return list("It has been welded shut.")
	return null

/datum/capability/weld_shut/draw(atom/holder, datum/look/look)
	if(layer)
		look.overlay(layer, when = is_welded(holder))

/datum/capability/weld_shut/ui_data(atom/holder, mob/user, list/data)
	data["welded"] = is_welded(holder)

/atom/proc/cap_weld_name(mob/user)
	return is_welded(src) ? "Unweld" : "Weld shut"

/atom/proc/cap_weld_toggle(mob/user, obj/item/held)
	var/obj/item/weldingtool/welder = held?.get_welder()
	if(welder && !welder.remove_fuel(0, user))
		return refuse(user, "[held] needs to be lit.")
	var/welding = !is_welded(src)
	cap_set(src, CAP_WELDED, welding)
	if(held?.usesound)
		playsound(src, held.usesound, 75, 1)
	act_message(user, src, self = welding ? "You weld %T% shut." : "You unweld %T%.", others = welding ? "%U% welds %T% shut." : "%U% unwelds %T%.")
	return TRUE

// ============================================================================
// pry(): forcing the holder open or closed with a crowbar outside combat mode (in combat mode the
// crowbar strikes instead). Refused while welded or bolted, and while powered unless the tool's tier
// reaches `strong_tier`; the holder refines the refusals (cap_pry_reason()) and the effect
// (cap_pry_force(): a door opens or closes). No state, no layer.

/datum/capability/pry
	var/tool_quality = TOOL_CROWBAR
	/// A tool of this tier or better forces it even while powered (0: never).
	var/strong_tier = 0

/// Pry with `tool`, while unpowered (or with a tool of `strong_tier`), unbolted and unwelded.
/proc/pry(tool = TOOL_CROWBAR, strong_tier = 0, log)
	var/datum/capability/pry/C = new
	C.tool_quality = tool
	C.strong_tier = strong_tier
	C.log = log
	return C

/datum/capability/pry/interactions(atom/holder)
	. = list()
	for(var/stance in list(I_HELP, I_DISARM, I_GRAB))
		var/datum/capability/entry/wrapper = tool("Force open or closed", tool_quality, TYPE_PROC_REF(/atom, cap_pry_force), needs = TYPE_PROC_REF(/atom, cap_pry_reason), works_broken = TRUE, works_unpowered = TRUE, log = log, name_proc = TYPE_PROC_REF(/atom, cap_pry_name))
		var/datum/interaction/capability/E = own_entry(wrapper, id = "pry:[tool_quality]:[stance]")
		cap_entry_setup(E, stance = stance, tool_volume = 0)
		. += E

/// Why prying fails now (text), or TRUE. A holder with more to say overrides it.
/atom/proc/cap_pry_reason(mob/user, obj/item/held)
	if(is_welded(src))
		return "it's welded shut"
	if(is_bolted(src))
		return "its bolts prevent it from being forced"
	if(cap_powered())
		var/datum/capability/pry/C = cap_of(src, /datum/capability/pry)
		if(!C?.strong_tier || !held || dq_tool_tier(held, C.tool_quality) < C.strong_tier)
			return "its motors resist your efforts to force it"
	return TRUE

/atom/proc/cap_pry_name(mob/user)
	return "Force open or closed"

/// Forces the holder. A door opens or closes; anything else overrides it.
/atom/proc/cap_pry_force(mob/user, obj/item/held)
	return TRUE

/obj/machinery/door/cap_pry_force(mob/user, obj/item/held)
	if(density)
		open(TRUE)
	else
		close(TRUE)
	return TRUE

// ============================================================================
// emergency_access(): CAP_EMERGENCY. While engaged the door lets anyone through (a door's access
// check reads emergency_access_on()). Toggled by the door's controls. Layer: `layer` while engaged.

/datum/capability/emergency_access
	var/layer = "emergency"

/// Emergency access. layer: the overlay while engaged (null: nothing drawn).
/proc/emergency_access(layer = "emergency", log)
	var/datum/capability/emergency_access/C = new
	C.layer = layer
	C.log = log
	return C

/proc/emergency_access_on(atom/A)
	return !!(A.cap_state & CAP_EMERGENCY)

/proc/set_emergency_access(atom/A, on)
	return cap_set(A, CAP_EMERGENCY, on)

/datum/capability/emergency_access/examine(atom/holder, mob/user)
	if(emergency_access_on(holder))
		return list("Its emergency access mode is engaged.")
	return null

/datum/capability/emergency_access/draw(atom/holder, datum/look/look)
	if(layer)
		look.overlay(layer, when = emergency_access_on(holder))

/datum/capability/emergency_access/ui_data(atom/holder, mob/user, list/data)
	data["emergency"] = emergency_access_on(holder)

// ============================================================================
// door_access(): a door's access check, in the lock family (cap_of(A, /datum/capability/lock) finds
// it) but with no swipe toggle: a door is opened by an allowed ID, never locked by one. grants()
// reads the door's own req_access / req_one_access (design review H1: maps set them per door); the
// arguments are the type default. No layer, no examine line, no UI data.

/datum/capability/lock/door

/// A door's access: access (all required) and/or req_one_access (any one), as type defaults.
/proc/door_access(list/access, list/req_one_access)
	var/datum/capability/lock/door/C = new
	C.req_access = access
	C.req_one_access = req_one_access
	return C

/datum/capability/lock/door/interactions(atom/holder)
	return null

/datum/capability/lock/door/examine(atom/holder, mob/user)
	return null

/datum/capability/lock/door/draw(atom/holder, datum/look/look)
	return

/datum/capability/lock/door/ui_data(atom/holder, mob/user, list/data)
	return

// ============================================================================
// ai_control(): the airlock's remote control panel (the AiAirlock window, opened by the AI and by
// cyborgs with the door's access). The window's actions are ui_<action> procs on the airlock
// (airlock.dm); this adds the panel's data: power, the ID scanner, bolt lights, safeties, timing,
// the door's position and the wire states. The other door capabilities add bolted, welded,
// electrified and emergency.

/datum/capability/ai_control

/proc/ai_control()
	return new /datum/capability/ai_control

/datum/capability/ai_control/ui_data(atom/holder, mob/user, list/data)
	var/obj/machinery/door/airlock/A = holder
	if(!istype(A))
		return
	var/list/power = list()
	power["main"] = A.main_power_lost_until > 0 ? 0 : 2
	power["main_timeleft"] = A.main_power_lost_until > 0 ? round(time_left(A, nameof(A.main_power_lost_until)) / 10, 1) : A.main_power_lost_until
	power["backup"] = A.backup_power_lost_until > 0 ? 0 : 2
	power["backup_timeleft"] = A.backup_power_lost_until > 0 ? round(time_left(A, nameof(A.backup_power_lost_until)) / 10, 1) : A.backup_power_lost_until
	data["power"] = power
	data["id_scanner"] = !A.aiDisabledIdScanner
	data["lights"] = A.lights
	data["safe"] = A.safe
	data["speed"] = A.normalspeed
	data["opened"] = !A.density
	var/list/wire = list()
	wire["main_1"] = !A.wire_cut(WIRE_MAIN_POWER1)
	wire["main_2"] = !A.wire_cut(WIRE_MAIN_POWER2)
	wire["backup_1"] = !A.wire_cut(WIRE_BACKUP_POWER1)
	wire["backup_2"] = !A.wire_cut(WIRE_BACKUP_POWER2)
	wire["shock"] = !A.wire_cut(WIRE_ELECTRIFY)
	wire["id_scanner"] = !A.wire_cut(WIRE_IDSCAN)
	wire["bolts"] = !A.wire_cut(WIRE_DOOR_BOLTS)
	wire["lights"] = !A.wire_cut(WIRE_BOLT_LIGHT)
	wire["safe"] = !A.wire_cut(WIRE_SAFETY)
	wire["timing"] = !A.wire_cut(WIRE_SPEED)
	data["wires"] = wire
