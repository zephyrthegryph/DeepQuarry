// The condenser: a table-top cooling coil that catches the vapour boiling off a heated container (code/domains/world_model/reagents/boiling.dm) and runs it into a
// second container, instead of letting it be deleted: real distillation. It works for a hot plate (code/content/reagents/machinery/hot_plate.dm) standing on its
// own tile or any tile next to it, and only while it has power and a container to collect into. What does not fit in that container is lost. The distillate has the
// purity of what boiled: a contaminant with a boiling point under the plate's temperature comes over with it, one that never boils stays behind in the flask.

/obj/machinery/chem_condenser
	name = "condenser"
	desc = "A glass cooling coil with a pump. Stand it next to a hot plate with a container under its spout, and the vapour boiling off the plate is collected there."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "alembic"
	density = FALSE
	anchored = FALSE
	layer = ABOVE_WINDOW_LAYER
	use_power = USE_POWER_IDLE
	circuit = VARIANT(/obj/item/circuitboard/chem_condenser)
	/// The container under the spout.
	var/obj/item/reagent_containers/glass/held_container

CAPABILITIES(/obj/machinery/chem_condenser)
	tabletop(carry = TRUE)
	configure(machine_rules(maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE))
	configure(movable_motion(unacidable = TRUE))
	configure(uses_power(idle = 10))
	owns_one(nameof(held_container), /obj/item/reagent_containers/glass)
	default_parts()
	op("place_container", item(/obj/item/reagent_containers/glass), label("Stand it under the spout"), needs(req(PROC_REF(spout_free))), then(PROC_REF(container_placed)))
	op("remove_container", hand(), label("Take the container from the spout"), needs(req(PROC_REF(container_present), silent = TRUE)), then(PROC_REF(container_removed)))

MSG_DEF_SELF(condenser/occupied, "There is a container under the spout already.")

/obj/machinery/chem_condenser/proc/spout_free(datum/act/op/A)
	return held_container ? MSG(condenser/occupied) : null

/obj/machinery/chem_condenser/proc/container_present(datum/act/op/A)
	return held_container ? null : /datum/msg/req_failed

/obj/machinery/chem_condenser/proc/container_placed(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/glass/C = A.held
	if(!move_into(src, nameof(src.held_container), C, user))
		return OP_OK
	to_chat(user, span_notice("You stand \the [C] under the spout of \the [src]."))
	return OP_OK

/obj/machinery/chem_condenser/proc/container_removed(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/glass/C = held_container
	if(!C)
		return OP_OK
	C.forceMove(get_turf(src))
	rel_take(src, nameof(held_container))
	user.put_in_hands(C)
	to_chat(user, span_notice("You take \the [C] from \the [src]."))
	return OP_OK

/// Takes boiled-off vapour (boil_step()'s list) into the container under the spout. TRUE when the condenser took part of it; it takes none without power or a container.
/obj/machinery/chem_condenser/proc/collect(list/vapour)
	var/obj/item/reagent_containers/glass/C = held_container
	if(!C || !operable())
		return FALSE
	var/taken = C.reagents.condense(vapour)
	if(GLOB.chem_trace)
		log_world("CHEM: [src] collected [round(taken, 0.001)]u of vapour into [C]")
	return taken > 0

/obj/machinery/chem_condenser/examine(mob/user)
	. = ..()
	if(held_container)
		. += span_notice("\A [held_container] stands under the spout, holding [round(held_container.reagents.total_volume, 0.1)] units.")

/// The coil, and the container under the spout.
/obj/machinery/chem_condenser/draw(datum/look/look)
	..()
	look.state("alembic")
	if(held_container)
		look.watch(held_container)
		look.watch(held_container.reagents)
		look.overlay(image("icon" = held_container))
