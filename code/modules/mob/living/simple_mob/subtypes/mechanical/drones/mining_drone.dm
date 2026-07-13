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

	maxHealth = 50
	health = 50
	movement_cooldown = 1.5
	// dq_get_hovering(src) type-default moved to GLOB.dq_hovering_by_type

	base_attack_cooldown = 2.5 SECONDS
	projectiletype = /obj/item/projectile/energy/excavate
	projectilesound = 'sound/weapons/pulse3.ogg'

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

	var/last_search = 0
	var/search_cooldown = 5 SECONDS
	var/ignoreunarmed = TRUE
	var/allowedtools = list(/obj/item/pickaxe, /obj/item/gun/energy/kinetic_accelerator, /obj/item/gun/magnetic/matfed/phoronbore, /obj/item/kinetic_crusher, /obj/item/melee/shock_maul)

/mob/living/simple_mob/mechanical/mining_drone/Initialize(mapload)
	ion_trail = new
	ion_trail.set_up(src)
	ion_trail.start()

	my_storage = new /obj/item/ore_bag(src)
	shields = new /obj/item/shield_projector/rectangle/automatic/drone(src)
	return ..()

/mob/living/simple_mob/mechanical/mining_drone/Destroy()
	QDEL_NULL(ion_trail)
	QDEL_NULL(shields)
	QDEL_NULL(my_storage)
	return ..()

/mob/living/simple_mob/mechanical/mining_drone/death()
	my_storage.forceMove(get_turf(src))
	my_storage = null
	..(null,"suddenly breaks apart.")
	qdel(src)

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
					for (var/path in allowedtools)
						if(istype(OH,path))
							has_tool = TRUE
							break
		else
			for (var/path in allowedtools)
				if(istype(I,path))
					has_tool = TRUE
					break
			if(!has_tool) //if a valid tool not found in main hand, check offhand
				var/obj/item/OH = H.get_inactive_hand()
				if(OH)
					for (var/path in allowedtools)
						if(istype(OH,path))
							has_tool = TRUE
							break
		return has_tool

//the IFF retaliation hooks (attack_hand / bullet_act / hit_with_weapon)
// poked legacy ai_brain.check_attacker / add_attacker. The modern brain handles
// retaliation automatically via dq_notify_damage; these wrappers are noops now.
/mob/living/simple_mob/mechanical/mining_drone/attack_hand(mob/living/L)
	return ..()

/mob/living/simple_mob/mechanical/mining_drone/bullet_act(obj/item/projectile/P, def_zone)
	return ..()

/mob/living/simple_mob/mechanical/mining_drone/hit_with_weapon(obj/item/I, mob/living/user, effective_force, hit_zone)
	return ..()
/mob/living/simple_mob/mechanical/mining_drone/handle_special()
	if(my_storage && ((ai_brain ? (ai_brain.primary_threat ? STANCE_FIGHT : STANCE_IDLE) : STANCE_IDLE) in list(STANCE_APPROACH, STANCE_IDLE, STANCE_FOLLOW)) && !(ai_brain && ai_brain.busy) && isturf(loc) && (world.time > last_search + search_cooldown) && (my_storage.contents.len < my_storage.max_storage_space))
		last_search = world.time

		for(var/turf/T in view(world.view,src))
			if(my_storage.contents.len >= my_storage.max_storage_space)
				break

			if((locate(/obj/item/ore) in T) && prob(40))
				src.Beam(T, icon_state = "holo_beam", time = 0.5 SECONDS)
				my_storage.rangedload(T, src)

		if(my_storage.contents.len >= my_storage.max_storage_space)
			visible_message(span_infoplain(span_bold("\The [src]") + " emits a shrill beep, indicating its storage is full."))

		var/obj/structure/ore_box/OB = locate() in view(2, src)

		if(istype(OB) && my_storage && my_storage.contents.len)
			src.Beam(OB, icon_state = "rped_upgrade", time = 1 SECONDS)
			for(var/obj/item/I in my_storage)
				my_storage.remove_from_storage(I, OB)

/datum/decl/mob_organ_names/miningdrone
	hit_zones = list("chassis", "comms array", "sensor suite", "left excavator module", "right excavator module", "maneuvering thruster")

/datum/say_list/malf_drone/mining
	say_threaten = list("Armed intruder detected.", "Lay down your weapons.", "Mining personnel only.", "Threat detected.", "Mining gear check: negative.")

/mob/living/simple_mob/mechanical/mining_drone/scavenger //more aggro version for the debris field, with a weaker weapon
	name = "scavenger drone"
	ignoreunarmed = FALSE
	allowedtools = list(/obj/item/pickaxe)
	projectiletype = /obj/item/projectile/energy/excavate/weak


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
	maxHealth = 25
	health = 25

/mob/living/simple_mob/mechanical/mining_drone
	maxHealth = 25
	health = 25

//Are this things close enough to drones?
/mob/living/simple_mob/mechanical/viscerator
	maxHealth = 7
	health = 7
*/
/obj/item/shield_projector/rectangle/automatic/drone
	shield_health = 75
	max_shield_health = 75
	shield_regen_delay = 10 SECONDS
	shield_regen_amount = 10
	size_x = 1
	size_y = 1
