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

/obj/machinery/button/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/button_press,
		/datum/interaction/machine_item/button_press_item,
	)
	..()

/// Old attack_hand: `if(..()) return 1; playsound(...)`.
/datum/interaction/machine_hand/button_press
	id = "button_press"
	name = "Press"
	effect = /obj/machinery/button/proc/interaction_press

/// Old attackby: any item presses the button (`return attack_hand(user)`).
/datum/interaction/machine_item/button_press_item
	id = "button_press_item"
	name = "Press"
	category = INTERACTION_CAT_TOGGLE
	held_type = /obj/item
	effect = /atom/proc/interaction_as_touch

/// Remote buttons declare their own item interactions.
/datum/interaction/machine_item/button_press_item/applies_to(atom/target)
	return !istype(target, /obj/machinery/button/remote)

/obj/machinery/button/proc/interaction_press(mob/user, obj/item/held, datum/interaction/interaction)
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

/obj/machinery/button/mob_spawner_button/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/mob_spawner_button_spawn,
	)
	..()

/// Old attack_hand, which never called ..() (ungated: no machinery hand gate).
/datum/interaction/machine_hand/ungated/mob_spawner_button_spawn
	id = "mob_spawner_button_spawn"
	name = "Spawn mob"
	effect = /obj/machinery/button/mob_spawner_button/proc/interaction_spawn

/obj/machinery/button/mob_spawner_button/proc/interaction_spawn(mob/living/user, obj/item/held, datum/interaction/interaction)
	open_request(src, /datum/prompt/choice, PROC_REF(spawn_mob_chosen), answerer = user, choices = GLOB.vr_mob_spawner_options, title = "Mob spawn", question = "Which Mob do you want to spawn?", ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)
	return TRUE

/obj/machinery/button/mob_spawner_button/proc/spawn_mob_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mobtype = GLOB.vr_mob_spawner_options[A.answer.value]
	if(!mobtype)
		return
	open_request(src, /datum/prompt/choice/mob_spawner_faction, PROC_REF(spawn_choices_made), answerer = A.request.answerer, title = "Faction", question = "Do you want the mob's faction to remain the same or be passive?", choices = list("Normal", "Neutral"), buttons = TRUE, mobtype = mobtype, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)

/// The mob to spawn is kept on the faction question.
/datum/prompt/choice/mob_spawner_faction
	var/mobtype

/obj/machinery/button/mob_spawner_button/proc/spawn_choices_made(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/mob_spawner_faction/R = A.request
	var/neutral = (A.answer.value == "Neutral")
	var/mobtype = R.mobtype
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
