/obj/machinery/portable_atmospherics/hydroponics/soil
	name = "soil"
	icon_state = "soil"
	density = FALSE
	use_power = USE_POWER_OFF
	mechanical = 0
	tray_light = 0
	frozen = -1

/obj/machinery/portable_atmospherics/hydroponics/soil/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/soil_tank_block,
		/datum/interaction/machine_item/soil_shovel,
	)
	..()

/// Old attackby: a tank silently did nothing (never fell through to ..()).
/datum/interaction/machine_item/soil_tank_block
	id = "soil_tank_block"
	name = "Use"
	held_type = /obj/item/tank
	effect = /obj/machinery/portable_atmospherics/hydroponics/soil/proc/interaction_tank_block

/obj/machinery/portable_atmospherics/hydroponics/soil/proc/interaction_tank_block(mob/user, obj/item/O, datum/interaction/interaction)
	return TRUE

/datum/interaction/machine_item/soil_shovel
	id = "soil_shovel"
	name = "Dig"
	held_type = /obj/item/shovel
	effect = /obj/machinery/portable_atmospherics/hydroponics/soil/proc/interaction_shovel

/obj/machinery/portable_atmospherics/hydroponics/soil/proc/interaction_shovel(mob/user, obj/item/O, datum/interaction/interaction)
	if(IS_HARMING(user))
		user.visible_message(span_notice("\The [user] begins filling in \the [src]."))
		if(do_after(user, 3 SECONDS, target = src) && !QDELETED(src))
			user.visible_message(span_notice("\The [user] fills in \the [src]."))
			qdel(src)
		return TRUE
	if(!seed)
		var/choice= tgui_alert(user, "Do you want to destroy the growplot?", "Destroy growplot?" , list("Yes", "No"))
		if(!choice||choice=="No")
			return TRUE
		user.visible_message("[user] starts dispersing the [src]...", runemessage = "disperses the [src]")
		if(do_after(user, 5 SECONDS, target = src))
			qdel(src)
	else
		to_chat(user, span_notice("There is something growing here."))
	return TRUE

/obj/machinery/portable_atmospherics/hydroponics/soil/Initialize(mapload)
	. = ..()

/obj/machinery/portable_atmospherics/hydroponics/soil/CanPass()
	return 1

// Holder for vine plants.
// Icons for plants are generated as overlays, so setting it to invisible wouldn't work.
// Hence using a blank icon.
/obj/machinery/portable_atmospherics/hydroponics/soil/invisible
	name = "plant"
	icon = 'icons/obj/seeds.dmi'
	icon_state = "blank"

/obj/machinery/portable_atmospherics/hydroponics/soil/invisible/Initialize(mapload,datum/seed/newseed)
	. = ..()
	if(isopenturf(loc))
		return INITIALIZE_HINT_QDEL
	seed = newseed
	dead = 0
	age = 1
	health = seed.get_trait(TRAIT_ENDURANCE)
	lastcycle = world.time
	pixel_y = rand(-5,5)
	check_health()

/obj/machinery/portable_atmospherics/hydroponics/soil/invisible/remove_dead()
	..()
	qdel(src)

/obj/machinery/portable_atmospherics/hydroponics/soil/invisible/harvest()
	..()
	if(!seed) // Repeat harvests are a thing.
		qdel(src)

/obj/machinery/portable_atmospherics/hydroponics/soil/invisible/die()
	qdel(src)

/obj/machinery/portable_atmospherics/hydroponics/soil/invisible/process()
	if(!seed)
		qdel(src)
		return
	else if(name=="plant")
		name = seed.display_name
	..()

/obj/machinery/portable_atmospherics/hydroponics/soil/invisible/Destroy()
	// Check if we're masking a decal that needs to be visible again.
	for(var/obj/effect/plant/plant in get_turf(src))
		if(plant.invisibility == INVISIBILITY_MAXIMUM)
			plant.invisibility = initial(plant.invisibility)
	. = ..()
