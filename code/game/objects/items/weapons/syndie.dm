/obj/item/syndie
	icon = 'icons/obj/syndieweapons.dmi'

/*C-4 explosive charge and etc, replaces the old syndie transfer valve bomb.*/


/*The explosive charge itself.  Flashes for five seconds before exploding.*/

/obj/item/syndie/c4explosive
	icon_state = "c-4small_0"
	item_state = "radio"
	name = "normal-sized package"
	desc = "A small wrapped package."
	w_class = ITEMSIZE_NORMAL

	var/devastate = 1
	var/heavy_impact = 2
	var/light_impact = 4
	var/flash_range = 5
	var/size = "small"  /*Used for the icon, this one will make c-4small_0 for the off state.*/

/obj/item/syndie/c4explosive/heavy
	icon_state = "c-4large_0"
	item_state = "radio"
	desc = "A mysterious package, it's quite heavy."
	devastate = 1
	heavy_impact = 3
	light_impact = 5
	flash_range = 7
	size = "large"

/obj/item/syndie/c4explosive/heavy/super_heavy
	name = "large-sized package"
	desc = "A mysterious package, it's quite exceptionally heavy."
	devastate = 2
	heavy_impact = 5
	light_impact = 7
	flash_range = 7

/obj/item/syndie/c4explosive/Initialize(mapload)
	. = ..()
	var/K = rand(1,2000)
	K = md5(num2text(K)+name)
	K = copytext(K,1,7)
	desc += "\n You see [K] engraved on \the [src]."
	var/obj/item/flame/lighter/zippo/c4detonator/detonator = new(src.loc)
	detonator.desc += " You see [K] engraved on the lighter."
	rel_set(detonator, "bomb", src)

/obj/item/syndie/c4explosive/proc/detonate()
	icon_state = "c-4[size]_1"
	play_sfx(src, SFX_WEAPONS_ARMBOMB, extrarange = 0)
	for(var/mob/O in hearers(src, null))
		O.show_message("[icon2html(src, O.client)] " + span_warning(" The [src.name] beeps!"))
	om_after(src, 5 SECONDS, PROC_REF(do_detonate))

/obj/item/syndie/c4explosive/proc/do_detonate()
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	for(var/dirn in GLOB.cardinal)		//This is to guarantee that C4 at least breaks down all immediately adjacent walls and doors.
		var/turf/simulated/wall/T = get_step(src,dirn)
		if(locate_on(T, /obj/machinery/door/airlock))
			var/obj/machinery/door/airlock/D = locate_on(T, /obj/machinery/door/airlock)
			if(D.density)
				D.open()
		if(istype(T,/turf/simulated/wall))
			T.dismantle_wall(1)
	qdel(src)

DECLARE_INTERACTIONS(/obj/item/syndie/c4explosive, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/syndie/c4explosive/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/flame/lighter/zippo/c4detonator))
		var/obj/item/flame/lighter/zippo/c4detonator/D = W
		rel_set(D, "bomb", src)
		return INTERACTION_HANDLED_PASS
	return FALSE

/*Detonator, disguised as a lighter*/
/*Click it when closed to open, when open to bring up a prompt asking you if you want to close it or press the button.*/

/obj/item/flame/lighter/zippo/c4detonator
	var/obj/item/syndie/c4explosive/bomb

/// Opened as a detonator it is not a flame: it burns only while lit as a zippo.
DECLARE_PERIODIC_WHILE_ALL(/obj/item/flame/lighter/zippo/c4detonator, PERIODIC_SLOW, list("lit", "!detonator_mode"))

EXTEND_INTERACTIONS(/obj/item/flame/lighter/zippo/c4detonator, INTERACT_SELF(null, PROC_REF(c4detonator_self)))

/// Old attack_self. FALSE (not in detonator mode) falls to the zippo's own self-use.
/obj/item/flame/lighter/zippo/c4detonator/proc/c4detonator_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(!detonator_mode)
		return FALSE
	. = TRUE

	if(!lit)
		base_state = icon_state
		set_lit(TRUE)
		icon_state = "[base_state]1"
		act_message(user, src, others = span_rose("Without even breaking stride, %U% flips open %T% in one smooth movement."))

	else if(lit && detonator_mode)
		om_ask(user, /datum/om/prompt/choice, PROC_REF(detonator_action), title = "Lighter", message = "What would you like to do?", choices = list("Press the button.", "Close the lighter."), buttons = TRUE, ask_flags = ASK_CARRIED | ASK_CAPABLE)

/obj/item/flame/lighter/zippo/c4detonator/proc/detonator_action(datum/om/prompt/choice/ask)
	if(!lit || !detonator_mode)
		return
	var/mob/user = ask.answerer
	switch(ask.choice)
		if("Press the button.")
			to_chat(user, span_warning("You press the button."))
			icon_state = "[base_state]click"
			if(bomb())
				var/obj/item/syndie/c4explosive/bomb_to_explode = bomb()
				rel_clear(src, "bomb") //clear up our ref
				bomb_to_explode.detonate()
				log_admin("[key_name(user)] has triggered [bomb_to_explode] with [src].")
				message_admins(span_danger("[key_name_admin(user)] has triggered [bomb_to_explode] with [src]."))

		if("Close the lighter.")
			set_lit(FALSE)
			icon_state = "[base_state]"
			act_message(user, src, others = span_rose("You hear a quiet click, as %U% shuts off %T% without even looking at what they're doing."))


/obj/item/flame/lighter/zippo/c4detonator/screwdriver_act(mob/user, obj/item/tool)
	set_detonator_mode(!detonator_mode)
	playsound(src, tool.usesound, 50, 1)
	to_chat(user, span_notice("You unscrew the top panel of \the [src] revealing a button."))
	return ITEM_INTERACT_SUCCESS

/// Relation view: bomb (reads null once it is gone).
/obj/item/flame/lighter/zippo/c4detonator/proc/bomb() as /obj/item/syndie/c4explosive
	return bomb
