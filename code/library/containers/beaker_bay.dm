// beaker_bay(slot_var, accepts =, fits =, at =, eject_button =, exit_to =) (doc/rewrite/final_api.html, section 11 "Containers and slots"; the
// container sibling of cell_bay()): a one-container slot over a holder var, a sleeper's dialysis beaker or a cryo cell's drip.
//
//   CAPABILITIES(/obj/machinery/sleeper)
//       owns_one(nameof(beaker), /obj/item/reagent_containers/glass, starts = /obj/item/reagent_containers/glass/beaker/large, on_destroy = ON_DESTROY_SPILL)
//       beaker_bay(nameof(beaker), eject_button = "removebeaker")
//   CAPABILITIES(/obj/machinery/atmospherics/unary/cryo_cell)
//       owns_one(nameof(beaker), /obj/item/reagent_containers/glass, on_destroy = ON_DESTROY_SPILL)
//       beaker_bay(nameof(beaker), eject_button = "ejectBeaker", exit_to = SOUTH)
//
// The ops, keyed beaker_bay.<var>.<name>:
//   insert   a container of `accepts` in hand goes in (when it `fits`: a requirement, size_is(ITEMSIZE_SMALL)); a full bay refuses it ("There is already
//            something in there.") and it stays in hand. Placed at(at) when given, so a closed door sets it aside.
//   eject    the window button `eject_button` (its old action name, so the window does not change) puts the container out: onto the tile toward
//            `exit_to` when nothing blocks it, else onto the holder's own tile. No button: no eject op.
// The var is the holder's owns_one(): its starting container (starts =) and what happens to it when the holder goes are said there, as cell_bay()'s are.

MSG_DEF(beaker_bay/inserted, "You add %I% to %T%.", "%U% adds %I% to %T%.")
MSG_DEF(beaker_bay/ejected, "You take the container out of %T%.", "%U% takes the container out of %T%.")
MSG_DEF_SELF(beaker_bay/empty, "There is nothing in it.")

CAPABILITY_TYPE(beaker_bay, CAP_BEAKER_BAY, /datum/capability/lib/beaker_bay, key = slot_var, slot_var = null, accepts = /obj/item/reagent_containers/glass, fits = null, at = null, eject_button = null, exit_to = null)

/datum/capability/lib/beaker_bay

/datum/capability/lib/beaker_bay/entries()
	var/list/at_space = list()
	if(!isnull(at))
		at_space += global.at(at)
	var/list/entries = list(
		op("insert", item(accepts), label("Insert"), put_in(slot_var), at_space, fits ? needs(fits) : null, says(MSG(beaker_bay/inserted)), logs(LOG_GAME)))
	if(eject_button)
		entries += op("eject", ui_act(eject_button), needs(req_full(slot_var, because = MSG(beaker_bay/empty))), then(CAP_PROC(eject_op)), says(MSG(beaker_bay/ejected)))
	return entries

/datum/capability/lib/beaker_bay/proc/eject_op(datum/act/op/A)
	var/atom/holder = A.holder
	if(!beaker_bay_eject(holder, slot_var))
		return OP_FAILED
	holder.add_fingerprint(A.actor)
	return OP_OK

/// Puts what the bay `slot_var` of `holder` holds out, onto the tile toward its exit_to when nothing blocks it, else the holder's own. The container,
/// or null when the bay was empty.
/proc/beaker_bay_eject(atom/holder, slot_var)
	var/datum/capability/lib/beaker_bay/bay = cap_of(holder, CAP_BEAKER_BAY, slot_var)
	var/atom/movable/thing = holder.vars[slot_var]
	if(!istype(thing))
		return null
	var/turf/here = get_turf(holder)
	var/turf/out = here
	if(bay && !isnull(bay.exit_to) && here)
		var/turf/beside = get_step(here, bay.exit_to)
		if(beside && !is_blocked_turf(beside))
			out = beside
	varslot_set(holder, slot_var, null)
	thing.forceMove(out)
	return thing
