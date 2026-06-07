/*
CONTAINS:
Deployable items
*/

/obj/machinery/deployable
	name = "deployable"
	desc = "deployable"
	icon = 'icons/obj/objects.dmi'
	req_access = list(ACCESS_SECURITY)//I'm changing this until these are properly tested./N

/obj/machinery/deployable/barrier
	name = "deployable barrier"
	desc = "A deployable barrier. Swipe your ID card to lock/unlock it."
	icon = 'icons/obj/objects.dmi'
	anchored = FALSE
	density = TRUE
	icon_state = "barrier0"
	var/health = 100.0
	var/maxhealth = 100.0
	var/locked = 0.0
//	req_access = list(ACCESS_MAINT_TUNNELS)

/obj/machinery/deployable/barrier/Initialize(mapload)
	. = ..()
	icon_state = "barrier[locked]"

/obj/machinery/deployable/barrier/attackby(obj/item/W as obj, mob/user as mob)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(istype(W, /obj/item/card/id/))
		if(allowed(user))
			if	(emagged < 2.0)
				locked = !locked
				anchored = !anchored
				icon_state = "barrier[locked]"
				if((locked == 1.0) && (emagged < 2.0))
					to_chat(user, "Barrier lock toggled on.")
					return
				else if((locked == 0.0) && (emagged < 2.0))
					to_chat(user, "Barrier lock toggled off.")
					return
			else
				var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
				s.set_up(2, 1, src)
				s.start()
				visible_message(span_warning("BZZzZZzZZzZT"))
				return
		return
	else if(W.has_tool_quality(TOOL_WRENCH))
		if(health < maxhealth)
			health = maxhealth
			emagged = 0
			req_access = list(ACCESS_SECURITY)
			visible_message(span_warning("[user] repairs \the [src]!"))
			return
		else if(emagged > 0)
			emagged = 0
			req_access = list(ACCESS_SECURITY)
			visible_message(span_warning("[user] repairs \the [src]!"))
			return
		return
	else
		switch(W.damtype)
			if(BURN)
				health -= W.force * 0.75
			if(BRUTE)
				health -= W.force * 0.5
		playsound(src, 'sound/weapons/smash.ogg', 50, 1)
		CheckHealth()
		..()

/obj/machinery/deployable/barrier/proc/CheckHealth()
	if(health <= 0)
		explode()
	return

/obj/machinery/deployable/barrier/attack_generic(mob/user, damage, attack_verb)
	visible_message(span_danger("[user] [attack_verb] the [src]!"))
	playsound(src, 'sound/weapons/smash.ogg', 50, 1)
	user.do_attack_animation(src)
	health -= damage
	CheckHealth()
	return

/obj/machinery/deployable/barrier/take_damage(damage)
	health -= damage
	CheckHealth()
	return

/obj/machinery/deployable/barrier/ex_act(severity)
	switch(severity)
		if(1.0)
			explode()
			return
		if(2.0)
			health -= 25
			CheckHealth()
			return

/obj/machinery/deployable/barrier/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF || (stat & (BROKEN|NOPOWER)))
		return
	if(prob(50/severity))
		locked = !locked
		anchored = !anchored
		icon_state = "barrier[locked]"

/obj/machinery/deployable/barrier/CanPass(atom/movable/mover, turf/target)//So bullets will fly over and stuff.
	if(istype(mover) && mover.checkpass(PASSTABLE) && !isliving(mover)) // Check if living so teshari can't evade security barriers by pressing W
		return TRUE
	return FALSE

/obj/machinery/deployable/barrier/proc/explode()

	visible_message(span_danger("[src] blows apart!"))
	var/turf/Tsec = get_turf(src)

/*	var/obj/item/stack/rods/ =*/
	new /obj/item/stack/rods(Tsec)

	var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
	s.set_up(3, 1, src)
	s.start()

	explosion(src.loc,-1,-1,0)
	if(src)
		qdel(src)

/obj/machinery/deployable/barrier/emag_act(remaining_charges, mob/user)
	if(emagged == 0)
		emagged = 1
		LAZYCLEARLIST(req_access)
		LAZYCLEARLIST(req_one_access)
		to_chat(user, "You break the ID authentication lock on \the [src].")
		var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
		s.set_up(2, 1, src)
		s.start()
		visible_message(span_warning("BZZzZZzZZzZT"))
		return 1
	else if(emagged == 1)
		emagged = 2
		to_chat(user, "You short out the anchoring mechanism on \the [src].")
		var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
		s.set_up(2, 1, src)
		s.start()
		visible_message(span_warning("BZZzZZzZZzZT"))
		return 1


// === merged from deployable_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/structure/barricade/cutout
	name = "stand-up figure"
	desc = "Some sort of wooden stand-up figure..."
	icon = 'icons/obj/cardboard_cutout.dmi'
	icon_state = "cutout_basic"

	maxhealth = 15 //Weaker than normal barricade
	anchored = FALSE

	var/fake_name = "unknown"
	var/fake_desc = "You have to be closer to examine this creature."
	var/construct_name = "basic cutout"

	var/toppled = FALSE
	var/human_name = TRUE

	var/static/list/cutout_types
	var/static/list/painters = list(/obj/item/reagent_containers/glass/paint, /obj/item/floor_painter)//, /obj/item/closet_painter)
	resistance_flags = FLAMMABLE

/obj/structure/barricade/cutout/Initialize(mapload)
	. = ..()
	color = null
	if(human_name)
		fake_name = random_name(pick(list(MALE, FEMALE)))
	name = fake_name
	desc = fake_desc
	if(!cutout_types)
		cutout_types = list()
		var/list/types = typesof(/obj/structure/barricade/cutout)
		for(var/cutout_type in types)
			var/obj/structure/barricade/cutout/pathed_type = cutout_type
			cutout_types[initial(pathed_type.construct_name)] = cutout_type

/obj/structure/barricade/cutout/proc/topple()
	if(toppled)
		return
	toppled = TRUE
	icon_state = "cutout_pushed_over"
	density = FALSE
	name = initial(name)
	desc = initial(desc)
	visible_message(span_warning("[src] topples over!"))

/obj/structure/barricade/cutout/proc/untopple()
	if(!toppled)
		return
	toppled = FALSE
	icon_state = initial(icon_state)
	density = TRUE
	name = fake_name
	desc = fake_desc
	visible_message(span_warning("[src] is uprighted to their proper position."))

/obj/structure/barricade/cutout/CheckHealth()
	if(!toppled && (health < (maxhealth/2)))
		topple()
	..()

/obj/structure/barricade/cutout/attack_hand(mob/user)
	if((. = ..()))
		return

	if(toppled)
		untopple()

/obj/structure/barricade/cutout/examine(mob/user)
	. = ..()

	if(Adjacent(user))
		. += span_notice("... from this distance, they seem to be made of [material.name] ...")

/obj/structure/barricade/cutout/attackby(obj/I, mob/user)
	if(is_type_in_list(I, painters))
		var/choice = tgui_input_list(user, "What would you like to paint the cutout as?", "Cutout Painting", cutout_types)
		if(!choice || !Adjacent(user) || I != user.get_active_hand())
			return TRUE
		if(do_after(user, 10 SECONDS, target = src))
			var/picked_type = cutout_types[choice]
			new picked_type(loc)
			qdel(src) //Laaaazy. Technically heals it too. Must be held together with all that paint.
		return TRUE

	else
		return ..()

//Variants
/obj/structure/barricade/cutout/greytide
	icon_state = "cutout_greytide"
	construct_name = "greytide"
/obj/structure/barricade/cutout/clown
	icon_state = "cutout_clown"
	construct_name = "clown"
/obj/structure/barricade/cutout/mime
	icon_state = "cutout_mime"
	construct_name = "mime"
/obj/structure/barricade/cutout/traitor
	icon_state = "cutout_traitor"
	construct_name = "criminal employee"
/obj/structure/barricade/cutout/fluke
	icon_state = "cutout_fluke"
	construct_name = "nuclear operative"
/obj/structure/barricade/cutout/cultist
	icon_state = "cutout_cultist"
	construct_name = "presumed cultist"
/obj/structure/barricade/cutout/servant
	icon_state = "cutout_servant"
	construct_name = "druid"
/obj/structure/barricade/cutout/new_servant
	icon_state = "cutout_new_servant"
	construct_name = "other druid"
/obj/structure/barricade/cutout/viva
	icon_state = "cutout_viva"
	human_name = FALSE
	fake_name = "Unknown"
	construct_name = "advanced greytide"
/obj/structure/barricade/cutout/wizard
	icon_state = "cutout_wizard"
	construct_name = "wizard"
/obj/structure/barricade/cutout/shadowling
	icon_state = "cutout_shadowling"
	human_name = FALSE
	fake_name = "Unknown"
	construct_name = "dark creature"
/obj/structure/barricade/cutout/fukken_xeno
	icon_state = "cutout_fukken_xeno"
	human_name = FALSE
	fake_name = "xenomorph"
	construct_name = "alien"
/obj/structure/barricade/cutout/swarmer
	icon_state = "cutout_swarmer"
	human_name = FALSE
	fake_name = "swarmer"
	construct_name = "robot"
/obj/structure/barricade/cutout/free_antag
	icon_state = "cutout_free_antag"
	construct_name = "hot lizard"
/obj/structure/barricade/cutout/deathsquad
	icon_state = "cutout_deathsquad"
	construct_name = "unknown"
/obj/structure/barricade/cutout/ian
	icon_state = "cutout_ian"
	human_name = FALSE
	fake_name = "corgi"
	construct_name = "dog"
/obj/structure/barricade/cutout/ntsec
	icon_state = "cutout_ntsec"
	construct_name = "nt security"
/obj/structure/barricade/cutout/lusty
	icon_state = "cutout_lusty"
	human_name = FALSE
	fake_name = "xenomorph"
	construct_name = "hot alien"
/obj/structure/barricade/cutout/gondola
	icon_state = "cutout_gondola"
	construct_name = "creature"
/obj/structure/barricade/cutout/monky
	icon_state = "cutout_monky"
	human_name = FALSE
	fake_name = "monkey"
	construct_name = "monkey"
/obj/structure/barricade/cutout/law
	icon_state = "cutout_law"
	human_name = FALSE
	fake_name = "Beepsky"
	construct_name = "lawful robot"

/obj/random/cutout //Random wooden standup figure
	name = "random wooden figure"
	desc = "This is a random wooden figure."
	icon = 'icons/obj/cardboard_cutout.dmi'
	icon_state = "cutout_random"
	spawn_nothing_percentage = 80 //Only spawns 20% of the time to avoid being predictable

/obj/random/cutout/item_to_spawn()
	var/list/cutout_types = subtypesof(/obj/structure/barricade/cutout)
	return pick(cutout_types)
