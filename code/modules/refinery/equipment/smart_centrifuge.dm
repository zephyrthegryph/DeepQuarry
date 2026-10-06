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
	op("centrifuge_attackby", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), when(nameof(working)), then(PROC_REF(interaction_attackby)))
	op("centrifuge_use", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_use)))
	op("centrifuge_isolate_reagents", menu(), label("Isolate Reagents Automatically"), needs(req_adjacent(), req_capable()), then(PROC_REF(interaction_isolate_reagents)))
	op("centrifuge_isolate_reagents_bottle", menu(), label("Isolate Reagents To Bottles"), needs(req_adjacent(), req_capable()), then(PROC_REF(interaction_isolate_reagents_bottle)))
	op("centrifuge_isolate_reagents_canisters", menu(), label("Isolate Reagents To Canisters"), needs(req_adjacent(), req_capable()), then(PROC_REF(interaction_isolate_reagents_canisters)))
	op("centrifuge_drain_tank", item(/obj/vehicle/train/trolley_tank), gesture(GESTURE_DRAG), priority(OP_PRIORITY_DEFAULT - 1), label("Drain"), then(PROC_REF(interaction_drain_tank)))
OM_FIELD(/obj/machinery/smart_centrifuge, working, FALSE, CHANGE_MACHINE_SETTINGS)
DECLARE_REPEAT(/obj/machinery/smart_centrifuge, "separate_delay", internal_reagent_seperate, "working")

/obj/machinery/smart_centrifuge/Initialize(mapload)
	. = ..()
	flags |= OPENCONTAINER
	default_apply_parts()

/obj/machinery/smart_centrifuge/proc/interaction_attackby(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, "<span class='notice'>\The [src] is still spinning.</span>")
	return OP_OK

/obj/machinery/smart_centrifuge/proc/interaction_use(datum/act/op/A)
	var/mob/user = A.actor
	spin_reagents(user,FALSE)
	return OP_OK

/obj/machinery/smart_centrifuge/proc/interaction_isolate_reagents(datum/act/op/A)
	var/mob/user = A.actor
	spin_reagents(user,FALSE,FALSE)
	return TRUE

/obj/machinery/smart_centrifuge/proc/interaction_isolate_reagents_bottle(datum/act/op/A)
	var/mob/user = A.actor
	spin_reagents(user,TRUE,FALSE)
	return TRUE

/obj/machinery/smart_centrifuge/proc/interaction_isolate_reagents_canisters(datum/act/op/A)
	var/mob/user = A.actor
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

/// Whether the drop was a deliberate one (the actor can reach both). No side effects.
/obj/machinery/smart_centrifuge/proc/can_drop_drain(mob/actor, atom/target, atom/movable/held)
	if(actor?.buckled_to() || actor.stat || actor.restrained() || !target.Adjacent(actor) || !actor.Adjacent(held) || (actor == held && !actor.canmove))
		return FALSE
	return TRUE

/obj/machinery/smart_centrifuge/proc/interaction_drain_tank(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/movable/dropping = A.held
	if(!can_drop_drain(user, src, dropping)) // the old MouseDrop_T's silent guard: the drop goes on to whatever else takes it
		return OP_DECLINE
	dropping.reagents.trans_to_holder( src.reagents, src.reagents.maximum_volume)
	act_message(user, dropping, others = "%U% drains %T% into \the [src].")
	return OP_OK

/obj/machinery/smart_centrifuge/examine(mob/user, infix, suffix)
	. = ..()
	. += "The meter shows [reagents.total_volume]u / [reagents.maximum_volume]u."
	for(var/datum/reagent/RL in reagents.reagent_list)
		. += "[RL.name]: [RL.volume]u."
