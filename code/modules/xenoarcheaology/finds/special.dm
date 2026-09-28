//endless reagents!
/obj/item/reagent_containers/glass/replenishing
	var/spawning_id

/obj/item/reagent_containers/glass/replenishing/Initialize(mapload)
	. = ..()
	PERIODIC_START(src, PERIODIC_SLOW)
	for(var/x=1;x<=10;x++) //You got 10 chances to hit a reagent that is NOT banned.
		var/new_chem = pick(SSchemistry.chemical_reagents)
		if(new_chem in GLOB.obtainable_chemical_blacklist)
			continue
		else
			spawning_id = new_chem
			break

/obj/item/reagent_containers/glass/replenishing/periodic_step()
	reagents.add_reagent(spawning_id, 0.3)

//a talking gas mask!
/obj/item/clothing/mask/gas/poltergeist
	var/list/heard_talk
	var/last_twitch = 0
	var/max_stored_messages = 100

/obj/item/clothing/mask/gas/poltergeist/Initialize(mapload)
	. = ..()

/// Echoes what it heard through its wearer every 2 s while worn by someone with something to say
/// (hearing or being put on starts it); otherwise it sleeps.
/obj/item/clothing/mask/gas/poltergeist/periodic_step()
	if(!length(heard_talk) || !isliving(src.loc))
		return PROCESS_KILL
	if(length(heard_talk) && isliving(src.loc) && prob(10))
		var/mob/living/M = src.loc
		M.say(DEFAULTPICK(heard_talk, null))

/obj/item/clothing/mask/gas/poltergeist/hear_talk(mob/M, list/message_pieces, verb)
	..()
	if(length(heard_talk) > max_stored_messages)
		LAZYREMOVE(heard_talk, DEFAULTPICK(heard_talk, null))
	LAZYADD(heard_talk, multilingual_to_message(message_pieces))
	if(isliving(loc))
		PERIODIC_START(src, PERIODIC_SLOW)
	if(isliving(src.loc) && world.time - last_twitch > 50)
		last_twitch = world.time

//a vampiric statuette
//todo: cult integration
/obj/item/vampiric
	name = "statuette"
	icon_state = "statuette"
	icon = 'icons/obj/xenoarchaeology.dmi'
	var/charges = 0
	var/list/nearby_mobs
	var/last_bloodcall = 0
	var/bloodcall_interval = 50
	var/last_eat = 0
	var/eat_interval = 100
	var/wight_check_index = 1
	var/list/shadow_wights

/obj/item/vampiric/Initialize(mapload)
	. = ..()
	PERIODIC_START(src, PERIODIC_SLOW)

/// Acts only while a player is near; otherwise it sleeps until one comes near.
/obj/item/vampiric/periodic_step()
	if(!mob_near(world.view, TRUE))
		return sleep_until_mob_near(world.view, TRUE)
	//see if we've identified anyone nearby
	if(world.time - last_bloodcall > bloodcall_interval && length(nearby_mobs))
		var/mob/living/carbon/human/M = pop(nearby_mobs)
		if((M in view(7,src)) && M.vitality() > 0.6)
			if(prob(50))
				bloodcall(M)
				LAZYADD(nearby_mobs, M)

	//suck up some blood to gain power
	if(world.time - last_eat > eat_interval)
		var/obj/effect/decal/cleanable/blood/B = locate() in range(2,src)
		if(B)
			last_eat = world.time
			B.moveToNullspace()
			if(istype(B, /obj/effect/decal/cleanable/blood/drip))
				charges += 0.25
			else
				charges += 1
				playsound(src, 'sound/effects/splat.ogg', 50, 1, -3)

	//use up stored charges
	if(charges >= 10)
		charges -= 10
		var/new_object = pick(/obj/item/soulstone, /obj/item/melee/artifact_blade, /obj/item/book/tome, /obj/item/clothing/head/helmet/space/cult, /obj/item/clothing/suit/space/cult, /obj/structure/constructshell, /obj/item/clothing/shoes/cult)
		new new_object(pick(RANGE_TURFS(1,src)))
		playsound(src, 'sound/effects/ghost.ogg', 50, 1, -3)

	if(charges >= 3)
		if(prob(5))
			charges -= 1
			var/spawn_type = pick(/mob/living/simple_mob/creature)
			new spawn_type(pick(RANGE_TURFS(1,src)))
			playsound(src, pick('sound/hallucinations/growl1.ogg','sound/hallucinations/growl2.ogg','sound/hallucinations/growl3.ogg'), 50, 1, -3)

	if(charges >= 1)
		if(length(shadow_wights) < 5 && prob(5))
			LAZYADD(shadow_wights, new /obj/effect/shadow_wight(src.loc))
			playsound(src, 'sound/effects/ghost.ogg', 50, 1, -3)
			charges -= 0.1

	if(charges >= 0.1)
		if(prob(5))
			src.visible_message(span_red("[icon2html(src,viewers(src))] [src]'s eyes glow ruby red for a moment!"))
			charges -= 0.1

	//check on our shadow wights
	if(length(shadow_wights))
		wight_check_index++
		if(wight_check_index > length(shadow_wights))
			wight_check_index = 1

		var/obj/effect/shadow_wight/W = LAZYACCESS(shadow_wights, wight_check_index)
		if(isnull(W))
			LAZYREMOVE(shadow_wights, W)
		else if(isnull(W.loc))
			LAZYREMOVE(shadow_wights, W)
		else if(get_dist(W, src) > 10)
			LAZYREMOVE(shadow_wights, W)

/obj/item/vampiric/hear_talk(mob/M, list/message_pieces, verb)
	..()
	if(world.time - last_bloodcall >= bloodcall_interval && (M in view(7, src)))
		bloodcall(M)

/obj/item/vampiric/proc/bloodcall(mob/living/carbon/human/M)
	last_bloodcall = world.time
	if(istype(M))
		playsound(src, pick('sound/hallucinations/wail.ogg','sound/hallucinations/veryfar_noise.ogg','sound/hallucinations/far_noise.ogg'), 50, 1, -3)
		LAZYADD(nearby_mobs, M)

		var/target = length(M.organs_by_name) ? pick(M.organs_by_name) : null
		M.injure(INJURY_CUT, rand(5, 10), target, src)
		to_chat(M, span_red("The skin on your [parse_zone(target)] feels like it's ripping apart, and a stream of blood flies out."))
		var/obj/effect/decal/cleanable/blood/splatter/animated/B = new(M.loc)
		//legacy .target reference removed (no equivalent on /datum/ai_brain).
		B.add_blooddna(M.dna,M)
		M.remove_blood(rand(25,50))

//animated blood 2 SPOOKY
/obj/effect/decal/cleanable/blood/splatter/animated
	var/turf/target_turf
	var/loc_last_process

/obj/effect/decal/cleanable/blood/splatter/animated/Initialize(mapload, _age)
	. = ..()
	PERIODIC_START(src, PERIODIC_SLOW)
	loc_last_process = src.loc

/// Crawls toward its target turf every 2 s; arrived, it sleeps.
/obj/effect/decal/cleanable/blood/splatter/animated/periodic_step()
	if(!target_turf)
		return PROCESS_KILL
	if(target_turf && src.loc != target_turf)
		step_towards(src,target_turf)
		if(src.loc == loc_last_process)
			target_turf = null
		loc_last_process = src.loc

		//leave some drips behind
		if(prob(50))
			var/obj/effect/decal/cleanable/blood/drip/D = new(src.loc)
			D.init_forensic_data().merge_blooddna(forensic_data)
			if(prob(50))
				D = new(src.loc)
				D.init_forensic_data().merge_blooddna(forensic_data)
				if(prob(50))
					D = new(src.loc)
					D.init_forensic_data().merge_blooddna(forensic_data)
	else
		..()

/obj/effect/shadow_wight
	name = "shadow wight"
	icon = 'icons/mob/mob.dmi'
	icon_state = "shade"
	density = TRUE

/obj/effect/shadow_wight/Initialize(mapload)
	. = ..()
	PERIODIC_START(src, PERIODIC_SLOW)

/// Acts only while a player is near; otherwise it sleeps until one comes near.
/obj/effect/shadow_wight/periodic_step()
	if(!mob_near(world.view, TRUE))
		return sleep_until_mob_near(world.view, TRUE)
	if(src.loc)
		src.forceMove(get_turf(pick(orange(1,src))))
		var/mob/living/carbon/M = locate() in src.loc
		if(M)
			playsound(src, pick('sound/hallucinations/behind_you1.ogg',\
			'sound/hallucinations/behind_you2.ogg',\
			'sound/hallucinations/i_see_you1.ogg',\
			'sound/hallucinations/i_see_you2.ogg',\
			'sound/hallucinations/im_here1.ogg',\
			'sound/hallucinations/im_here2.ogg',\
			'sound/hallucinations/look_up1.ogg',\
			'sound/hallucinations/look_up2.ogg',\
			'sound/hallucinations/over_here1.ogg',\
			'sound/hallucinations/over_here2.ogg',\
			'sound/hallucinations/over_here3.ogg',\
			'sound/hallucinations/turn_around1.ogg',\
			'sound/hallucinations/turn_around2.ogg',\
			), 50, 1, -3)
			to_chat(M, span_cult("The [src] phases right into your body, your entire form feeling cold and numb!")) //You just had a ghost possess / take residence you...YEAH, it's going to be alarming!
			M.visible_message(span_cult("[M]'s body glows bright red for a moment as glyphs spread across their form!")) //Let's try something fancy.
			M.status_at_least(EFFECT_SLEEPING, rand(5, 10))

			src.moveToNullspace()
	else
		PERIODIC_STOP(src)
		qdel(src) //Let's not just sit in nullspace forever, yeah?

/obj/effect/shadow_wight/Bump(atom/obstacle)
	to_chat(obstacle, span_red("You feel a chill run down your spine!"))

/obj/item/clothing/mask/gas/poltergeist/equipped(mob/user, slot)
	. = ..()
	if(length(heard_talk))
		PERIODIC_START(src, PERIODIC_SLOW)
