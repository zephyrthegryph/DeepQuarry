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
// gating and the layers. The door's mechanism stays on the door: a capability moves it through its
// holder interface, procs of the capability that take the holder (bolts set_bolted(), electrify is_electrified() /
// shock(), pry reason() / force(), crush safeties_on()). A door with its own mechanism (the airlock's lock()/unlock(),
// open()/close()) declares capability subtypes overriding them and hands them to door(subtypes = list(...)); nothing
// is a proc on /atom.

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
// is_bolted()), and cap_pry() refuses. Look: part LOOK_BOLTS while bolted (a holder that shows its bolts
// another way, a door_locked state, hides it in its draw(): look.hide(LOOK_BOLTS)).
// No examine line: bolt lights that are off hide the bolts on purpose.

/datum/capability/bolts
	layer_name = LOOK_BOLTS

/// Door bolts. Draws LOOK_BOLTS while bolted. type: a subtype with the holder's own bolt mechanism.
/proc/cap_bolts(needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log, type = /datum/capability/bolts)
	var/datum/capability/bolts/C = new type
	cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)
	return C

/datum/capability/bolts/draw(atom/holder, datum/look/look)
	draw_layer(look, when = is_bolted(holder))

/datum/capability/bolts/ui_data(atom/holder, mob/user, list/data)
	data["bolted"] = is_bolted(holder)

/// Drops (on) or raises the bolts through the holder's own mechanism. forced skips the mechanism's
/// refusals (a door mid-swing, no power, a cut bolt wire). TRUE when they moved. The default has no
/// mechanism of its own and just flips the bit; a subtype overrides it.
/datum/capability/bolts/proc/set_bolted(atom/holder, on, forced = FALSE)
	return cap_set(holder, CAP_BOLTED, on)

/// Drops (on) or raises A's bolts through its bolts capability (just the bit without one).
/proc/set_bolted(atom/A, on, forced = FALSE)
	var/datum/capability/bolts/C = cap_of(A, /datum/capability/bolts)
	return C ? C.set_bolted(A, on, forced) : cap_set(A, CAP_BOLTED, on)

// ============================================================================
// cap_electrify(): an electrified holder zaps whoever touches it. Every entry of the holder that
// isn't `insulated` shocks a non-silicon user first: touch_chance for a bare hand, item_chance
// through a held item; a shock stops the entry. The state is the holder's (is_electrified(), usually a
// timed_set() var) and the shock is the holder's (a machine's shock()); a subtype answers both. UI: electrified,
// electrified_left (seconds, -1 for permanent).

/datum/capability/electrify
	var/touch_chance = 100
	var/item_chance = 75

/// Zaps on touch while the holder is_electrified(): touch_chance by hand, item_chance with an item. type: a subtype
/// answering is_electrified() / electrified_left() / shock() for the holder.
/proc/cap_electrify(touch_chance = 100, item_chance = 75, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log, type = /datum/capability/electrify)
	var/datum/capability/electrify/C = new type
	cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)
	C.touch_chance = touch_chance
	C.item_chance = item_chance
	return C

/datum/capability/electrify/before_entry(atom/holder, mob/user, obj/item/held, datum/interaction/capability/entry)
	if(entry.insulated || issilicon(user) || !is_electrified(holder))
		return FALSE
	return shock(holder, user, held ? item_chance : touch_chance)

/datum/capability/electrify/ui_data(atom/holder, mob/user, list/data)
	data["electrified"] = is_electrified(holder)
	data["electrified_left"] = electrified_left(holder)

/// Whether touching the holder shocks now.
/datum/capability/electrify/proc/is_electrified(atom/holder)
	return FALSE

/// Seconds until the holder stops being electrified: -1 while permanently, 0 while not.
/datum/capability/electrify/proc/electrified_left(atom/holder)
	return 0

/// Shocks user with `chance` percent. TRUE when it did (the entry stops). A machine shocks through its own shock().
/datum/capability/electrify/proc/shock(atom/holder, mob/user, chance)
	var/obj/machinery/M = holder
	return istype(M) ? M.shock(user, chance) : FALSE

/// Whether touching A shocks now (its cap_electrify()).
/proc/is_electrified(atom/A)
	var/datum/capability/electrify/C = cap_of(A, /datum/capability/electrify)
	return C ? C.is_electrified(A) : FALSE

/// Seconds until A stops being electrified (-1: permanently, 0: not).
/proc/electrified_left(atom/A)
	var/datum/capability/electrify/C = cap_of(A, /datum/capability/electrify)
	return C ? C.electrified_left(A) : 0

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
	layer_name = LOOK_WELDED

/// Weld shut with `tool`. applies / help_applies: holder procs, () -> whether welding is offered.
/proc/cap_weld_shut(tool = TOOL_WELDER, applies, help_applies, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/weld_shut/C = new
	C.tool_quality = tool
	C.applies = applies
	C.help_applies = help_applies
	cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)
	return C

/// Welds A shut or unwelds it with no welder (a construct's spell, a mech clamp tearing it open).
/proc/set_welded(atom/A, on)
	return cap_set(A, CAP_WELDED, on)

/// One structural op per stance, "weld_shut:<stance>" (each narrowed to its stance, as the old per-stance entries were), so
/// help_applies can hide the help one alone. A hostile stance's op is still ACT_USE: welding is no attack.
/datum/capability/weld_shut/interactions(atom/holder)
	. = list()
	for(var/stance in GLOB.cap_all_stances)
		var/datum/capability/entry/wrapper = lib_op("Weld shut", GLOBAL_PROC_REF(cap_weld_toggle), OP_SHAPE_TOOL, using = tool_quality, key = "weld_shut:[stance]", kind = OP_STRUCTURAL, works_broken = TRUE, works_unpowered = TRUE, log = log, name_proc = GLOBAL_PROC_REF(cap_weld_name))
		var/datum/interaction/capability/E = adopt_entry(wrapper, id = "weld_shut:[tool_quality]:[stance]")
		// The handler plays the welder's sound itself, louder, as the old weld did.
		cap_entry_setup(E, stance = stance, applies = (stance == I_HELP && help_applies) ? help_applies : applies, tool_volume = 0)
		. += E

GLOBAL_LIST_INIT(cap_examine_welded, list("It has been welded shut."))

/datum/capability/weld_shut/examine(atom/holder, mob/user)
	if(is_welded(holder))
		return GLOB.cap_examine_welded
	return null

/datum/capability/weld_shut/draw(atom/holder, datum/look/look)
	draw_layer(look, when = is_welded(holder))

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

/// Pry with `tool`, while unpowered (or with a tool of `strong_tier`), unbolted and unwelded. type: a subtype with the
/// holder's own reason() / name_for() / force().
/proc/cap_pry(tool = TOOL_CROWBAR, strong_tier = 0, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log, type = /datum/capability/pry)
	var/datum/capability/pry/C = new type
	C.tool_quality = tool
	C.strong_tier = strong_tier
	cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)
	return C

/// One op per stance but harm, "pry:<stance>" (in harm the crowbar strikes instead): the refusals are needs (a tool's
/// click on a bolted door answers with why).
/datum/capability/pry/interactions(atom/holder)
	. = list()
	for(var/stance in list(I_HELP, I_DISARM, I_GRAB))
		var/datum/capability/entry/wrapper = lib_op("Force open or closed", GLOBAL_PROC_REF(cap_pry_force), OP_SHAPE_TOOL, using = tool_quality, key = "pry:[stance]", needs = GLOBAL_PROC_REF(cap_pry_reason), works_broken = TRUE, works_unpowered = TRUE, log = log, name_proc = GLOBAL_PROC_REF(cap_pry_name))
		var/datum/interaction/capability/E = adopt_entry(wrapper, id = "pry:[tool_quality]:[stance]")
		cap_entry_setup(E, stance = stance, tool_volume = 0)
		. += E

/// Why prying holder fails now (text), or TRUE. A holder with more to say declares a subtype.
/datum/capability/pry/proc/reason(atom/holder, mob/user, obj/item/held)
	if(is_welded(holder))
		return "it's welded shut"
	if(is_bolted(holder))
		return "its bolts prevent it from being forced"
	if(cap_of(holder, /datum/capability/powered) && holder.cap_powered())
		if(!strong_tier || !held || dq_tool_tier(held, tool_quality) < strong_tier)
			return "its motors resist your efforts to force it"
	return TRUE

/datum/capability/pry/proc/name_for(atom/holder, mob/user)
	return "Force open or closed"

/// Forces the holder: a door opens or closes; anything else does nothing unless a subtype says.
/datum/capability/pry/proc/force(atom/holder, mob/user, obj/item/held)
	var/obj/machinery/door/D = holder
	if(istype(D))
		if(D.density)
			D.open(TRUE)
		else
			D.close(TRUE)
	return TRUE

/// The pry op's requirement, (user, holder, held): its capability's reason().
/proc/cap_pry_reason(mob/user, atom/holder, obj/item/held)
	var/datum/capability/pry/C = cap_of(holder, /datum/capability/pry)
	return C ? C.reason(holder, user, held) : TRUE

/proc/cap_pry_name(atom/holder, mob/user)
	var/datum/capability/pry/C = cap_of(holder, /datum/capability/pry)
	return C ? C.name_for(holder, user) : "Force open or closed"

/// The pry op's handler: its capability's force().
/proc/cap_pry_force(atom/holder, mob/user, obj/item/held)
	var/datum/capability/pry/C = cap_of(holder, /datum/capability/pry)
	return C ? C.force(holder, user, held) : TRUE

// ============================================================================
// cap_emergency_access(): CAP_EMERGENCY_ACCESS. While engaged the door lets anyone through (a door's access
// check reads emergency_access_on()). Toggled by the door's controls. Look: part LOOK_EMERGENCY while engaged.

/datum/capability/emergency_access
	layer_name = LOOK_EMERGENCY

/// Emergency access. Draws LOOK_EMERGENCY while engaged.
/proc/cap_emergency_access(needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/emergency_access/C = new
	cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)
	return C

/proc/emergency_access_on(atom/A)
	return !!(A.cap_state & CAP_EMERGENCY_ACCESS)

/proc/set_emergency_access(atom/A, on)
	return cap_set(A, CAP_EMERGENCY_ACCESS, on)

GLOBAL_LIST_INIT(cap_examine_emergency, list("Its emergency access mode is engaged."))

/datum/capability/emergency_access/examine(atom/holder, mob/user)
	if(emergency_access_on(holder))
		return GLOB.cap_examine_emergency
	return null

/datum/capability/emergency_access/draw(atom/holder, datum/look/look)
	draw_layer(look, when = emergency_access_on(holder))

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

/// A door that crushes what it closes on, for `damage` (the type default). type: a subtype with the holder's safeties_on().
/proc/cap_crush(damage = DOOR_CRUSH_DAMAGE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log, type = /datum/capability/crush)
	var/datum/capability/crush/C = new type
	C.damage = damage
	cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)
	return C

/// Crushes everything in holder's tiles for `amount` (null: this capability's damage). TRUE when
/// anything was crushed; the holder takes the damage once per crushed thing.
/datum/capability/crush/proc/crush(atom/movable/holder, amount)
	var/dealt = isnull(amount) ? damage : amount
	. = FALSE
	for(var/turf/T in holder.locs)
		for(var/atom/movable/AM in contents_of(T))
			if(AM.airlock_crush(dealt))
				holder.take_damage(dealt, BRUTE, MELEE)
				. = TRUE

/datum/capability/crush/ui_data(atom/holder, mob/user, list/data)
	data["safe"] = safeties_on(holder)

/// Whether the holder's safeties stop it closing on someone.
/datum/capability/crush/proc/safeties_on(atom/holder)
	return TRUE

/// Whether A's safeties stop it closing on someone (its cap_crush(); TRUE without one).
/proc/door_safeties_on(atom/A)
	var/datum/capability/crush/C = cap_of(A, /datum/capability/crush)
	return C ? C.safeties_on(A) : TRUE

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
// Named args pick the variations; `without()` / `replace()` edit the result like any list. `subtypes`: base capability
// type -> the holder's subtype implementing its holder interface (list(/datum/capability/bolts = /datum/capability/bolts/airlock)).
/proc/door(wires, electrify = FALSE, ai_control = FALSE, panel_tool = TOOL_SCREWDRIVER, repair_tool = null, emag_effect, emag_mode = EMAG_REPEATABLE, emag_log = LOG_GAME, weld_applies, weld_help_applies, pry_strong_tier = 0, crush_damage = DOOR_CRUSH_DAMAGE, close_wait = 15 SECONDS, list/subtypes)
	var/list/K = subtypes || list()
	. = list(cap_panel(tool = panel_tool, type = K[/datum/capability/panel] || /datum/capability/panel))
	if(wires)
		. += cap_wires(wires, type = K[/datum/capability/wires] || /datum/capability/wires)
	. += cap_door_access()
	. += cap_breakable(repair_tool = repair_tool)
	. += cap_power()
	. += cap_emag(effect = emag_effect, mode = emag_mode, log = emag_log)
	. += cap_bolts(type = K[/datum/capability/bolts] || /datum/capability/bolts)
	if(electrify)
		. += cap_electrify(type = K[/datum/capability/electrify] || /datum/capability/electrify)
	. += cap_weld_shut(applies = weld_applies, help_applies = weld_help_applies)
	. += cap_pry(strong_tier = pry_strong_tier, type = K[/datum/capability/pry] || /datum/capability/pry)
	. += cap_emergency_access()
	. += cap_crush(damage = crush_damage, type = K[/datum/capability/crush] || /datum/capability/crush)
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

/// The AiAirlock actions that are logged (read through ui_logged()).
TYPE_TABLE(/datum/capability/ai_control, ui_logged_actions, list(
	"shock_temp" = LOG_GAME,
	"shock_perm" = LOG_GAME,
	"bolt_toggle" = LOG_GAME,
	"emergency_toggle" = LOG_GAME,
))

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
