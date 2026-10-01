// Door capabilities (doc/rewrite/dx_conventions.md §2; design review §5, "door behaviours"), and
// door(), the bundle that puts a powered door's parts together:
//
//	/obj/machinery/door/airlock/capabilities()
//		. = ..()
//		. += door(wires = /datum/wires/airlock, electrify = TRUE, ai_control = TRUE)
//		. += cap_frozen_shut()
//
// The parts: cap_bolts(), cap_electrify(), cap_weld_shut(), cap_pry(), cap_emergency_access(),
// cap_door_access(), cap_crush(), cap_door_timing(), cap_ai_control().
// These own the door's state bits (CAP_BOLTED, CAP_WELDED, CAP_EMERGENCY_ACCESS), its tool entries, the
// gating and the layers. The door's mechanism stays on the door: a capability moves it through the
// holder hooks below (set_bolted(), is_electrified(), electric_shock(), cap_pry_force()), which a door
// overrides with its own behaviour procs (airlock lock()/unlock(), shock(), open()/close()).

// ---- shared entry setup ----

/**
 * Finishes an entry a library capability built with hand()/tool()/use_on(): the stance it answers
 * (the resolver offers it only for that stance, and a hostile stance ranks by combat mode), the
 * holder proc that says whether it is offered at all, whether cap_electrify() may zap it, the tool
 * sound (null keeps the pipeline's), and the legacy entry proc that runs it (click_ctrl()). Returns E.
 */
/proc/cap_entry_setup(datum/interaction/capability/E, stance, applies, insulated = FALSE, tool_volume, legacy_entry)
	if(stance)
		E.stance = stance
		E.apply_stance_tags()
	if(applies)
		E.applies = applies
	E.insulated = insulated
	if(!isnull(tool_volume))
		E.tool_volume = tool_volume
	if(legacy_entry)
		E.entry = legacy_entry
	return E

/// The stances a Use can have, in the order per-stance entries are listed.
GLOBAL_LIST_INIT(cap_all_stances, list(I_HELP, I_DISARM, I_GRAB, I_HURT))

// ============================================================================
// cap_bolts(): CAP_BOLTED. Dropped and raised by the door's own controls (wires, the AI, a UI, a
// button): no entry of its own. The door refuses to open while bolted (its can_open() reads
// is_bolted()), and cap_pry() refuses. Layer: `layer` while bolted (null: the holder draws its own).
// No examine line: bolt lights that are off hide the bolts on purpose.

/datum/capability/bolts
	/// The layer drawn while bolted, or null when the holder's draw() shows it (a door_locked state).
	var/layer = LOOK_BOLTS

/// Door bolts. layer: the overlay while bolted (null: the holder draws the state itself).
/proc/cap_bolts(layer = LOOK_BOLTS, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/bolts/C = new
	C.layer = layer
	cap_gating(C, behind = behind, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)
	return C

/datum/capability/bolts/draw(atom/holder, datum/look/look)
	if(layer)
		look.part(layer, !!(is_bolted(holder)))

/datum/capability/bolts/ui_data(atom/holder, mob/user, list/data)
	data["bolted"] = is_bolted(holder)

/// Drops (on) or raises the bolts through the holder's own mechanism. forced skips the mechanism's
/// refusals (a door mid-swing, no power, a cut bolt wire). TRUE when they moved. A holder with no
/// mechanism of its own just flips the bit.
/atom/proc/set_bolted(on, forced = FALSE)
	return cap_set(src, CAP_BOLTED, on)

// ============================================================================
// cap_electrify(): an electrified holder zaps whoever touches it. Every entry of the holder that
// isn't `insulated` shocks a non-silicon user first: touch_chance for a bare hand, item_chance
// through a held item; a shock stops the entry. The state is the holder's (is_electrified(), usually a
// timed_set() var) and the shock is the holder's (electric_shock()). UI: electrified,
// electrified_left (seconds, -1 for permanent).

/datum/capability/electrify
	var/touch_chance = 100
	var/item_chance = 75

/// Zaps on touch while the holder is_electrified(): touch_chance by hand, item_chance with an item.
/proc/cap_electrify(touch_chance = 100, item_chance = 75, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/electrify/C = new
	cap_gating(C, behind = behind, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)
	C.touch_chance = touch_chance
	C.item_chance = item_chance
	return C

/datum/capability/electrify/before_entry(atom/holder, mob/user, obj/item/held, datum/interaction/capability/entry)
	if(entry.insulated || issilicon(user) || !holder.is_electrified())
		return FALSE
	return holder.electric_shock(user, held ? item_chance : touch_chance)

/datum/capability/electrify/ui_data(atom/holder, mob/user, list/data)
	data["electrified"] = holder.is_electrified()
	data["electrified_left"] = holder.electrified_left()

/// Whether touching the holder shocks now (cap_electrify()).
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
// cap_weld_shut(): CAP_WELDED, toggled with a welder. One entry per stance, as the airlock's old ones
// were: `applies` (a holder proc) says when welding is offered at all, and `help_applies`
// narrows it outside combat mode (an airlock that needs repair is repaired instead). An entry that
// isn't offered is hidden, so the welder falls through to the holder's other welder use. Layer:
// `layer` while welded. Examine: "It has been welded shut."

/datum/capability/weld_shut
	var/tool_quality = TOOL_WELDER
	var/applies
	var/help_applies
	var/layer = LOOK_WELDED

/// Weld shut with `tool`. applies / help_applies: holder procs, () -> whether welding is offered.
/proc/cap_weld_shut(tool = TOOL_WELDER, applies, help_applies, layer = LOOK_WELDED, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/weld_shut/C = new
	C.tool_quality = tool
	C.applies = applies
	C.help_applies = help_applies
	C.layer = layer
	cap_gating(C, behind = behind, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)
	return C

/// Welds A shut or unwelds it with no welder (a construct's spell, a mech clamp tearing it open).
/proc/set_welded(atom/A, on)
	return cap_set(A, CAP_WELDED, on)

/datum/capability/weld_shut/interactions(atom/holder)
	. = list()
	for(var/stance in GLOB.cap_all_stances)
		var/datum/capability/entry/wrapper = cap_tool("Weld shut", tool_quality, GLOBAL_PROC_REF(cap_weld_toggle), works_broken = TRUE, works_unpowered = TRUE, log = log, name_proc = GLOBAL_PROC_REF(cap_weld_name))
		var/datum/interaction/capability/E = adopt_entry(wrapper, id = "weld_shut:[tool_quality]:[stance]")
		// The handler plays the welder's sound itself, louder, as the old weld did.
		cap_entry_setup(E, stance = stance, applies = (stance == I_HELP && help_applies) ? help_applies : applies, tool_volume = 0)
		. += E

/datum/capability/weld_shut/examine(atom/holder, mob/user)
	if(is_welded(holder))
		return list("It has been welded shut.")
	return null

/datum/capability/weld_shut/draw(atom/holder, datum/look/look)
	if(layer)
		look.part(layer, !!(is_welded(holder)))

/datum/capability/weld_shut/ui_data(atom/holder, mob/user, list/data)
	data["welded"] = is_welded(holder)

/proc/cap_weld_name(atom/holder, mob/user)
	return is_welded(holder) ? "Unweld" : "Weld shut"

/proc/cap_weld_toggle(atom/holder, mob/user, obj/item/held)
	var/obj/item/weldingtool/welder = held?.get_welder()
	if(welder && !welder.remove_fuel(0, user))
		return refuse(user, "[held] needs to be lit.")
	var/welding = !is_welded(holder)
	cap_set(holder, CAP_WELDED, welding)
	if(held?.usesound)
		playsound(holder, held.usesound, 75, 1)
	act_message(user, holder, self = welding ? "You weld %T% shut." : "You unweld %T%.", others = welding ? "%U% welds %T% shut." : "%U% unwelds %T%.")
	return TRUE

// ============================================================================
// cap_pry(): forcing the holder open or closed with a crowbar outside combat mode (in combat mode the
// crowbar strikes instead). Refused while welded or bolted, and while powered unless the tool's tier
// reaches `strong_tier`; the holder refines the refusals (cap_pry_reason()) and the effect
// (cap_pry_force(): a door opens or closes). No state, no layer.

/datum/capability/pry
	var/tool_quality = TOOL_CROWBAR
	/// A tool of this tier or better forces it even while powered (0: never).
	var/strong_tier = 0

/// Pry with `tool`, while unpowered (or with a tool of `strong_tier`), unbolted and unwelded.
/proc/cap_pry(tool = TOOL_CROWBAR, strong_tier = 0, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/pry/C = new
	C.tool_quality = tool
	C.strong_tier = strong_tier
	cap_gating(C, behind = behind, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)
	return C

/datum/capability/pry/interactions(atom/holder)
	. = list()
	for(var/stance in list(I_HELP, I_DISARM, I_GRAB))
		var/datum/capability/entry/wrapper = cap_tool("Force open or closed", tool_quality, TYPE_PROC_REF(/atom, cap_pry_force), needs = TYPE_PROC_REF(/atom, cap_pry_reason), works_broken = TRUE, works_unpowered = TRUE, log = log, name_proc = TYPE_PROC_REF(/atom, cap_pry_name))
		var/datum/interaction/capability/E = adopt_entry(wrapper, id = "pry:[tool_quality]:[stance]")
		cap_entry_setup(E, stance = stance, tool_volume = 0)
		. += E

/// Why prying fails now (text), or TRUE. A holder with more to say overrides it.
/atom/proc/cap_pry_reason(mob/user, obj/item/held)
	if(is_welded(src))
		return "it's welded shut"
	if(is_bolted(src))
		return "its bolts prevent it from being forced"
	if(cap_of(src, /datum/capability/powered) && cap_powered())
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
// cap_emergency_access(): CAP_EMERGENCY_ACCESS. While engaged the door lets anyone through (a door's access
// check reads emergency_access_on()). Toggled by the door's controls. Layer: `layer` while engaged.

/datum/capability/emergency_access
	var/layer = LOOK_EMERGENCY

/// Emergency access. layer: the overlay while engaged (null: nothing drawn).
/proc/cap_emergency_access(layer = LOOK_EMERGENCY, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/emergency_access/C = new
	C.layer = layer
	cap_gating(C, behind = behind, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)
	return C

/proc/emergency_access_on(atom/A)
	return !!(A.cap_state & CAP_EMERGENCY_ACCESS)

/proc/set_emergency_access(atom/A, on)
	return cap_set(A, CAP_EMERGENCY_ACCESS, on)

/datum/capability/emergency_access/examine(atom/holder, mob/user)
	if(emergency_access_on(holder))
		return list("Its emergency access mode is engaged.")
	return null

/datum/capability/emergency_access/draw(atom/holder, datum/look/look)
	if(layer)
		look.part(layer, !!(emergency_access_on(holder)))

/datum/capability/emergency_access/ui_data(atom/holder, mob/user, list/data)
	data["emergency"] = emergency_access_on(holder)

// ============================================================================
// cap_door_access(): a door's access check, in the lock family (cap_of(A, /datum/capability/lock) finds
// it) but with no swipe toggle: a door is opened by an allowed ID, never locked by one. grants()
// reads the door's own req_access / req_one_access (design review H1: maps set them per door); the
// arguments are the type default. No layer, no examine line, no UI data.

/datum/capability/lock/door

/// A door's access: access (all required) and/or req_one_access (any one), as type defaults.
/proc/cap_door_access(list/access, list/req_one_access)
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
// cap_crush(): a closing door crushes what stands in it (atom/movable/airlock_crush()) and takes the
// same damage itself. `damage` is the type default; a caller of close() may pass its own. The
// safeties that stop a door closing on someone are the holder's (door_safeties_on()). UI: safe.

/datum/capability/crush
	var/damage = DOOR_CRUSH_DAMAGE

/// A door that crushes what it closes on, for `damage` (the type default).
/proc/cap_crush(damage = DOOR_CRUSH_DAMAGE, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/crush/C = new
	C.damage = damage
	cap_gating(C, behind = behind, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)
	return C

/// Crushes everything in holder's tiles for `amount` (null: this capability's damage). TRUE when
/// anything was crushed; the holder takes the damage once per crushed thing.
/datum/capability/crush/proc/crush(atom/movable/holder, amount)
	var/dealt = isnull(amount) ? damage : amount
	. = FALSE
	for(var/turf/T in holder.locs)
		for(var/atom/movable/AM in T)
			if(AM.airlock_crush(dealt))
				holder.take_damage(dealt, BRUTE, MELEE)
				. = TRUE

/datum/capability/crush/ui_data(atom/holder, mob/user, list/data)
	data["safe"] = holder.door_safeties_on()

/// Whether the holder's safeties stop it closing on someone (cap_crush()).
/atom/proc/door_safeties_on()
	return TRUE

/// Crushes what stands in A's tiles through its cap_crush() (nothing without one). amount: null for
/// the capability's type default.
/proc/door_crush(atom/movable/A, amount)
	var/datum/capability/crush/C = cap_of(A, /datum/capability/crush)
	return C ? C.crush(A, amount) : FALSE

// ============================================================================
// cap_door_timing(): how long a door stays open before it closes itself. The door's own vars say
// whether it autocloses (`autoclose`) and at which speed (`normalspeed`, the timing wire); the
// opening animation delays are its type vars (anim_length_before_density / _finalize). The waits
// here are type defaults: `close_wait` normally, `thermal_wait` when the air on either side differs
// by 5 K or more (keep the heat in), `fast_wait` at high speed. UI: speed.

/datum/capability/door_timing
	var/close_wait = 15 SECONDS
	var/thermal_wait = 1.5 SECONDS
	var/fast_wait = 0.5 SECONDS

/// Door timing: the autoclose waits (type defaults; see above).
/proc/cap_door_timing(close_wait = 15 SECONDS, thermal_wait = 1.5 SECONDS, fast_wait = 0.5 SECONDS)
	var/datum/capability/door_timing/C = new
	C.close_wait = close_wait
	C.thermal_wait = thermal_wait
	C.fast_wait = fast_wait
	return C

/// How long holder waits open before closing itself.
/datum/capability/door_timing/proc/wait_for(obj/machinery/door/holder)
	if(!holder.normalspeed)
		return fast_wait
	var/lowest_temp = T20C
	var/highest_temp = T0C
	for(var/D in GLOB.cardinal)
		var/turf/target = get_step(holder.loc, D)
		if(!target || target.density)
			continue
		var/datum/gas_mixture/airmix = target.return_air()
		if(!airmix)
			continue
		var/airmix_temp = airmix.return_temperature()
		lowest_temp = min(lowest_temp, airmix_temp)
		highest_temp = max(highest_temp, airmix_temp)
	return abs(highest_temp - lowest_temp) >= 5 ? thermal_wait : close_wait

/datum/capability/door_timing/ui_data(atom/holder, mob/user, list/data)
	var/obj/machinery/door/D = holder
	if(istype(D))
		data["speed"] = D.normalspeed

// ============================================================================
// door(): the BUNDLE of a powered door (bundles are plain nouns; the parts stay cap_<noun>). It
// encodes how the parts relate: the wires sit behind the maintenance panel; the door's access is its
// own req_access (H1); bolts and welding both refuse a pry; a closing door crushes; the autoclose
// timing reads the door's vars. A type adds door(...) and then only what is its own:
//
//	/obj/machinery/door/airlock/capabilities()
//		. = ..()
//		. += door(wires = /datum/wires/airlock, electrify = TRUE, ai_control = TRUE)
//		. += cap_frozen_shut()
//
// Named args pick the variations; `without()` / `replace()` edit the result like any list.
/proc/door(wires, electrify = FALSE, ai_control = FALSE, panel_tool = TOOL_SCREWDRIVER, repair_tool = null, emag_effect, emag_mode = EMAG_REPEATABLE, emag_log = LOG_GAME, bolts_layer = null, emergency_layer = null, weld_applies, weld_help_applies, pry_strong_tier = 0, crush_damage = DOOR_CRUSH_DAMAGE, close_wait = 15 SECONDS)
	. = list(cap_panel(tool = panel_tool))
	if(wires)
		. += cap_wires(wires, behind = PANEL)
	. += cap_door_access()
	. += cap_breakable(repair_tool = repair_tool)
	. += cap_power()
	. += cap_emag(effect = emag_effect, mode = emag_mode, log = emag_log)
	. += cap_bolts(layer = bolts_layer)
	if(electrify)
		. += cap_electrify()
	. += cap_weld_shut(applies = weld_applies, help_applies = weld_help_applies)
	. += cap_pry(strong_tier = pry_strong_tier)
	. += cap_emergency_access(layer = emergency_layer)
	. += cap_crush(damage = crush_damage)
	. += cap_door_timing(close_wait = close_wait)
	if(ai_control)
		. += cap_ai_control()

// ============================================================================
// cap_ai_control(): the airlock's remote control panel (the AiAirlock window, opened by the AI and by
// cyborgs with the door's access). It owns the window's actions (act_<action> below, run on this
// shared capability with the airlock as `holder`; the airlock's ui_allowed() gates them all) and adds
// the panel's data: power, the ID scanner, bolt lights, the door's position and the wire states. The
// other door capabilities add bolted, welded, electrified, emergency, safe and speed.

/datum/capability/ai_control

/proc/cap_ai_control()
	return new /datum/capability/ai_control

/// The AiAirlock actions that are logged (cap_ai_control()'s ui_logged()).
GLOBAL_LIST_INIT(cap_ai_control_logged, list(
	"shock_temp" = LOG_GAME,
	"shock_perm" = LOG_GAME,
	"bolt_toggle" = LOG_GAME,
	"emergency_toggle" = LOG_GAME,
))

/datum/capability/ai_control/ui_logged()
	return GLOB.cap_ai_control_logged

/datum/capability/ai_control/proc/act_disrupt_main(mob/user, obj/machinery/door/airlock/holder)
	if(holder.main_power_lost_until)
		return refuse(user, "Main power is already offline.")
	holder.loseMainPower()
	return TRUE

/datum/capability/ai_control/proc/act_disrupt_backup(mob/user, obj/machinery/door/airlock/holder)
	if(holder.backup_power_lost_until)
		return refuse(user, "Backup power is already offline.")
	holder.loseBackupPower()
	return TRUE

/datum/capability/ai_control/proc/act_shock_restore(mob/user, obj/machinery/door/airlock/holder)
	holder.electrify(0, TRUE, user)
	return TRUE

/datum/capability/ai_control/proc/act_shock_temp(mob/user, obj/machinery/door/airlock/holder)
	holder.electrify(30, TRUE, user)
	return TRUE

/datum/capability/ai_control/proc/act_shock_perm(mob/user, obj/machinery/door/airlock/holder)
	holder.electrify(-1, TRUE, user)
	return TRUE

/datum/capability/ai_control/proc/act_idscan_toggle(mob/user, obj/machinery/door/airlock/holder)
	holder.set_idscan(holder.aiDisabledIdScanner, TRUE, user)
	return TRUE

/datum/capability/ai_control/proc/act_emergency_toggle(mob/user, obj/machinery/door/airlock/holder)
	set_emergency_access(holder, !emergency_access_on(holder))
	to_chat(user, span_notice("Emergency access is now [emergency_access_on(holder) ? "engaged" : "disengaged"]."))
	return TRUE

/datum/capability/ai_control/proc/act_bolt_toggle(mob/user, obj/machinery/door/airlock/holder)
	holder.toggle_bolt(user)
	return TRUE

/datum/capability/ai_control/proc/act_light_toggle(mob/user, obj/machinery/door/airlock/holder)
	if(holder.wire_cut(WIRE_BOLT_LIGHT))
		return refuse(user, "The bolt lights wire is cut - The door bolt lights are permanently disabled.")
	holder.lights = !holder.lights
	return TRUE

/datum/capability/ai_control/proc/act_safe_toggle(mob/user, obj/machinery/door/airlock/holder)
	holder.set_safeties(!holder.safe, TRUE, user)
	return TRUE

/datum/capability/ai_control/proc/act_speed_toggle(mob/user, obj/machinery/door/airlock/holder)
	if(holder.wire_cut(WIRE_SPEED))
		return refuse(user, "The timing wire is cut - Cannot alter timing.")
	holder.normalspeed = !holder.normalspeed
	return TRUE

/datum/capability/ai_control/proc/act_open_close(mob/user, obj/machinery/door/airlock/holder)
	holder.user_toggle_open(user)
	return TRUE

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
