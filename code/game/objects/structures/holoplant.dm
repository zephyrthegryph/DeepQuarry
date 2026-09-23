/obj/machinery/holoplant
	name = "holoplant"
	desc = "One of those Ward-Takahashi holoplants! Give your space a bit of the comfort of being outdoors, by buying this blue buddy. A rugged case guarantees that your flower will outlive you, and variety of plant types won't let you to get bored along the way!"
	icon = 'icons/obj/holoplants.dmi'
	icon_state = "holopot"
	light_color = "#3C94C5"
	anchored = TRUE
	idle_power_usage = 0
	active_power_usage = 5
	maintenance_flags = MACHINE_MAINT_WRENCH
	maintenance_wrench_time = 1 SECOND
	var/interference = FALSE
	var/icon/plant = null

/obj/machinery/holoplant/Initialize(mapload)
	. = ..()
	activate()

/obj/machinery/holoplant/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/holoplant_toggle,
	)
	..()

/datum/interaction/machine_hand/holoplant_toggle
	id = "holoplant_toggle"
	name = "Toggle"
	category = INTERACTION_CAT_TOGGLE
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/proc/can_operate_by_hand, null))
	effect = /obj/machinery/holoplant/proc/interaction_toggle

/obj/machinery/holoplant/proc/interaction_toggle(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(!istype(user) || interference)
		return TRUE

	if(!anchored)
		to_chat(user,span_warning("\The [src] must be anchored before activation!"))
		return TRUE

	if(!plant)
		activate()
	else
		deactivate()
	return TRUE

/obj/machinery/holoplant/wrench_act(mob/user, obj/item/tool)
	. = ..()
	if(. == ITEM_INTERACT_SUCCESS)
		deactivate()

/obj/machinery/holoplant/proc/activate()
	if(!anchored || stat & (NOPOWER|BROKEN))
		return

	plant = prepare_icon(emagged ? "emagged" : null)
	cut_overlays()
	add_overlay(plant)
	set_light(2)
	update_use_power(USE_POWER_ACTIVE)

/obj/machinery/holoplant/proc/deactivate()
	cut_overlays()
	QDEL_NULL(plant)
	set_light(0)
	update_use_power(USE_POWER_OFF)

/obj/machinery/holoplant/power_change()
	..()
	if(stat & NOPOWER)
		deactivate()
	else
		activate()

/obj/machinery/holoplant/proc/flicker()
	interference = TRUE
	spawn(0)
		cut_overlays()
		set_light(0)
		sleep(rand(2,4))
		add_overlay(plant)
		set_light(2)
		sleep(rand(2,4))
		cut_overlays()
		set_light(0)
		sleep(rand(2,4))
		add_overlay(plant)
		set_light(2)
		interference = FALSE

/obj/machinery/holoplant/proc/prepare_icon(state)
	if(!state)
		state = pick(GLOB.possible_plants)
	var/plant_icon = icon(icon, state)
	return getHologramIcon(plant_icon, 0)

/obj/machinery/holoplant/emag_act()
	if(emagged)
		return

	emagged = TRUE
	if(plant)
		deactivate()
	activate()

/obj/machinery/holoplant/Crossed(mob/living/L)
	if(!interference && plant && istype(L))
		flicker()


/obj/machinery/holoplant/shipped
	anchored = FALSE
/obj/machinery/holoplant/shipped/Initialize(mapload)
	. = ..()
