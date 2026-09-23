/obj/machinery/rnd
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	maintenance_wrench_time = 2 SECONDS
	name = "R&D Device"
	icon = 'icons/obj/machines/research_vr.dmi'
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE

	///Are we currently printing a machine
	var/busy = FALSE
	///Is this machne hacked via wires
	var/hacked = FALSE
	///Is this machine disabled via wires
	var/disabled = FALSE
	///Ref to global science techweb.
	var/datum/techweb/stored_research
	///The item loaded inside the machine, used by experimentors and destructive analyzers only.
	var/datum/weakref/loaded_item

/obj/machinery/rnd/Initialize(mapload)
	. = ..()
	if(!stored_research)
		CONNECT_TO_RND_SERVER_ROUNDSTART(stored_research, src)
	if(stored_research)
		on_connected_techweb()
	set_wires(new /datum/wires/rnd(src))

/obj/machinery/rnd/Destroy()
	if(stored_research)
		log_research("[src] disconnected from techweb [stored_research] (destroyed).")
		stored_research = null
	QDEL_NULL(wires)
	loaded_item = null
	return ..()

/obj/machinery/rnd/tgui_status(mob/user)
	if(disabled)
		return STATUS_CLOSE
	return ..()

///Called when attempting to connect the machine to a techweb, forgetting the old.
/obj/machinery/rnd/proc/connect_techweb(datum/techweb/new_techweb)
	if(stored_research)
		log_research("[src] disconnected from techweb [stored_research] when connected to [new_techweb].")
	stored_research = new_techweb
	if(!isnull(stored_research))
		on_connected_techweb()

///Called post-connection to a new techweb.
/obj/machinery/rnd/proc/on_connected_techweb()
	SHOULD_CALL_PARENT(FALSE)

///Reset the state of this machine
/obj/machinery/rnd/proc/reset_busy()
	busy = FALSE

/obj/machinery/rnd/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/rnd_part_replace,
		/datum/interaction/machine_hand/rnd_use,
	)
	..()

/datum/interaction/machine_hand/rnd_use
	id = "rnd_use"
	name = "Use"
	effect = /obj/machinery/rnd/proc/interaction_rnd_use

/obj/machinery/rnd/proc/interaction_rnd_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(wires && panel_open)
		wires.Interact(user)
		return TRUE
	if(disabled)
		return TRUE
	tgui_interact(user)
	return TRUE

/datum/interaction/machine_item/rnd_part_replace
	id = "rnd_part_replace"
	name = "Replace parts"
	category = INTERACTION_CAT_MAINTAIN
	held_type = /obj/item/storage/part_replacer
	effect = /obj/machinery/rnd/proc/interaction_rnd_part_replace

/obj/machinery/rnd/proc/interaction_rnd_part_replace(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	if(default_part_replacement(user, held))
		return TRUE
	return FALSE

/obj/machinery/rnd/screwdriver_act(mob/user, obj/item/tool)
	var/result = ..()
	if(ITEM_INTERACT_CONSUMED(result) && wires && panel_open)
		wires.Interact(user)
	return result

/obj/machinery/rnd/dismantle()
	var/obj/item/our_item = loaded_item?.resolve()
	if(our_item)
		our_item.forceMove(drop_location())
	loaded_item = null
	. = ..()
