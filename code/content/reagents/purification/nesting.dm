// A bath: a small glass container stood inside a larger open one (a large beaker, a bucket, a basin), and the ice and water that make it a bath
// (code/domains/world_model/reagents/freezing.dm).
//
// The outer container holds one inner container, and only a smaller one (a smaller volume, open, not itself in a bath and holding none). Clicking the outer container with
// the inner one in hand in a grab stance stands it in the bath ("Stand it in the bath"); in any other stance the click is a pour, as it is for any container, and a
// pour into a bath goes into the outer container's liquid, never the inner. The inner container comes out again from the outer one's menu.
//
// Heat goes through the heat system both ways. Both containers get a kept heat body; the inner one's body is coupled to the outer one's at NEST_CONDUCTANCE W/K
// (code/domains/heat/heat.dm: a thing inside a body-holder couples to its body), and the outer one is coupled to what it stands on or in as any container is, so a bath
// of ice cools its inner container to 0 C and warms back to the room as the ice goes, a bath on a hot plate heats its inner container, and the inner container's own
// reactions follow its own temperature (code/content/reagents/reagent_containers/reaction_watch.dm) however it got there. Every nesting is written to the world log under
// GLOB.chem_trace.

/obj/item/reagent_containers/glass
	/// The smaller glass container standing in this one (a bath), or null. It is in this container's contents and its heat body is coupled to this one's.
	var/obj/item/reagent_containers/glass/nested

/// What a glass container takes as a bath: a smaller container stood in it, and given back.
CAPABILITY_DEF(glass_nesting, CAP_GLASS_NESTING, key = NONE)

/datum/capability/def/glass_nesting/entries()
	return list(
		// Above the pour (the held container's own op at OP_PRIORITY_PART) but only in a grab stance, so a click in any other stance is still a pour.
		op("nest_container", item(/obj/item/reagent_containers/glass), stance(I_GRAB), priority(OP_PRIORITY_PART + 1), when(TYPE_PROC_REF(/obj/item/reagent_containers/glass, nest_fits)), label("Stand it in the bath"), \
			then(TYPE_PROC_REF(/obj/item/reagent_containers/glass, nest_added))),
		op("remove_nested", menu(), when(req_actor_kind(/mob/living)), label("Take the inner container out"), \
			needs(req_capable(), req(TYPE_PROC_REF(/obj/item/reagent_containers/glass, nest_present), silent = TRUE)), then(TYPE_PROC_REF(/obj/item/reagent_containers/glass, nest_removed))),
		every(2 SECONDS, then(TYPE_PROC_REF(/obj/item/reagent_containers/glass, phase_ticked)), when = TYPE_PROC_REF(/obj/item/reagent_containers/glass, phase_pending)))

/// Why `inner` cannot stand in this container, or null when it can: this one is open, holds no inner container and is not in a bath itself, and `inner` is a smaller
/// container of its own, in no bath and holding none.
/obj/item/reagent_containers/glass/proc/nest_refusal(obj/item/reagent_containers/glass/inner)
	if(!istype(inner) || inner == src || QDELETED(inner))
		return "it is not a container"
	if(!is_open_container())
		return "it is closed"
	if(nested)
		return "there is a container in it already"
	if(bath_of())
		return "it stands in a bath itself"
	if(inner.nested || inner.bath_of())
		return "the other is part of a bath"
	if(inner.volume >= volume)
		return "it is not smaller"
	return null

/// The held container can be stood in this one.
/obj/item/reagent_containers/glass/proc/nest_fits(datum/act/op/A)
	return isnull(nest_refusal(A.held))

/// There is an inner container to take out.
/obj/item/reagent_containers/glass/proc/nest_present(datum/act/op/A)
	return nested ? null : /datum/msg/req_failed

/// The container this one stands in as the inner container of a bath, or null.
/obj/item/reagent_containers/glass/proc/bath_of()
	RETURN_TYPE(/obj/item/reagent_containers/glass)
	var/obj/item/reagent_containers/glass/outer = loc
	return istype(outer) && outer.nested == src ? outer : null

/// An inner container couples to its bath through the glass; any other container has the conductance its size gives it.
/obj/item/reagent_containers/glass/thermal_properties()
	. = ..()
	if(bath_of())
		.[THERMAL_CONDUCTANCE] = NEST_CONDUCTANCE

/obj/item/reagent_containers/glass/proc/nest_added(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/glass/inner = A.held
	var/inner_temperature = inner.get_temperature()
	if(!move_into(src, nameof(src.nested), inner, user))
		return OP_OK
	nest_couple(inner_temperature)
	to_chat(user, span_notice("You stand \the [inner] in \the [src]."))
	if(GLOB.chem_trace)
		log_world("CHEM: [user] stood [inner] ([inner.reagents?.get_reagents()]) at [round(inner.get_temperature() - T0C, 0.1)] C in the bath [src] ([reagents?.get_reagents()]) at [round(get_temperature() - T0C, 0.1)] C")
	return OP_OK

/// Both containers get a kept heat body and the inner one's is coupled to the bath's: heat goes between them through the heat system from now on.
/// `inner_temperature` is the inner container's temperature before it went in: its body starts there, not at the bath's (a body made inside the bath would start at the bath's).
/obj/item/reagent_containers/glass/proc/nest_couple(inner_temperature)
	if(!nested)
		return
	for(var/obj/item/reagent_containers/glass/C in list(src, nested))
		C.create_heat_body(TRUE, C == nested ? inner_temperature : null)
		if(!isnull(C.heat_body))
			heat_body_keep(C.heat_body, TRUE) // a body at rest settles away, and a bath's must not while it holds another body
	nested.heat_recouple() // its body (if it had one already) was coupled to the room before the bath had a body of its own, and with the conductance of a bare container

/obj/item/reagent_containers/glass/proc/nest_removed(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/glass/inner = nested
	if(!inner)
		return OP_OK
	inner.forceMove(get_turf(src))
	rel_take(src, nameof(nested))
	for(var/obj/item/reagent_containers/glass/C in list(src, inner))
		if(!isnull(C.heat_body))
			heat_body_keep(C.heat_body, FALSE)
	inner.heat_recouple() // it left the bath: its conductance is its own again
	user.put_in_hands(inner)
	to_chat(user, span_notice("You take \the [inner] out of \the [src]."))
	if(GLOB.chem_trace)
		log_world("CHEM: [user] took [inner] at [round(inner.get_temperature() - T0C, 0.1)] C out of the bath [src] at [round(get_temperature() - T0C, 0.1)] C")
	return OP_OK

/// The timer's gate: there is ice that may melt, or water that a cold container may freeze.
/obj/item/reagent_containers/glass/proc/phase_pending(datum/act/A)
	return reagents && (reagents.reagent_by_id[REAGENT_ID_ICE] || (!isnull(heat_body) && reagents.reagent_by_id[REAGENT_ID_WATER]))

/// A bath goes on melting or freezing with nobody touching it.
/obj/item/reagent_containers/glass/proc/phase_ticked(datum/act/timer/A)
	if(reagents?.phase_step())
		reagents.handle_reactions()

/// What an inner container standing in this one reads, for examine.
/obj/item/reagent_containers/glass/proc/nest_examine_lines()
	. = list()
	if(nested)
		. += span_notice("\A [nested] stands in it, at [round(nested.get_temperature() - T0C, 0.1)] C against the bath's [round(get_temperature() - T0C, 0.1)] C.")
	var/obj/item/reagent_containers/glass/outer = bath_of()
	if(outer)
		. += span_notice("It stands in \the [outer], at [round(outer.get_temperature() - T0C, 0.1)] C.")
