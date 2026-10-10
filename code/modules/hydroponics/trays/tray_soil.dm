/obj/machinery/portable_atmospherics/hydroponics/soil
	name = "soil"
	icon_state = "soil"
	density = FALSE
	use_power = USE_POWER_OFF
	mechanical = 0
	tray_light = 0
	frozen = -1

MSG_DEF(soil/fill_begin, null, span_notice("%U% begins filling in %T%."))
MSG_DEF(soil/disperse_begin, null, "%U% starts dispersing %T%...")
MSG_DEF_SELF(soil/growing, "There is something growing here.")

// A tank does nothing here (the old attackby swallowed it); a shovel in combat mode fills the plot in, otherwise it digs it up when nothing grows.
CAPABILITIES(/obj/machinery/portable_atmospherics/hydroponics/soil)
	without(CAP_TANK_BAY) // a plot takes no tank: the tank does nothing here
	op("tank_block", item(/obj/item/tank), label("Use"), then(PROC_REF(nothing_happens)))
	op("fill_in", item(/obj/item/shovel), stance(I_HURT), answers(INTENT_ATTACK, INTENT_USE), priority(OP_PRIORITY_ATTACK), label("Fill in"), begins(MSG(soil/fill_begin)), wait(3 SECONDS), then(PROC_REF(fill_in_done)))
	op("dig", item(/obj/item/shovel), answers(INTENT_ATTACK, INTENT_USE), priority(OP_PRIORITY_ATTACK), label("Dig"), stance(I_HELP, I_DISARM, I_GRAB), needs(req(PROC_REF(nothing_growing))),
		soil_destroy_confirms(), begins(MSG(soil/disperse_begin)), wait(5 SECONDS), then(PROC_REF(dispersed)))

/// "Do you want to destroy the growplot?": a yes/no whose "no" ends the op before the work starts.
/proc/soil_destroy_confirms()
	return part_make(/datum/entry/part/asks, list("type" = /datum/prompt/yes_no, "fields" = list("question" = "Do you want to destroy the growplot?", "title" = "Destroy growplot?", "timeout" = 0),
		"step" = "destroy", "resume" = CAPTURE, "keeps" = WAIT_KEEPS_DEFAULT, "confirms" = TRUE))

/obj/machinery/portable_atmospherics/hydroponics/soil/proc/nothing_happens(datum/act/op/A)
	return

/obj/machinery/portable_atmospherics/hydroponics/soil/proc/fill_in_done(datum/act/op/A)
	act_message(A.actor, src, others = span_notice("%U% fills in %T%."))
	consume(src, A.actor)

/obj/machinery/portable_atmospherics/hydroponics/soil/proc/nothing_growing(datum/act/op/A)
	return (!seed) ? null : MSG(soil/growing)

/obj/machinery/portable_atmospherics/hydroponics/soil/proc/dispersed(datum/act/op/A)
	dissolved(src, A.actor)

/obj/machinery/portable_atmospherics/hydroponics/soil/CanPass()
	return 1

// Holder for vine plants.
// Icons for plants are generated as overlays, so setting it to invisible wouldn't work.
// Hence using a blank icon.
/obj/machinery/portable_atmospherics/hydroponics/soil/invisible
	name = "plant"
	icon = 'icons/obj/seeds.dmi'
	icon_state = "blank"

CAPABILITIES(/obj/machinery/portable_atmospherics/hydroponics/soil/invisible)
	param(nameof(seed_at_make), pos = 1)
	rolls(nameof(pixel_y), range_of(-5, 5))

/// The seed the soil grows (its constructor param).
/obj/machinery/portable_atmospherics/hydroponics/soil/invisible/var/datum/seed/seed_at_make

// ALLOW(init/INSTANCE_STATE): a vine's invisible soil starts its plant alive and healthy
/obj/machinery/portable_atmospherics/hydroponics/soil/invisible/Initialize(mapload)
	. = ..()
	if(isopenturf(loc))
		return INITIALIZE_HINT_QDEL
	proto_set(src, nameof(seed), seed_shareable(seed_at_make))
	set_dead(0)
	set_age(1)
	set_health(seed.get_trait(TRAIT_ENDURANCE))
	EXPIRY_STAMP(src, lastcycle, CLOCK_WORLD)
	check_health()

/obj/machinery/portable_atmospherics/hydroponics/soil/invisible/remove_dead()
	..()
	spent(src)

/obj/machinery/portable_atmospherics/hydroponics/soil/invisible/harvest()
	..()
	if(!seed) // Repeat harvests are a thing.
		spent(src)

/obj/machinery/portable_atmospherics/hydroponics/soil/invisible/die()
	consume(src)

/obj/machinery/portable_atmospherics/hydroponics/soil/invisible/work_step(datum/act/timer/A)
	if(!seed)
		consume(src)
		return PROCESS_KILL
	else if(name=="plant")
		name = seed.display_name
	return ..()

// plants it masked become visible again.
/obj/machinery/portable_atmospherics/hydroponics/soil/invisible/on_destroy(force)
	// Check if we're masking a decal that needs to be visible again.
	for(var/obj/effect/plant/plant in get_turf(src))
		if(plant.invisibility == INVISIBILITY_MAXIMUM)
			plant.invisibility = initial(plant.invisibility)
	..()

