//endless reagents!
/obj/item/reagent_containers/glass/replenishing
	var/spawning_id

DECLARE_PERIODIC(/obj/item/reagent_containers/glass/replenishing, PERIODIC_SLOW)

// ALLOW(init/INSTANCE_STATE): rolls which reagent it replenishes
/obj/item/reagent_containers/glass/replenishing/Initialize(mapload)
	. = ..()
	for(var/x=1;x<=10;x++) //You got 10 chances to hit a reagent that is NOT banned.
		var/new_chem = pick(SSchemistry.ready().chemical_reagents)
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
	EXPIRY_DECLARE(last_twitch)
	var/max_stored_messages = 100

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
		om_task_periodic(src, PERIODIC_SLOW)
	if(isliving(src.loc) && ELAPSED(src, last_twitch, CLOCK_WORLD) > 5 SECONDS)
		EXPIRY_STAMP(src, last_twitch, CLOCK_WORLD)

//a vampiric statuette
//todo: cult integration
/obj/item/vampiric
	name = "statuette"
	icon_state = "statuette"
	icon = 'icons/obj/xenoarchaeology.dmi'
	var/charges = 0
	var/list/nearby_mobs
	EXPIRY_DECLARE(last_bloodcall)
	var/bloodcall_interval = 50
	EXPIRY_DECLARE(last_eat)
	var/eat_interval = 100
	var/wight_check_index = 1
	var/list/shadow_wights

CAPABILITIES(/obj/item/vampiric)
	owns_many(nameof(shadow_wights))

DECLARE_PERIODIC(/obj/item/vampiric, PERIODIC_SLOW)

/// Acts only while a player is near; otherwise it sleeps until one comes near.
/obj/item/vampiric/periodic_step()
	if(!mob_near(world.view, TRUE))
		return sleep_until_mob_near(world.view, TRUE)
	//see if we've identified anyone nearby
	if(ELAPSED(src, last_bloodcall, CLOCK_WORLD) > bloodcall_interval && length(nearby_mobs))
		var/mob/living/carbon/human/M = pop(nearby_mobs)
		if((M in view(7,src)) && M.vitality() > 0.6)
			if(prob(50))
				bloodcall(M)
				rel_add(src, nameof(nearby_mobs), M)

	//suck up some blood to gain power
	if(ELAPSED(src, last_eat, CLOCK_WORLD) > eat_interval)
		var/obj/effect/decal/cleanable/blood/B = locate_in_list(range(2,src), /obj/effect/decal/cleanable/blood)
		if(B)
			EXPIRY_STAMP(src, last_eat, CLOCK_WORLD)
			B.moveToNullspace()
			if(istype(B, /obj/effect/decal/cleanable/blood/drip))
				charges += 0.25
			else
				charges += 1
				play_sfx(src, SFX_EFFECTS_SPLAT, extrarange = -3)

	//use up stored charges
	if(charges >= 10)
		charges -= 10
		var/new_object = pick(/obj/item/soulstone, /obj/item/melee/artifact_blade, /obj/item/book/tome, /obj/item/clothing/head/helmet/space/cult, /obj/item/clothing/suit/space/cult, /obj/structure/constructshell, /obj/item/clothing/shoes/cult)
		new new_object(pick(RANGE_TURFS(1,src)))
		play_sfx(src, SFX_EFFECTS_GHOST)

	if(charges >= 3)
		if(prob(5))
			charges -= 1
			var/spawn_type = pick(/mob/living/simple_mob/creature)
			new spawn_type(pick(RANGE_TURFS(1,src)))
			play_sfx(src, SFX_HALLUCINATIONS_GROWL)

	if(charges >= 1)
		if(length(shadow_wights) < 5 && prob(5))
			rel_add(src, nameof(shadow_wights), new /obj/effect/shadow_wight(src.loc))
			play_sfx(src, SFX_EFFECTS_GHOST)
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
			own_take_member(src, nameof(shadow_wights), W)
		else if(isnull(W.loc))
			own_take_member(src, nameof(shadow_wights), W)
		else if(get_dist(W, src) > 10)
			own_take_member(src, nameof(shadow_wights), W)

/obj/item/vampiric/hear_talk(mob/M, list/message_pieces, verb)
	..()
	if(ELAPSED(src, last_bloodcall, CLOCK_WORLD) >= bloodcall_interval && (M in view(7, src)))
		bloodcall(M)

/obj/item/vampiric/proc/bloodcall(mob/living/carbon/human/M)
	EXPIRY_STAMP(src, last_bloodcall, CLOCK_WORLD)
	if(istype(M))
		play_sfx(src, SFX_HALLUCINATIONS_WAIL)
		rel_add(src, nameof(nearby_mobs), M)

		var/target = length(M.organs_by_name) ? pick(M.organs_by_name) : null
		M.injure(INJURY_CUT, rand(5, 10), target, src)
		to_chat(M, span_red("The skin on your [parse_zone(target)] feels like it's ripping apart, and a stream of blood flies out."))
		var/obj/effect/decal/cleanable/blood/splatter/animated/B = new(M.loc)
		//legacy .target reference removed (no equivalent on /datum/ai_brain).
		B.add_blooddna(M.dna,M)
		M.remove_blood(rand(25,50))

//animated blood 2 SPOOKY
/obj/effect/decal/cleanable/blood/splatter/animated
	var/tmp/turf/target_turf
	var/loc_last_process

DECLARE_PERIODIC(/obj/effect/decal/cleanable/blood/splatter/animated, PERIODIC_SLOW)

// ALLOW(init/INSTANCE_STATE): remembers where it starts so it can leave a trail
/obj/effect/decal/cleanable/blood/splatter/animated/Initialize(mapload, _age)
	. = ..()
	loc_last_process = src.loc

/// Crawls toward its target turf every 2 s; arrived, it sleeps.
/obj/effect/decal/cleanable/blood/splatter/animated/periodic_step()
	if(!target_turf())
		return PROCESS_KILL
	if(target_turf() && src.loc != target_turf())
		step_towards(src,target_turf())
		if(src.loc == loc_last_process)
			rel_clear(src, nameof(target_turf))
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

DECLARE_PERIODIC(/obj/effect/shadow_wight, PERIODIC_SLOW)

/// Acts only while a player is near; otherwise it sleeps until one comes near.
/obj/effect/shadow_wight/periodic_step()
	if(!mob_near(world.view, TRUE))
		return sleep_until_mob_near(world.view, TRUE)
	if(src.loc)
		src.forceMove(get_turf(pick(orange(1,src))))
		var/mob/living/carbon/M = locate_within(src.loc, /mob/living/carbon)
		if(M)
			play_sfx(src, SFX_HALLUCINATIONS_VOICES)
			to_chat(M, span_cult("The [src] phases right into your body, your entire form feeling cold and numb!")) //You just had a ghost possess / take residence you...YEAH, it's going to be alarming!
			act_message(M, null, others = span_cult("%U%'s body glows bright red for a moment as glyphs spread across their form!")) //Let's try something fancy.
			M.status_at_least(STAT_SLEEPING, rand(5, 10))

			src.moveToNullspace()
	else
		consume(src) //Let's not just sit in nullspace forever, yeah?
		return PROCESS_KILL

/obj/effect/shadow_wight/Bump(atom/obstacle)
	to_chat(obstacle, span_red("You feel a chill run down your spine!"))

/obj/item/clothing/mask/gas/poltergeist/equipped(mob/user, slot)
	. = ..()
	if(length(heard_talk))
		om_task_periodic(src, PERIODIC_SLOW)

/// Accessor for the target_turf var.
/obj/effect/decal/cleanable/blood/splatter/animated/proc/target_turf() as /turf
	return target_turf
