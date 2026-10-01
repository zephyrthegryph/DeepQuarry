// The reagent container capability (doc/rewrite/dx_conventions.md §2): a holder with a reagent
// holder of its own (/datum/reagents), a lid, a transfer amount, and pouring, filling and
// splashing between containers.
//
//	/obj/item/flask/capabilities()
//		. = ..()
//		. += cap_reagent_container(volume = 60, transfer_amounts = list(5, 10, 30), lid = TRUE)
//
// State: CAP_LID_OPEN (open for reagents; is_open_container() reads it). A lidded container
// (lid = TRUE) starts as its type's cap_state says and offers Open lid / Close lid; a lidless
// one is opened at init and stays open. The transfer amount lives in the capability data
// (/datum/cap_reagent_data), defaulting to the first of transfer_amounts.
//
// Entries, all on the holder (the resolver offers target-side entries only):
//   Open lid / Close lid     empty hand, when lid.
//   Set transfer amount      a form choosing one of transfer_amounts (or, with cycle_transfer, the
//                            next amount without asking), when there is more than one.
//   Pour in                  a held open container with reagents pours into the holder (fillable).
//   Fill from                a held open container fills from the holder (pourable), when the holder
//                            takes no pouring or the held container is empty.
//   Splash                   with combat mode on (help intent off), a held open splashable container
//                            is splashed over the holder instead of poured.
// Held-side API for any target: A.cap_reagent_splash_onto(user, target) splashes A's contents.
// Examine: the volume and a closed lid. Look: gauge "fill" (0..4 by total/maximum volume) and
// overlay LOOK_LID while a lid is on. The reagents mark the holder changed (holder.dm update_total()).

/datum/capability/reagent_container
	layer_name = LOOK_LID
	data_type = /datum/cap_reagent_data
	/// The reagent holder's volume, made at init when the holder has none.
	var/volume = 30
	/// The amounts a user can pick; the first is the default.
	var/list/transfer_amounts
	/// Has a lid that opens and closes (else always open).
	var/lid = FALSE
	/// Other containers can fill from it.
	var/pourable = TRUE
	/// Other containers can pour into it.
	var/fillable = TRUE
	/// Its contents can be splashed.
	var/splashable = TRUE
	/// Set transfer amount steps to the next amount instead of asking.
	var/cycle_transfer = FALSE
	/// Look gauge steps.
	var/fill_levels = 4

/// Per-instance reagent container state.
/datum/cap_reagent_data
	/// The chosen transfer amount, or null for the capability's default.
	var/transfer_amount

/**
 * The reagent container capability. volume: the holder's reagent volume; transfer_amounts: the
 * choices (first is the default); lid: has a lid; pourable / fillable / splashable: what other
 * containers can do with it; cycle_transfer: Set transfer amount steps instead of asking.
 */
/proc/cap_reagent_container(volume = 30, list/transfer_amounts = list(5, 10, 15, 30), lid = FALSE, pourable = TRUE, fillable = TRUE, splashable = TRUE, cycle_transfer = FALSE, fill_levels = 4, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/reagent_container/C = new
	C.volume = volume
	C.transfer_amounts = transfer_amounts
	C.lid = lid
	C.pourable = pourable
	C.fillable = fillable
	C.splashable = splashable
	C.cycle_transfer = cycle_transfer
	C.fill_levels = fill_levels
	return cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/datum/capability/reagent_container/on_holder_init(atom/holder, mapload)
	if(!holder.reagents)
		holder.create_reagents(volume)
	if(!lid)
		cap_set(holder, CAP_LID_OPEN, TRUE) // lidless: always open

/**
 * Ops: "toggle_lid" (an empty hand, when lidded), "set_transfer_amount" (ACT_NONE: a setting, chosen from the Menu,
 * radial or command bar), and with a held container (anything else in hand is not meant, so the click falls through):
 * "pour_in" (priority 5), "splash" (the hostile ACT_ATTACK in harm) and "fill_from" (priority 4; not meant where Pour in
 * applies). A container that can't give or take now (closed, empty, full) refuses.
 */
/datum/capability/reagent_container/interactions(atom/holder)
	. = list()
	if(lid)
		. += adopt_entry(lib_op("Open lid", TYPE_PROC_REF(/atom, cap_reagent_toggle_lid), OP_SHAPE_HAND, key = "toggle_lid", works_broken = TRUE, works_unpowered = TRUE, name_proc = TYPE_PROC_REF(/atom, cap_reagent_lid_name)), id = "reagents:lid", empty_handed = TRUE, pass_cap = TRUE)
	if(length(transfer_amounts) > 1)
		var/list/form = cycle_transfer ? null : list(choice_field("amount", TYPE_PROC_REF(/atom, cap_reagent_amount_choices), message = "Amount per transfer:"))
		. += adopt_entry(lib_op("Set transfer amount", TYPE_PROC_REF(/atom, cap_reagent_set_amount), OP_SHAPE_HAND, key = "set_transfer_amount", action = ACT_NONE, works_broken = TRUE, works_unpowered = TRUE, form = form), id = "reagents:amount", category = INTERACTION_CAT_CONFIGURE, empty_handed = TRUE, pass_cap = TRUE)
	var/datum/req/held_container = req_proc(TYPE_PROC_REF(/atom, cap_reagent_held_container))
	if(fillable)
		. += adopt_entry(lib_op("Pour in", TYPE_PROC_REF(/atom, cap_reagent_pour_in), OP_SHAPE_USE_ON, using = /obj/item, key = "pour_in", offered = held_container, needs = TYPE_PROC_REF(/atom, cap_reagent_pour_in_reason), works_broken = TRUE, works_unpowered = TRUE, priority = 5), id = "reagents:pour_in", pass_cap = TRUE)
	. += adopt_entry(lib_op("Splash", TYPE_PROC_REF(/atom, cap_reagent_splash_on), OP_SHAPE_USE_ON, using = /obj/item, key = "splash", action = ACT_ATTACK, offered = held_container, needs = TYPE_PROC_REF(/atom, cap_reagent_splash_reason), works_broken = TRUE, works_unpowered = TRUE, log = LOG_GAME, priority = 5, stance = I_HURT), id = "reagents:splash:[I_HURT]", pass_cap = TRUE)
	if(pourable)
		. += adopt_entry(lib_op("Fill from", TYPE_PROC_REF(/atom, cap_reagent_fill_from), OP_SHAPE_USE_ON, using = /obj/item, key = "fill_from", offered = list(held_container, req_proc(TYPE_PROC_REF(/atom, cap_reagent_fill_from_meant))), needs = TYPE_PROC_REF(/atom, cap_reagent_fill_from_reason), works_broken = TRUE, works_unpowered = TRUE, priority = 4), id = "reagents:fill_from", pass_cap = TRUE)

/datum/capability/reagent_container/examine(atom/holder, mob/user)
	. = list()
	var/datum/reagents/R = holder.reagents
	if(R)
		. += R.total_volume ? "It contains [R.total_volume] of [R.maximum_volume] units." : "It is empty. It holds [R.maximum_volume] units."
	if(lid && !(holder.cap_state & CAP_LID_OPEN))
		. += "Its lid is closed."

/datum/capability/reagent_container/draw(atom/holder, datum/look/look)
	var/datum/reagents/R = holder.reagents
	if(R && R.maximum_volume)
		look.gauge("fill", level = R.total_volume / R.maximum_volume, levels = fill_levels)
	draw_layer(look, when = lid && !(holder.cap_state & CAP_LID_OPEN))

/datum/capability/reagent_container/ui_data(atom/holder, mob/user, list/data)
	data["reagent_volume"] = holder.reagents?.total_volume || 0
	data["reagent_max_volume"] = holder.reagents?.maximum_volume || 0
	data["lid_open"] = !!(holder.cap_state & CAP_LID_OPEN)
	data["transfer_amount"] = transfer_for(holder)

/// The holder's transfer amount now.
/datum/capability/reagent_container/proc/transfer_for(atom/holder)
	var/datum/cap_reagent_data/D = holder.cap_data?[key]
	if(D?.transfer_amount)
		return D.transfer_amount
	return length(transfer_amounts) ? transfer_amounts[1] : 5

// ---- helpers any container answers (a capability holder or a legacy container) ----

/// How much A moves per transfer.
/proc/reagent_transfer_amount(atom/A)
	var/datum/capability/reagent_container/C = cap_of(A, /datum/capability/reagent_container)
	if(C)
		return C.transfer_for(A)
	if(istype(A, /obj/item/reagent_containers))
		var/obj/item/reagent_containers/legacy = A
		return legacy.amount_per_transfer_from_this
	return 5

/// Whether A's contents can be splashed: its capability says, and legacy open containers can.
/proc/reagent_splashable(atom/A)
	var/datum/capability/reagent_container/C = cap_of(A, /datum/capability/reagent_container)
	if(C)
		return C.splashable
	return istype(A, /obj/item/reagent_containers)

/// Why `from` can't give reagents right now, or null.
/proc/reagent_source_reason(atom/from)
	if(!from?.reagents)
		return "\the [from] can't hold reagents"
	if(!from.is_open_container())
		return "\the [from] is closed"
	if(!from.reagents.total_volume)
		return "\the [from] is empty"
	return null

/// Why `into` can't take reagents right now, or null.
/proc/reagent_sink_reason(atom/into)
	if(!into?.reagents)
		return "\the [into] can't hold reagents"
	if(!into.is_open_container())
		return "\the [into] is closed"
	if(!into.reagents.get_free_space())
		return "\the [into] is full"
	return null

// ---- entry handlers and needs (procs on the holder) ----

/atom/proc/cap_reagent_lid_name(mob/user)
	return (cap_state & CAP_LID_OPEN) ? "Close lid" : "Open lid"

/atom/proc/cap_reagent_toggle_lid(mob/user, datum/capability/reagent_container/cap)
	var/opening = !(cap_state & CAP_LID_OPEN)
	cap_set(src, CAP_LID_OPEN, opening)
	act_message(user, src, self = "You [opening ? "take the lid off" : "put the lid on"] %T%.", others = "%U% [opening ? "takes the lid off" : "puts the lid on"] %T%.")
	return TRUE

/atom/proc/cap_reagent_amount_choices(mob/user)
	var/datum/capability/reagent_container/C = cap_of(src, /datum/capability/reagent_container)
	. = list()
	for(var/amount in C?.transfer_amounts)
		. += "[amount]"

/// amount: the choice from the form (text), or null to step to the next amount (cycle_transfer).
/atom/proc/cap_reagent_set_amount(mob/user, amount, datum/capability/reagent_container/cap)
	var/datum/capability/reagent_container/C = cap
	if(!C)
		return FALSE
	var/list/amounts = C.transfer_amounts
	var/chosen
	if(isnull(amount))
		var/at = amounts.Find(C.transfer_for(src))
		chosen = amounts[(at % length(amounts)) + 1]
	else
		chosen = text2num(amount)
		if(!(chosen in amounts))
			return refuse(user, "That isn't an amount \the [src] can pour.")
	var/datum/cap_reagent_data/D = cap_data(src, C)
	D.transfer_amount = chosen
	to_chat(user, span_notice("\The [src] now transfers [chosen] unit\s at a time."))
	return TRUE

/// offered: the held item is a reagent container at all (anything else in hand is not meant: the click falls through).
/atom/proc/cap_reagent_held_container(mob/user, obj/item/held)
	return held?.reagents ? TRUE : "\the [held] can't hold reagents"

/// offered: Fill from is not meant where Pour in applies (a holder that takes pouring, a held container with something in it).
/atom/proc/cap_reagent_fill_from_meant(mob/user, obj/item/held)
	var/datum/capability/reagent_container/C = cap_of(src, /datum/capability/reagent_container)
	return (C?.fillable && held?.reagents?.total_volume) ? FALSE : TRUE

/atom/proc/cap_reagent_pour_in_reason(mob/user, obj/item/held)
	if(!held)
		return FALSE
	return reagent_source_reason(held) || reagent_sink_reason(src) || TRUE

/atom/proc/cap_reagent_pour_in(mob/user, obj/item/held, datum/capability/reagent_container/cap)
	var/moved = held.reagents.trans_to_holder(reagents, reagent_transfer_amount(held))
	if(!moved)
		return refuse(user, "Nothing pours out of \the [held].")
	act_message(user, src, self = "You pour [moved] unit\s from %I% into %T%.", others = "%U% pours something from %I% into %T%.", item = held)
	return TRUE

/atom/proc/cap_reagent_fill_from_reason(mob/user, obj/item/held)
	if(!held)
		return FALSE
	var/datum/capability/reagent_container/C = cap_of(src, /datum/capability/reagent_container)
	// Something that takes pouring is poured into, unless the held container has nothing to pour.
	if(C?.fillable && held.reagents?.total_volume)
		return FALSE
	return reagent_source_reason(src) || reagent_sink_reason(held) || TRUE

/atom/proc/cap_reagent_fill_from(mob/user, obj/item/held, datum/capability/reagent_container/cap)
	var/moved = reagents.trans_to_holder(held.reagents, reagent_transfer_amount(src))
	if(!moved)
		return refuse(user, "Nothing flows out of \the [src].")
	act_message(user, src, self = "You fill %I% with [moved] unit\s from %T%.", others = "%U% fills %I% from %T%.", item = held)
	return TRUE

/atom/proc/cap_reagent_splash_reason(mob/user, obj/item/held)
	if(!held)
		return FALSE
	if(!reagent_splashable(held))
		return "\the [held] can't be splashed"
	return reagent_source_reason(held) || TRUE

/atom/proc/cap_reagent_splash_on(mob/user, obj/item/held, datum/capability/reagent_container/cap)
	if(!held.cap_reagent_splash_onto(user, src))
		return refuse(user, "Nothing splashes out of \the [held].")
	return TRUE

/// Splashes everything in this container over `target` (anything: a mob, a turf, a container).
/// Held-side API for the throw and attack paths. TRUE when something splashed.
/atom/proc/cap_reagent_splash_onto(mob/user, atom/target)
	if(!target || !reagent_splashable(src) || reagent_source_reason(src))
		return FALSE
	var/amount = reagents.total_volume
	var/list/contained = reagents.get_reagents()
	reagents.splash(target, amount)
	if(ismob(target))
		add_attack_logs(user, target, "Splashed with [name] containing [contained]")
	act_message(user, target, self = "You splash the contents of %I% onto %T%.", others = "%U% splashes something onto %T%!", item = src)
	changed(src)
	return TRUE
