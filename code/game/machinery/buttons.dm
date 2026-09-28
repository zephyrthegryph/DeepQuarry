/obj/machinery/button
	name = "button"
	icon = 'icons/obj/objects.dmi'
	icon_state = "launcherbtt"
	layer = ABOVE_WINDOW_LAYER
	desc = "A remote control switch for something."
	var/id = null
	var/active = FALSE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 2
	active_power_usage = 4

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
	active = !active
	update_icon()

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
	var/mobspawned_handle
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
	om_ask(user, /datum/om/prompt/choice, PROC_REF(spawn_mob_chosen), choices = GLOB.vr_mob_spawner_options, title = "Mob spawn", message = "Which Mob do you want to spawn?", requires = PROMPT_ADJACENT)
	return TRUE

/obj/machinery/button/mob_spawner_button/proc/spawn_mob_chosen(datum/om/prompt/choice/ask)
	var/mobtype = GLOB.vr_mob_spawner_options[ask.choice]
	if(!mobtype)
		return
	om_ask(ask.answerer, /datum/om/prompt/confirm/mob_spawner_faction, PROC_REF(spawn_choices_made), mobtype = mobtype)

/datum/om/prompt/confirm/mob_spawner_faction
	title = "Faction"
	message = "Do you want the mob's faction to remain the same or be passive?"
	yes_text = "Neutral"
	no_text = "Normal"
	no_first = TRUE
	answer_on_no = TRUE
	requires = PROMPT_ADJACENT
	var/mobtype

/obj/machinery/button/mob_spawner_button/proc/spawn_choices_made(datum/om/prompt/confirm/mob_spawner_faction/ask)
	var/neutral = ask.yes
	var/mobtype = ask.mobtype
	var/mob/living/simple_mob/old_mob = mobspawned()
	mobspawned_handle = null
	QDEL_NULL(old_mob)
	mobspawned_handle = om_handle(new mobtype(get_turf(GLOB.button_mob_spawner_landmark[link])))
	if(!istype(mobspawned(), /mob/living/simple_mob))
		mobspawned_handle = null
		return TRUE
	mobspawned().voremob_loaded = TRUE
	mobspawned().init_vore()
	if(neutral == TRUE)
		mobspawned().faction = "neutral"
	return TRUE

/obj/machinery/button/mob_spawner_button/second
	link = "MOBSPAWNSECOND"

/obj/machinery/button/remote/noemag/emag_act(remaining_charges, mob/user)
	to_chat(usr, span_warning("The cryptographic sequencer seems to do nothing."))
	return 0

/// LC-refs: mobspawned -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/button/mob_spawner_button/proc/mobspawned() as /mob/living/simple_mob
	return om_resolve(mobspawned_handle)
