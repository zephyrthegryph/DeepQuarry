/*
	Mining drones have a slow-firing, armor-piercing beam that can destroy rocks.
	They will, if "tamed", collect ore and deposit it into nearby oreboxes when adjacent.
*/

/datum/category_item/catalogue/technology/drone/mining_drone
	name = "Drone - Mining Drone"
	desc = "A crude modification of the commonly seen combat drone model, usually created\
	from the salvaged husks that litter debris fields. Capable of crude problem solving,\
	the drone's targeting system has been repurposed for locating suitable ores, though even\
	that is only functional in certain conditions.\
	<br><br>\
	These drones are armed with high-power mining emitters, which makes their decrepit forms\
	just as lethal as they were in their prime. Modified thrust vectoring devices allow them\
	to gather ore effectively without expending mechanical energy."
	value = CATALOGUER_REWARD_MEDIUM

/mob/living/simple_mob/mechanical/mining_drone
	name = "mining drone"
	desc = "An automated drone with a worn-out appearance, but an ominous gaze."
	catalogue_data = list(/datum/category_item/catalogue/technology/drone/mining_drone)

	icon_state = "miningdrone"
	icon_living = "miningdrone"
	icon_dead = "miningdrone_dead"
	has_eye_glow = TRUE

	faction = FACTION_MALF_DRONE

	endurance = 50
	movement_cooldown = 1.5
	// dq_get_hovering(src) type-default moved to GLOB.dq_hovering_by_type

	base_attack_cooldown = 2.5 SECONDS
	projectiletype = /obj/item/projectile/energy/excavate
	projectilesound = SFX_WEAPONS_PULSE3

	response_help = "pokes"
	response_disarm = "gently pushes aside"
	response_harm = "hits"

	organ_names = /datum/decl/mob_organ_names/miningdrone

	say_list_type = /datum/say_list/malf_drone/mining

	tame_items = list(
	/obj/item/ore/verdantium = 90,
	/obj/item/ore/hydrogen = 90,
	/obj/item/ore/osmium = 70,
	/obj/item/ore/diamond = 70,
	/obj/item/ore/gold = 55,
	/obj/item/ore/silver = 55,
	/obj/item/ore/lead = 40,
	/obj/item/ore/marble = 30,
	/obj/item/ore/coal = 25,
	/obj/item/ore/iron = 25,
	/obj/item/ore/glass = 15,
	/obj/item/ore = 5
	)

	var/datum/effect/effect/system/ion_trail_follow/ion_trail = null
	var/obj/item/shield_projector/shields = null
	var/obj/item/ore_bag/my_storage = null

	COOLDOWN_DECLARE(search_cooldown_until)
	var/search_cooldown = 5 SECONDS
	var/ignoreunarmed = TRUE
TYPE_TABLE_DECLARE(/mob/living/simple_mob/mechanical/mining_drone, mining_drone_allowed_tools, list(/obj/item/pickaxe, /obj/item/gun/energy/kinetic_accelerator, /obj/item/gun/magnetic/matfed/phoronbore, /obj/item/kinetic_crusher, /obj/item/melee/shock_maul))

CAPABILITIES(/mob/living/simple_mob/mechanical/mining_drone)
	owns_one(nameof(ion_trail), /datum/effect/effect/system/ion_trail_follow)
	owns_one(nameof(my_storage), starts = /obj/item/ore_bag)
	owns_one(nameof(shields), starts = /obj/item/shield_projector/rectangle/automatic/drone)

/mob/living/simple_mob/mechanical/mining_drone/Initialize(mapload)
	rel_set(src, nameof(ion_trail), new /datum/effect/effect/system/ion_trail_follow) // ALLOW(decl): configured and started before parent init
	ion_trail.set_up(src)
	ion_trail.start()
	return ..()


/mob/living/simple_mob/mechanical/mining_drone
	delete_on_death = TRUE

/mob/living/simple_mob/mechanical/mining_drone
	death_message = "suddenly breaks apart."

/mob/living/simple_mob/mechanical/mining_drone/on_death(gibbed)
	var/obj/item/ore_bag/dropped = rel_take(src, nameof(my_storage))
	dropped?.forceMove(get_turf(src))
	..()

/mob/living/simple_mob/mechanical/mining_drone/Process_Spacemove(check_drift = 0)
	return TRUE

/mob/living/simple_mob/mechanical/mining_drone/IIsAlly(mob/living/L)
	. = ..()

	var/mob/living/carbon/human/H = L
	if(!istype(H))
		return .

	if(!.)
		if(ai_brain.check_attacker(H)) //it doesn't care how nicely you're geared if you've attacked it
			return FALSE

		var/has_tool = FALSE
		var/obj/item/I = H.get_active_hand()
		if(!istype(I,/obj/item))
			if(ignoreunarmed)
				return TRUE
			else //just so they don't attack "miners" for having their mining gear in their offhand
				var/obj/item/OH = H.get_inactive_hand()
				if(OH)
					for (var/path in TYPE_TABLE_GET(src, mining_drone_allowed_tools))
						if(istype(OH,path))
							has_tool = TRUE
							break
		else
			for (var/path in TYPE_TABLE_GET(src, mining_drone_allowed_tools))
				if(istype(I,path))
					has_tool = TRUE
					break
			if(!has_tool) //if a valid tool not found in main hand, check offhand
				var/obj/item/OH = H.get_inactive_hand()
				if(OH)
					for (var/path in TYPE_TABLE_GET(src, mining_drone_allowed_tools))
						if(istype(OH,path))
							has_tool = TRUE
							break
		return has_tool

//the IFF retaliation hooks (attack_hand / bullet_act / hit_with_weapon)
// poked legacy ai_brain.check_attacker / add_attacker. The modern brain handles
// retaliation automatically via dq_notify_damage; these wrappers are noops now.

/mob/living/simple_mob/mechanical/mining_drone/hit_with_weapon(obj/item/I, mob/living/user, effective_force, hit_zone)
	return ..()

/mob/living/simple_mob/mechanical/mining_drone/life_special_due()
	return TRUE

/mob/living/simple_mob/mechanical/mining_drone/life_special(datum/seq_frame/life/F)
	if(src.my_storage && ((src.ai_brain ? (src.ai_brain.primary_threat ? STANCE_FIGHT : STANCE_IDLE) : STANCE_IDLE) in list(STANCE_APPROACH, STANCE_IDLE, STANCE_FOLLOW)) && !om_busy(src) && isturf(src.loc) && (COOLDOWN_FINISHED(src, search_cooldown_until)) && (contents_count(src.my_storage) < src.my_storage.max_storage_space))
		COOLDOWN_START(src, search_cooldown_until, src.search_cooldown)

		for(var/turf/T in view(world.view,src))
			if(contents_count(src.my_storage) >= src.my_storage.max_storage_space)
				break

			if((locate_within(T, /obj/item/ore)) && prob(40))
				src.Beam(T, icon_state = "holo_beam", time = 0.5 SECONDS)
				src.my_storage.rangedload(T, src)

		if(contents_count(src.my_storage) >= src.my_storage.max_storage_space)
			act_message(src, null, null, MSG_OTHERS(span_infoplain(span_bold("%U%") + " emits a shrill beep, indicating its storage is full.")))

		var/obj/structure/ore_box/OB = locate_in_list(view(2, src), /obj/structure/ore_box)

		if(istype(OB) && src.my_storage && contents_count(src.my_storage))
			src.Beam(OB, icon_state = "rped_upgrade", time = 1 SECONDS)
			for(var/obj/item/I in src.my_storage)
				src.my_storage.remove_from_storage(I, OB)

/datum/decl/mob_organ_names/miningdrone
TYPE_TABLE(/datum/decl/mob_organ_names/miningdrone, mob_organ_hit_zones, list("chassis", "comms array", "sensor suite", "left excavator module", "right excavator module", "maneuvering thruster"))

/datum/say_list/malf_drone/mining
	say_threaten = list("Armed intruder detected.", "Lay down your weapons.", "Mining personnel only.", "Threat detected.", "Mining gear check: negative.")

/mob/living/simple_mob/mechanical/mining_drone/scavenger //more aggro version for the debris field, with a weaker weapon
	name = "scavenger drone"
	ignoreunarmed = FALSE
	projectiletype = /obj/item/projectile/energy/excavate/weak

TYPE_TABLE(/mob/living/simple_mob/mechanical/mining_drone/scavenger, mining_drone_allowed_tools, list(/obj/item/pickaxe))

// === merged from combat_drone_chomp.dm during hard-fork de-suffix. Placed in this file because it
// is the highest-positioned definer in the override chain for the members it
// sets, so every override stays after its base definition (resolution preserved). ===
/mob/living/simple_mob/mechanical/combat_drone
	projectiletype = /obj/item/projectile/energy/mob/drone

/mob/living/simple_mob/mechanical/combat_drone/lesser/aerostat
	desc = "A Vir System Authority automated combat drone with an aged apperance."
	movement_cooldown = 10
	say_list_type = /datum/say_list/malf_drone/drone_aerostat

/datum/say_list/malf_drone/drone_aerostat
	speak = list("ALERT.","Hostile-ile-ile entities dee-twhoooo-wected.","Threat parameterszzzz- szzet.","Bring sub-sub-sub-systems uuuup to combat alert alpha-a-a.")
	emote_see = list("beeps menacingly","whirrs threateningly","scans its immediate vicinity")

	say_understood = list("Affirmative.", "Positive.")
	say_cannot = list("Denied.", "Negative.")
	say_maybe_target = list("Possible threat detected. Investigating.", "Motion detected.", "Investigating.")
	say_got_target = list("Threat detected.", "New task: Remove threat.", "Threat removal engaged.", "Engaging target.")
	say_threaten = list("This area is condemned by Vir System Authority. Please leave immediately. You have 20 seconds to comply.")
	say_stand_down = list("Visual lost.", "Error: Target not found.")
	say_escalate = list("Intruder is tresspassing. Maximum force authorized by Vir System Suthority.")
	threaten_sound = 'sound/mob/robots/dronefreezelong.ogg'
	stand_down_sound = 'sound/mob/robots/dronelosttarget.ogg'
/* Combat refactor walkback
/mob/living/simple_mob/mechanical/combat_drone
	endurance = 25

/mob/living/simple_mob/mechanical/mining_drone
	endurance = 25

//Are this things close enough to drones?
/mob/living/simple_mob/mechanical/viscerator
	endurance = 7
*/
/obj/item/shield_projector/rectangle/automatic/drone
	max_integrity = 75
	shield_regen_delay = 10 SECONDS
	shield_regen_amount = 10
	size_x = 1
	size_y = 1
