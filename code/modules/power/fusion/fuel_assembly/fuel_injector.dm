
/obj/machinery/fusion_fuel_injector
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	name = "fuel injector"
	icon = 'icons/obj/machines/power/fusion.dmi'
	icon_state = "injector0"
	density = TRUE
	anchored = FALSE
	req_access = list(ACCESS_ENGINE)
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	active_power_usage = 500

	circuit = /obj/item/circuitboard/fusion_injector

	var/fuel_usage = 30
	var/id_tag
	var/obj/item/fuel_assembly/cur_assembly

REGISTRY_MEMBERSHIP(/obj/machinery/fusion_fuel_injector, REGISTRY_FUEL_INJECTORS)

OM_FIELD(/obj/machinery/fusion_fuel_injector, injecting, FALSE, CHANGE_MACHINE_SETTINGS)
DECLARE_PERIODIC_WHILE(/obj/machinery/fusion_fuel_injector, MACHINE_PIPELINE, "injecting")

/obj/machinery/fusion_fuel_injector/Initialize(mapload)
	. = ..()
	default_apply_parts()
	make_rotatable()

OWN(/obj/machinery/fusion_fuel_injector, cur_assembly, OWN_SPILL)

/obj/machinery/fusion_fuel_injector/mapped
	anchored = TRUE

/obj/machinery/fusion_fuel_injector/machine_step()
	if(!operable())
		StopInjecting()
		return
	Inject()

/obj/machinery/fusion_fuel_injector/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/fuel_injector_set_id,
		/datum/interaction/machine_item/fuel_injector_insert_assembly,
		/datum/interaction/machine_item/fuel_injector_part_replace,
		/datum/interaction/machine_hand/ungated/fuel_injector_take,
	)
	..()

/datum/interaction/machine_item/fuel_injector_set_id
	id = "fuel_injector_set_id"
	name = "Set ident tag"
	tool = TOOL_MULTITOOL
	tool_volume = 0
	effect = /obj/machinery/fusion_fuel_injector/proc/interaction_fuel_injector_set_id

/obj/machinery/fusion_fuel_injector/proc/interaction_fuel_injector_set_id(mob/user, obj/item/held, datum/interaction/interaction)
	var/new_ident = rerun_ask(user, "k62", PROC_REF(interaction_fuel_injector_set_id), args, /datum/om/prompt/text, message = "Enter a new ident tag.", title = "Fuel Injector", default = id_tag, max_length = MAX_NAME_LEN)
	if(isnull(new_ident))
		return
	if(new_ident && user.Adjacent(src))
		id_tag = new_ident
	return TRUE

/datum/interaction/machine_item/fuel_injector_insert_assembly
	id = "fuel_injector_insert_assembly"
	name = "Insert fuel rod"
	held_type = /obj/item/fuel_assembly
	effect = /obj/machinery/fusion_fuel_injector/proc/interaction_fuel_injector_insert_assembly
	also_requires = list(REQ_FIELD_NOT("injecting", "shut it off before playing with the fuel rod"))

/obj/machinery/fusion_fuel_injector/proc/interaction_fuel_injector_insert_assembly(mob/user, obj/item/fuel_assembly/held, datum/interaction/interaction)
	if(istype(held,/obj/item/fuel_assembly/blitz))
		var/secondchance = rerun_ask(user, "k78", PROC_REF(interaction_fuel_injector_insert_assembly), args, /datum/om/prompt/choice/alert, message = "Are you sure you want to put the blitz rod in the fuel injector? This definitely wasn't meant to be used like this, and could only end badly.", title = "Confirm", choices = list("Yes","No"))
		if(isnull(secondchance))
			return
		if(!secondchance || secondchance=="No")
			return TRUE
	if(cur_assembly)
		cur_assembly.forceMove(get_turf(src))
		act_message(user, src, others = span_infoplain(span_bold("%U%") + " swaps %T%'s [cur_assembly] for \a [held]."))
	else
		act_message(user, src, others = span_infoplain(span_bold("%U%") + " inserts \a [held] into %T%."))

	user.drop_from_inventory(held)
	held.forceMove(src)
	var/obj/item/fuel_assembly/old_assembly = own_take(src, "cur_assembly") // swapped out to the user
	if(old_assembly)
		old_assembly.forceMove(get_turf(src))
		user.put_in_hands(old_assembly)
	own_set(src, "cur_assembly", held)
	if(istype(held,/obj/item/fuel_assembly/blitz))
		visible_message(span_warning("The fuel injector begins to shake and whirr violently as it tries to accept the blitz rod!"))
		om_after(src, 3 SECONDS, PROC_REF(blitz_boom))
	return TRUE

/datum/interaction/machine_item/fuel_injector_part_replace
	id = "fuel_injector_part_replace"
	name = "Replace parts"
	category = INTERACTION_CAT_MAINTAIN
	held_type = /obj/item/storage/part_replacer
	effect = /obj/machinery/fusion_fuel_injector/proc/interaction_fuel_injector_part_replace
	also_requires = list(REQ_FIELD_NOT("injecting", "shut it off first"))

/obj/machinery/fusion_fuel_injector/proc/interaction_fuel_injector_part_replace(mob/user, obj/item/held, datum/interaction/interaction)
	if(default_part_replacement(user, held))
		return TRUE
	return FALSE

/obj/machinery/fusion_fuel_injector/proc/maintenance_available(mob/user)
	if(!injecting)
		return TRUE
	to_chat(user, span_warning("Shut \the [src] off first!"))
	return FALSE

/obj/machinery/fusion_fuel_injector/wrench_act(mob/user, obj/item/W)
	if(!maintenance_available(user))
		return ITEM_INTERACT_BLOCKING
	return ..()

/obj/machinery/fusion_fuel_injector/screwdriver_act(mob/user, obj/item/W)
	if(!maintenance_available(user))
		return ITEM_INTERACT_BLOCKING
	return ..()

/obj/machinery/fusion_fuel_injector/crowbar_act(mob/user, obj/item/W)
	if(!maintenance_available(user))
		return ITEM_INTERACT_BLOCKING
	return ..()

/datum/interaction/machine_hand/ungated/fuel_injector_take
	id = "fuel_injector_take"
	name = "Take fuel rod"
	category = INTERACTION_CAT_EJECT
	effect = /obj/machinery/fusion_fuel_injector/proc/interaction_fuel_injector_take
	also_requires = list(REQ_FIELD_NOT("injecting", "shut it off before playing with the fuel rod"))

/obj/machinery/fusion_fuel_injector/proc/interaction_fuel_injector_take(mob/user, obj/item/held, datum/interaction/interaction)
	if(cur_assembly)
		var/obj/item/fuel_assembly/removed = own_take(src, "cur_assembly")
		removed.forceMove(get_turf(src))
		user.put_in_hands(removed)
		act_message(user, src, others = span_infoplain(span_bold("%U%") + " removes \the [removed] from %T%."))
		return TRUE
	else
		to_chat(user, span_warning("There is no fuel rod in \the [src]."))
		return TRUE

/obj/machinery/fusion_fuel_injector/proc/BeginInjecting()
	if(!injecting && cur_assembly)
		icon_state = "injector1"
		set_injecting(TRUE)
		set_use_power(USE_POWER_IDLE)

/obj/machinery/fusion_fuel_injector/proc/StopInjecting()
	if(injecting)
		set_injecting(FALSE)
		icon_state = "injector0"
		set_use_power(USE_POWER_OFF)

/obj/machinery/fusion_fuel_injector/proc/Inject()
	if(!injecting)
		return
	if(cur_assembly)
		var/amount_left = 0
		for(var/reagent in cur_assembly.rod_quantities)
			if(cur_assembly.rod_quantities[reagent] > 0)
				var/numparticles = fuel_usage
				if(numparticles < 1)
					numparticles = 1
				var/obj/effect/accelerated_particle/A = new/obj/effect/accelerated_particle(get_turf(src), dir)
				A.particle_type = reagent
				A.additional_particles = numparticles - 1
				if(cur_assembly)
					cur_assembly.rod_quantities[reagent] -= fuel_usage
					amount_left += cur_assembly.rod_quantities[reagent]
		if(cur_assembly)
			cur_assembly.percent_depleted = amount_left / cur_assembly.initial_amount
		flick("injector-emitting",src)
	else
		StopInjecting()

/obj/machinery/fusion_fuel_injector/proc/blitz_boom()
	explosion(loc,2,3,4,8)
	qdel(src)
