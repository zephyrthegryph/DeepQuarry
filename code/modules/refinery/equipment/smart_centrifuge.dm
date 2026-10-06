/obj/machinery/smart_centrifuge
	name = "smart centrifuge"
	desc = "Isolates various compounds and stores them in chemical cartridges."
	icon = 'icons/obj/hydroponics_machines.dmi'
	icon_state = "sextractor"
	density = TRUE
	anchored = TRUE
	circuit = /obj/item/circuitboard/smart_centrifuge
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	maintenance_wrench_time = 2 SECONDS

	/// Delay before the next separation step: the spin-up, then one bottle a second.
	var/separate_delay = 10 SECONDS
	/// The current run's output choice (spin_reagents()).
	var/separate_force_bottle = FALSE
	var/separate_force_canister = FALSE

CAPABILITIES(/obj/machinery/smart_centrifuge)
	reagents(CARGOTANKER_VOLUME)
OM_FIELD(/obj/machinery/smart_centrifuge, working, FALSE, CHANGE_MACHINE_SETTINGS)
DECLARE_REPEAT(/obj/machinery/smart_centrifuge, "separate_delay", internal_reagent_seperate, "working")

/obj/machinery/smart_centrifuge/Initialize(mapload)
	. = ..()
	flags |= OPENCONTAINER
	default_apply_parts()

/obj/machinery/smart_centrifuge/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/centrifuge_attackby,
		/datum/interaction/machine_hand/ungated/centrifuge_use,
		/datum/interaction/machine_verb/centrifuge_isolate_reagents,
		/datum/interaction/machine_verb/centrifuge_isolate_reagents_bottle,
		/datum/interaction/machine_verb/centrifuge_isolate_reagents_canisters,
		/datum/interaction/machine_drag/centrifuge_drain_tank,
	)
	..()

/// Old attackby: while working, refuses; else falls through to ..().
/datum/interaction/machine_item/centrifuge_attackby
	id = "centrifuge_attackby"
	name = "Use"
	held_type = /obj/item
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/smart_centrifuge/proc/is_working, null))
	effect = /obj/machinery/smart_centrifuge/proc/interaction_attackby

/// No side effects.
/obj/machinery/smart_centrifuge/proc/is_working(mob/actor, atom/target, obj/item/held)
	return working

/obj/machinery/smart_centrifuge/proc/interaction_attackby(mob/user, obj/item/O, datum/interaction/interaction)
	to_chat(user, "<span class='notice'>\The [src] is still spinning.</span>")
	return TRUE

/// Old attack_hand: never called ..().
/datum/interaction/machine_hand/ungated/centrifuge_use
	id = "centrifuge_use"
	name = "Use"
	effect = /obj/machinery/smart_centrifuge/proc/interaction_use

/obj/machinery/smart_centrifuge/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	spin_reagents(user,FALSE)
	return TRUE

/// Old object verb: `set src in view(1)`.
/datum/interaction/machine_verb/centrifuge_isolate_reagents
	id = "centrifuge_isolate_reagents"
	name = "Isolate Reagents Automatically"
	effect = /obj/machinery/smart_centrifuge/proc/interaction_isolate_reagents

/obj/machinery/smart_centrifuge/proc/interaction_isolate_reagents(mob/user, obj/item/held, datum/interaction/interaction)
	spin_reagents(user,FALSE,FALSE)
	return TRUE

/// Old object verb: `set src in view(1)`.
/datum/interaction/machine_verb/centrifuge_isolate_reagents_bottle
	id = "centrifuge_isolate_reagents_bottle"
	name = "Isolate Reagents To Bottles"
	effect = /obj/machinery/smart_centrifuge/proc/interaction_isolate_reagents_bottle

/obj/machinery/smart_centrifuge/proc/interaction_isolate_reagents_bottle(mob/user, obj/item/held, datum/interaction/interaction)
	spin_reagents(user,TRUE,FALSE)
	return TRUE

/// Old object verb: `set src in view(1)`.
/datum/interaction/machine_verb/centrifuge_isolate_reagents_canisters
	id = "centrifuge_isolate_reagents_canisters"
	name = "Isolate Reagents To Canisters"
	effect = /obj/machinery/smart_centrifuge/proc/interaction_isolate_reagents_canisters

/obj/machinery/smart_centrifuge/proc/interaction_isolate_reagents_canisters(mob/user, obj/item/held, datum/interaction/interaction)
	spin_reagents(user,FALSE,TRUE)
	return TRUE

/obj/machinery/smart_centrifuge/proc/spin_reagents(mob/user, force_bottle, force_canister)
	if(working)
		to_chat(user, "<span class='notice'>\The [src] is still spinning.</span>")
		return
	else if(reagents.reagent_list.len == 0)
		to_chat(user, "<span class='notice'>\The [src] is empty.</span>")
		return
	else
		play_sfx(src, SFX_MACHINES_BUTTONBEEP)
		play_sfx(src, SFX_MACHINES_AIRPUMPIDLE)
		to_chat(user, "<span class='notice'>You activate \the [src].</span>")
		separate_force_bottle = force_bottle
		separate_force_canister = force_canister
		separate_delay = 10 SECONDS
		set_working(TRUE)
		flags ^= OPENCONTAINER

/obj/machinery/smart_centrifuge/proc/internal_reagent_seperate()
	var/force_canister = separate_force_canister
	var/force_bottle = separate_force_bottle
	separate_delay = 1 SECOND
	if(reagents.reagent_list.len <= 0)
		visible_message("\The [src] finishes processing.")
		play_sfx(src, SFX_MACHINES_BIOGENERATOR_END, 1.25)
		play_sfx(src, SFX_MACHINES_BUTTONBEEP)
		set_working(FALSE)
		flags |= OPENCONTAINER
		return REPEAT_STOP

	// Seperate out reagents
	for(var/datum/reagent/RL in reagents.reagent_list)
		// Handle special bottle types
		if(!RL.volume)
			continue
		var/obj/item/reagent_containers/CD
		if(force_canister || (RL.volume >= 500 && !force_bottle))
			CD = new /obj/item/reagent_containers/chem_canister(src)
			var/obj/item/reagent_containers/chem_canister/CHEM = CD
			CHEM.set_canister(RL.name,RL.id)
		else
			CD = new /obj/item/reagent_containers/glass/bottle(src)
			CD.name = "[RL.name] bottle"
			CD.icon_state = "bottle-1"
		// Transfer if possible
		play_sfx(src, SFX_MACHINES_REAGENT_DISPENSE)
		reagents.trans_id_to( CD, RL.id, min(RL.volume,CD.reagents.maximum_volume), TRUE)
		CD.update_icon()
		CD.forceMove(loc) // Drop it outside
		CD.pixel_x = rand(-7, 7) // random position
		CD.pixel_y = rand(-7, 7)
		break

/// Old MouseDrop_T: only trolley tanks are handled; anything else, or a failed guard, falls through to ..().
/datum/interaction/machine_drag/centrifuge_drain_tank
	id = "centrifuge_drain_tank"
	name = "Drain"
	held_type = /obj/vehicle/train/trolley_tank
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/smart_centrifuge/proc/can_drop_drain, null))
	effect = /obj/machinery/smart_centrifuge/proc/interaction_drain_tank

/// No side effects.
/obj/machinery/smart_centrifuge/proc/can_drop_drain(mob/actor, atom/target, atom/movable/held)
	if(actor?.buckled_to() || actor.stat || actor.restrained() || !target.Adjacent(actor) || !actor.Adjacent(held) || (actor == held && !actor.canmove))
		return FALSE
	return TRUE

/obj/machinery/smart_centrifuge/proc/interaction_drain_tank(mob/user, atom/movable/dropping, datum/interaction/interaction)
	dropping.reagents.trans_to_holder( src.reagents, src.reagents.maximum_volume)
	act_message(user, dropping, others = "%U% drains %T% into \the [src].")
	return TRUE

/obj/machinery/smart_centrifuge/examine(mob/user, infix, suffix)
	. = ..()
	. += "The meter shows [reagents.total_volume]u / [reagents.maximum_volume]u."
	for(var/datum/reagent/RL in reagents.reagent_list)
		. += "[RL.name]: [RL.volume]u."
