/obj/machinery/button
	name = "button"
	icon = 'icons/obj/objects.dmi'
	icon_state = "launcherbtt"
	layer = ABOVE_WINDOW_LAYER
	desc = "A remote control switch for something."
	var/id = null
	active = FALSE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 2
	active_power_usage = 4

TRACKED(/obj/machinery/button, id)

/obj/machinery/button/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

MSG_DEF_SELF(button/needs_item, "needs an item")

CAPABILITIES(/obj/machinery/button)
	op("button_press", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Press"), then(PROC_REF(interaction_press)))
	op("button_press_item", inputs(item(/obj/item), menu()), priority(OP_PRIORITY_DEFAULT - 1), label("Press"), needs(req(/obj/item, because = MSG(button/needs_item)), req_adjacent(), req_capable()), when(PROC_REF(local_item_press)), then(TYPE_PROC_REF(/atom, op_as_touch)))

/obj/machinery/button/proc/local_item_press(datum/act/op/A)
	return !istype(src, /obj/machinery/button/remote)

/obj/machinery/button/proc/interaction_press(datum/act/op/A)
	play_sfx(src, SFX_MACHINES_BUTTON, volume = 100)
	return TRUE

/obj/machinery/button/windowtint/multitint
	name = "tint control"
	desc = "A remote control switch for polarized windows and doors."

/obj/machinery/button/windowtint/multitint/toggle_tint()
	use_power(5)
	set_active(!active)

	var/in_range = range(src,range)
	for(var/obj/structure/window/reinforced/polarized/W in in_range)
		if(W.id == src.id || !W.id)
			W.toggle()
	for(var/obj/machinery/door/D in in_range)
		if(D.icon_tinted)
			if(D.id_tint == src.id || !D.id_tint)
				D.toggle()


/obj/machinery/button/mob_spawner_button
	name = "Mob spawner"
	var/mob/living/simple_mob/mobspawned
	///What spawner is linked with this spawner
	var/link = "MOBSPAWN"

CAPABILITIES(/obj/machinery/button/mob_spawner_button)
	op("spawn_mob", hand(), ungated(), priority(OP_PRIORITY_DEFAULT), label("Spawn mob"),
		asks(/datum/prompt/choice, fields = list("choices" = computed(PROC_REF(spawn_options)), "title" = "Mob spawn", "question" = "Which Mob do you want to spawn?", "timeout" = 0), step = "mob"),
		asks(/datum/prompt/choice, fields = list("title" = "Faction", "question" = "Do you want the mob's faction to remain the same or be passive?", "choices" = list("Normal", "Neutral"), "buttons" = TRUE), step = "faction"), then(PROC_REF(spawn_choices_made)))

/obj/machinery/button/mob_spawner_button/proc/spawn_options(datum/act/op/A)
	return GLOB.vr_mob_spawner_options

/obj/machinery/button/mob_spawner_button/proc/spawn_choices_made(datum/act/op/A)
	var/mobtype = GLOB.vr_mob_spawner_options[A.step_value("mob")]
	if(!mobtype || isnull(A.step_value("faction")))
		return OP_OK
	var/neutral = A.step_value("faction") == "Neutral"
	var/mob/living/simple_mob/old_mob = mobspawned()
	rel_clear(src, nameof(mobspawned))
	QDEL_NULL(old_mob)
	rel_set(src, nameof(mobspawned), new mobtype(get_turf(GLOB.button_mob_spawner_landmark[link])))
	if(!istype(mobspawned(), /mob/living/simple_mob))
		rel_clear(src, nameof(mobspawned))
		return TRUE
	mobspawned().voremob_loaded = TRUE
	mobspawned().init_vore()
	if(neutral == TRUE)
		mobspawned().faction = "neutral"
	return TRUE

/obj/machinery/button/mob_spawner_button/second
	link = "MOBSPAWNSECOND"

MSG_DEF_SELF(button/no_emag, "The cryptographic sequencer seems to do nothing.")

// A button no sequencer works: it says so and the card keeps its use.
CAPABILITIES(/obj/machinery/button/remote/noemag)
	without(CAP_EMAG)
	op("emag_refused", item(/obj/item/card/emag), priority(OP_PRIORITY_SUBVERT), wait(0),
		needs(req(PROC_REF(sequencer_welcome), because = MSG(button/no_emag))), then(PROC_REF(press_nothing)))

/obj/machinery/button/remote/noemag/proc/sequencer_welcome(datum/act/A)
	return FALSE

/obj/machinery/button/remote/noemag/proc/press_nothing(datum/act/op/A)
	return OP_OK

/// mobspawned (a relation view: it reads null once the target is deleted).
/obj/machinery/button/mob_spawner_button/proc/mobspawned() as /mob/living/simple_mob
	return mobspawned
