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
		/datum/interaction/machine_item/soil_fill,
		/datum/interaction/machine_item/soil_shovel,
	)
	..()

/// Old attackby: a tank silently did nothing (never fell through to ..()).
/datum/interaction/machine_item/soil_tank_block
	id = "soil_tank_block"
	name = "Use"
	held_type = /obj/item/tank
	effect = /atom/proc/interaction_swallow

/// Combat mode: fill the growplot in with the shovel.
/datum/interaction/machine_item/soil_fill
	id = "soil_fill"
	name = "Fill in"
	held_type = /obj/item/shovel
	stance = I_HURT
	effect = /obj/machinery/portable_atmospherics/hydroponics/soil/proc/interaction_fill_in

/obj/machinery/portable_atmospherics/hydroponics/soil/proc/interaction_fill_in(mob/user, obj/item/O, datum/interaction/interaction)
	act_message(user, src, others = span_notice("%U% begins filling in %T%."))
	om_task_timed(user, 3 SECONDS, src, src, PROC_REF(fill_in_done), list(user))
	return TRUE

/datum/interaction/machine_item/soil_shovel
	id = "soil_shovel"
	name = "Dig"
	held_type = /obj/item/shovel
	effect = /obj/machinery/portable_atmospherics/hydroponics/soil/proc/interaction_shovel

/obj/machinery/portable_atmospherics/hydroponics/soil/proc/fill_in_done(mob/user)
	act_message(user, src, others = span_notice("%U% fills in %T%."))
	consume(src, user)

/obj/machinery/portable_atmospherics/hydroponics/soil/proc/interaction_shovel(mob/user, obj/item/O, datum/interaction/interaction)
	return botany_soil_destroy_stage(user, O, interaction)

/obj/machinery/portable_atmospherics/hydroponics/soil/proc/botany_soil_destroy_stage(mob/user, obj/item/O, datum/interaction/interaction, botany_answer, botany_answer_ready = FALSE)
	if(!seed)
		if(!botany_answer_ready)
			open_request(src, /datum/prompt/choice/botany_soil_destroy, PROC_REF(botany_soil_destroy_answered), answerer = user, botany_operator = user, botany_held = O, botany_interaction = interaction, question = "Do you want to destroy the growplot?", title = "Destroy growplot?", choices = list("Yes", "No"), buttons = TRUE)
			return
		var/choice = botany_answer
		if(isnull(choice))
			return
		if(!choice||choice=="No")
			return TRUE
		act_message(user, src, others = "%U% starts dispersing %T%...", runemessage = "disperses the [src]")
		om_task_timed(user, 5 SECONDS, src, src, TYPE_PROC_REF(/datum, om_qdel_self))
	else
		to_chat(user, span_notice("There is something growing here."))
	return TRUE

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
	dead = 0
	age = 1
	health = seed.get_trait(TRAIT_ENDURANCE)
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

/obj/machinery/portable_atmospherics/hydroponics/soil/invisible/machine_step()
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

/obj/machinery/portable_atmospherics/hydroponics/soil/proc/botany_soil_destroy_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = botany_soil_destroy_apply(A)
	SStgui.update_uis(src)

/obj/machinery/portable_atmospherics/hydroponics/soil/proc/botany_soil_destroy_apply(datum/act/request/A)
	var/datum/prompt/choice/botany_soil_destroy/ask = A.answer
	return botany_soil_destroy_stage(ask.botany_operator, ask.botany_held, ask.botany_interaction, ask.value, TRUE)

/datum/prompt/choice/botany_soil_destroy
	timeout = 0
	var/mob/botany_operator
	var/obj/item/botany_held
	var/datum/interaction/botany_interaction
	var/botany_operator_expected = FALSE
	var/botany_held_expected = FALSE
	var/botany_interaction_expected = FALSE

CAPABILITIES(/datum/prompt/choice/botany_soil_destroy)
	ref_one(nameof(botany_operator), /mob)
	ref_one(nameof(botany_held), /obj/item)
	ref_one(nameof(botany_interaction), /datum/interaction)

/datum/prompt/choice/botany_soil_destroy/prepare(datum/act/A)
	. = ..()
	var/mob/captured_operator = botany_operator
	var/obj/item/captured_held = botany_held
	var/datum/interaction/captured_interaction = botany_interaction
	botany_operator_expected = !isnull(captured_operator)
	botany_held_expected = !isnull(captured_held)
	botany_interaction_expected = !isnull(captured_interaction)
	rel_clear(src, nameof(botany_operator))
	rel_clear(src, nameof(botany_held))
	rel_clear(src, nameof(botany_interaction))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(botany_operator), captured_operator)
	if(captured_held && !QDELETED(captured_held))
		rel_set(src, nameof(botany_held), captured_held)
	if(captured_interaction && !QDELETED(captured_interaction))
		rel_set(src, nameof(botany_interaction), captured_interaction)

/datum/prompt/choice/botany_soil_destroy/recheck_extra()
	if((botany_operator_expected && QDELETED(botany_operator)) || (botany_held_expected && QDELETED(botany_held)) || (botany_interaction_expected && QDELETED(botany_interaction)))
		return "gone"
