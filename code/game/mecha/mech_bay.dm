/obj/machinery/mech_recharger
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "mech recharger"
	desc = "A mech recharger, built into the floor."
	icon = 'icons/mecha/mech_bay.dmi'
	icon_state = "recharge_floor"
	density = FALSE
	anchored = TRUE
	layer = TURF_LAYER + 0.1
	circuit = /obj/item/circuitboard/mech_recharger

	var/charge = 45
	var/repair = 0
	var/static/list/chargable_types = list(
		/obj/mecha,
		/mob/living/silicon/robot/platform
	)
/// What stands on the pad being charged (a relation view). A field: charging runs while it is set.
OM_FIELD_VIEW(/obj/machinery/mech_recharger, atom/movable, charging, CHANGE_MACHINE_OCCUPANT)
/obj/machinery/mech_recharger/alien
	icon = 'icons/turf/shuttle_alien_blue.dmi'

/obj/machinery/mech_recharger/Crossed(atom/movable/M)
	. = ..()
	if(charging() == M)
		return
	for(var/mtype in chargable_types)
		if(istype(M, mtype))
			start_charging(M)
			return

/obj/machinery/mech_recharger/Uncrossed(atom/movable/M)
	. = ..()
	if(M == charging())
		rel_clear(src, nameof(charging))

/obj/machinery/mech_recharger/RefreshParts()
	..()
	charge = 0
	repair = -5
	charge += get_part_rating(/obj/item/stock_parts/capacitor) * 20
	charge += get_part_rating(/obj/item/stock_parts/scanning_module) * 5
	repair += get_part_rating(/obj/item/stock_parts/scanning_module)
	repair += get_part_rating(/obj/item/stock_parts/manipulator) * 2

// Its periodic work: work_step() while it is started (code/library/machine/started_work.dm).
CAPABILITIES(/obj/machinery/mech_recharger)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(charging), gate = PROC_REF(operable), wakes_on = list(nameof(charging), nameof(stat)))
	op("part_replacement", item(/obj/item/storage/part_replacer), priority(OP_PRIORITY_DEFAULT - 1), label("Replace parts"), then(TYPE_PROC_REF(/obj/machinery, op_part_replacement)))
	default_parts()

/obj/machinery/mech_recharger/proc/work_step(datum/act/timer/A)
	if(!charging() || charging().loc != src.loc) // Could be qdel or teleport or something
		rel_clear(src, nameof(charging))
		return

	var/done = FALSE
	var/obj/mecha/mech = charging()
	var/obj/item/cell/cell = charging().get_cell()
	if(cell)
		var/t = min(charge, cell.maxcharge - cell.charge)
		if(t > 0)
			if(istype(mech))
				mech.give_power(t)
			else
				cell.give(t)
			use_power(t * 150)
		else
			if(istype(mech))
				mech.occupant_message(span_notice("Fully charged."))
			done = TRUE

	if(repair && istype(mech) && mech.get_integrity() < mech.max_integrity)
		mech.repair_damage(min(repair, mech.max_integrity - mech.get_integrity()))
		if(mech.get_integrity() >= mech.max_integrity)
			mech.occupant_message(span_notice("Fully repaired."))
		else
			done = FALSE
	if(done)
		rel_clear(src, nameof(charging))

/obj/machinery/mech_recharger/proc/start_charging(atom/movable/M)

	var/obj/mecha/mech = M
	if(!operable())
		if(istype(mech))
			mech.occupant_message(span_warning("Power port not responding. Terminating."))
		else
			to_chat(M, span_warning("Power port not responding. Terminating."))
		return
	if(M.get_cell())
		if(istype(mech))
			mech.occupant_message(span_notice("Now charging..."))
		else
			to_chat(M, span_notice("Now charging..."))
		rel_set(src, nameof(charging), M)
	return

/// charging (a relation view: it reads null once the target is deleted).
/obj/machinery/mech_recharger/proc/charging() as /atom/movable
	return charging
