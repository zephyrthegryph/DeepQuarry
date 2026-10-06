/mob/living/simple_mob/animal/goat
	name = "goat"
	desc = "Not known for their pleasant disposition."
	tt_desc = "E Oreamnos americanus"
	icon_state = "goat"
	icon_living = "goat"
	icon_dead = "goat_dead"

	faction = FACTION_GOAT

	endurance = 40

	response_help  = "pets"
	response_disarm = "gently pushes aside"
	response_harm   = "kicks"

	melee_damage_lower = 1
	melee_damage_upper = 5
	attacktext = list("kicked")

	say_list_type = /datum/say_list/goat

	meat_amount = 6
	meat_type = /obj/item/reagent_containers/food/snacks/meat

	var/datum/reagents/udder = null

CAPABILITIES(/mob/living/simple_mob/animal/goat)
	owns_one(nameof(udder), /datum/reagents)

/mob/living/simple_mob/animal/goat/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(udder), new /datum/reagents(50)) // ALLOW(decl): holder takes constructor args
	rel_set(udder, nameof(udder.my_atom), src)

/mob/living/simple_mob/animal/goat/life_type_post_due()
	return TRUE

/mob/living/simple_mob/animal/goat/life_type_post(datum/seq_frame/life/F)
	..()
	if(F.alive())
		if(src.stat == CONSCIOUS)
			if(src.udder && prob(5))
				src.udder.add_reagent(REAGENT_ID_MILK, rand(5, 10))

		if(locate_in_list(src.loc, /obj/effect/plant))
			var/obj/effect/plant/SV = locate_in_list(src.loc, /obj/effect/plant)
			SV.die_off(1)

		if(locate_in_list(src.loc, /obj/machinery/portable_atmospherics/hydroponics/soil/invisible))
			var/obj/machinery/portable_atmospherics/hydroponics/soil/invisible/SP = locate_in_list(src.loc, /obj/machinery/portable_atmospherics/hydroponics/soil/invisible)
			spent(SP)

		if(!src?.pulled_by_mob())
			var/obj/effect/plant/food
			food = locate_in_list(oview(5,src.loc), /obj/effect/plant)
			if(food)
				var/step = get_step_to(src, food, 0)
				src.Move(step)

/mob/living/simple_mob/animal/goat/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	if(!stat)
		for(var/obj/effect/plant/SV in contents_of(loc))
			SV.die_off(1)

EXTEND_INTERACTIONS(/mob/living/simple_mob/animal/goat, INTERACT_ITEM(null, PROC_REF(goat_interaction_item)))

/// Old attackby: milking.
/mob/living/simple_mob/animal/goat/proc/goat_interaction_item(mob/user, obj/item/O, datum/interaction/interaction)
	. = TRUE
	var/obj/item/reagent_containers/glass/G = O
	if(stat == CONSCIOUS && istype(G) && G.is_open_container())
		act_message(user, src, null, MSG_OTHERS(span_notice("%U% milks %T% using %I%.")), item = O)
		var/transfered = udder.trans_id_to(G, REAGENT_ID_MILK, rand(5,10))
		if(G.reagents.total_volume >= G.volume)
			to_chat(user, span_red("The [O] is full."))
		if(!transfered)
			to_chat(user, span_red("The udder is dry. Wait a bit longer..."))
	else
		return FALSE

/datum/say_list/goat
	speak = list("EHEHEHEHEH","eh?")
	emote_hear = list("brays")
	emote_see = list("shakes its head", "stamps a foot", "glares around")

	// say_got_target doesn't seem to handle emotes, but keeping this here in case someone wants to make it work
//	say_got_target = list(span_warning("[src] gets an evil-looking gleam in their eye."))

