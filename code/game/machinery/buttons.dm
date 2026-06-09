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

/obj/machinery/button/attack_ai(mob/user as mob)
	return attack_hand(user)

/obj/machinery/button/attackby(obj/item/W, mob/user as mob)
	return attack_hand(user)

/obj/machinery/button/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag


// === merged from buttons_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/machinery/button/attack_hand(obj/item/W, mob/user as mob)
	if(..()) return 1
	SEND_GLOBAL_SIGNAL(COMSIG_GLOB_BUTTON_PRESSED, src, user)
	playsound(src, 'sound/machines/button.ogg', 100, 1)

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


// === merged from buttons_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/machinery/button/mob_spawner_button
	name = "Mob spawner"
	var/mob/living/simple_mob/mobspawned
	///What spawner is linked with this spawner
	var/link = "MOBSPAWN"

/obj/machinery/button/mob_spawner_button/attack_hand(mob/living/user)
	var/mob_wanted = tgui_input_list(user, "Which Mob do you want to spawn?", "Mob spawn", GLOB.vr_mob_spawner_options)
	if(!mob_wanted)
		return
	var/neutral = FALSE
	var/mobtype = GLOB.vr_mob_spawner_options[mob_wanted]
	var/faction = tgui_alert(user, "Do you want the mob's faction to remain the same or be passive?","Faction",list("Normal","Neutral"))
	if(!faction)
		return
	QDEL_NULL(mobspawned)
	if(faction == "Neutral")
		neutral = TRUE
	mobspawned = new mobtype(get_turf(GLOB.button_mob_spawner_landmark[link]))
	if(!istype(mobspawned))
		mobspawned = null
		return
	mobspawned.voremob_loaded = TRUE
	mobspawned.init_vore()
	if(neutral == TRUE)
		mobspawned.faction = "neutral"
	RegisterSignal(mobspawned, COMSIG_QDELETING, PROC_REF(clean_mob))

/obj/machinery/button/mob_spawner_button/proc/clean_mob()
	SIGNAL_HANDLER
	mobspawned = null

/obj/machinery/button/mob_spawner_button/second
	link = "MOBSPAWNSECOND"

/obj/machinery/button/remote/noemag/emag_act(remaining_charges, mob/user)
	to_chat(usr, span_warning("The cryptographic sequencer seems to do nothing."))
	return 0
