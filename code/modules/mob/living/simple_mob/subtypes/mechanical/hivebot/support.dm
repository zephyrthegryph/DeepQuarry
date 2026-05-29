// These hivebots help their team in various ways, and can be very powerful with allies, but are otherwise very weak when alone.

/mob/living/simple_mob/mechanical/hivebot/support
	icon_state = "white"
	icon_living = "white"
	attacktext = list("prodded")
	movement_cooldown = 1.5
	melee_damage_lower = 2
	melee_damage_upper = 2

	organ_names = /datum/decl/mob_organ_names/hivebotsupport

// This hivebot supplies a general buff to nearby hivebots that improve their performance.
// Note that the commander itself does not receive the buff.
/mob/living/simple_mob/mechanical/hivebot/support/commander
	name = "commander hivebot"
	desc = "A robot that appears to be directing the others."
	maxHealth = 5 LASERS_TO_KILL // 150 health
	health = 5 LASERS_TO_KILL
	player_msg = "You <b>increase the performance of other hivebots near you</b> passively.<br>\
	You are otherwise very weak offensively."

/mob/living/simple_mob/mechanical/hivebot/support/commander/handle_special()
	for(var/mob/living/L in range(4, src))
		if(L == src)
			continue // Don't buff ourselves.
		if(IIsAlly(L) && L.isSynthetic()) // Don't buff enemies.
			L.add_modifier(/datum/modifier/aura/hivebot_commander_buff, null, src)

// Modifier added to friendly hivebots nearby.
// Boosts most stats by 30%.
// The boost is lost if the commander is too far away or dies.
/datum/modifier/aura/hivebot_commander_buff
	name = "Strategicals"
	on_created_text = span_notice("Signal established with commander. Optimizating combat performance...")
	on_expired_text = span_warning("Lost signal to commander. Optimization halting.")
	stacks = MODIFIER_STACK_FORBID
	aura_max_distance = 4
	mob_overlay_state = "signal_blue"

	disable_duration_percent = 0.7
	outgoing_melee_damage_percent = 1.3
	attack_speed_percent = 0.7
	accuracy = 30
	slowdown = -1
	evasion = 30

// Variant that automatically commands nearby allies to follow it when created.
// Useful to avoid having to manually set follow to a lot of hivebots that are gonna die in the next minute anyways.
/mob/living/simple_mob/mechanical/hivebot/support/commander/autofollow/Initialize(mapload)
	for(var/mob/living/L in hearers(7, src))
		if(!L.ai_brain)
			continue
		if(L.faction != src.faction)
			continue
		var/datum/ai_brain/AI = L.ai_brain
		AI.set_follow(src)
	return ..()


// This hivebot adds charges to nearby allied hivebots that use the charge system for their special attacks.
// A charge is given to a nearby ally every so often.
// Charges cannot exceed the initial starting amount.
/mob/living/simple_mob/mechanical/hivebot/support/logistics
	name = "logistics hivebot"
	desc = "A robot that resupplies their allies."
	maxHealth = 3 LASERS_TO_KILL // 90 health
	health = 3 LASERS_TO_KILL
	player_msg = "You <b>passively restore 'charges' to allies with special abilities</b> who are \
	limited to using them a specific number of times."
	var/resupply_range = 5
	var/resupply_cooldown = 4 SECONDS
	var/last_resupply = null

/mob/living/simple_mob/mechanical/hivebot/support/logistics/handle_special()
	if(last_resupply + resupply_cooldown > world.time)
		return // On cooldown.

	for(var/mob/living/simple_mob/SM in hearers(resupply_range, src))
		if(SM == src)
			continue // We don't use charges buuuuut in case that changes in the future...
		if(IIsAlly(SM)) // Don't resupply enemies.
			if(!isnull(SM.special_attack_charges) && SM.special_attack_charges < initial(SM.special_attack_charges))
				SM.special_attack_charges += 1
				to_chat(SM, span_notice("\The [src] has resupplied you, and you can use your special ability one additional time."))
				to_chat(src, span_notice("You have resupplied \the [SM]."))
				last_resupply = world.time
				break // Only one resupply per pulse.

/datum/decl/mob_organ_names/hivebotsupport
	hit_zones = list("central chassis", "positioning servo", "head", "sensor suite", "manipulator arm", "battle analytics mount", "weapons array", "front right leg", "front left leg", "rear left leg", "rear right leg")

/mob/living/simple_mob/mechanical/hivebot/support/harry
	name = "Harry the hivelessbot"
	desc = "A severely corroded hivebot, covered in barnacles and seaweed."
	maxHealth = 5 // 1 health
	health = 5
	say_list_type = /datum/say_list/hivebot/harry
	melee_damage_lower = 0
	melee_damage_upper = 0
	faction = FACTION_STATION
	water_resist = 1 //Harry lives under the sea!

/mob/living/simple_mob/mechanical/hivebot/support/harry/death()
	..()
	visible_message(span_warning("Connection... terminated... Sweet Release... obtained."),span_danger("\The [src] blows apart!"))
	new /obj/effect/decal/cleanable/blood/gibs/robot(src.loc)
	var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
	s.set_up(3, 1, src)
	s.start()
	qdel(src)


// === merged from support_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/datum/category_item/catalogue/technology/drone/hivebot/commander // Hivebot Scanner Data - This is for Commander Hivebots
	name = "Drone - Commander Hivebot"
	desc = "A drone that walks on several legs, with yellow/gold armor plating. It appears to have some sort of \
	ballistic weapon. It also appears to have hardened internal connections and network interlinks, as well as some sort of datalink \
	to the other hivebots. Other than that, it has similar yellowish color to regular hivebots."
	value = CATALOGUER_REWARD_HARD

/datum/category_item/catalogue/technology/drone/hivebot/logistics // Hivebot Scanner Data - This is for Logistics Hivebots
	name = "Drone - Logistics Hivebot"
	desc = "A drone that walks on several legs, with yellow/gold armor plating. It appears to have some sort of \
	ballistic weapon. It also appears to have supply deploying bays, and internal fabs to repair and buff their allies' special capabilities. \
	Other than that, it has similar yellowish color to regular hivebots."
	value = CATALOGUER_REWARD_HARD
