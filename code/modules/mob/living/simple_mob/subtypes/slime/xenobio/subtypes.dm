// Here are where all the other colors of slime live.
// They will generally fight each other if not Unified, meaning the xenobiologist has to seperate them.

// Tier 1.

/mob/living/simple_mob/slime/xenobio/purple/get_mechanics_info(list/additional_information)
	return ..(list("This slime spreads a toxin when it attacks. A biosuit or other thick armor can protect from the toxic attack.") + additional_information)

/mob/living/simple_mob/slime/xenobio/purple
	desc ="This slime is rather toxic to handle, as it is poisonous."
	color = "#CC23FF"
	slime_color = "purple"
	coretype = /obj/item/slime_extract/purple
	reagent_injected = REAGENT_ID_TOXIN
	player_msg = "You <b>inject a harmful toxin</b> when attacking."

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/dark_purple,
			/mob/living/simple_mob/slime/xenobio/dark_blue,
			/mob/living/simple_mob/slime/xenobio/green,
			/mob/living/simple_mob/slime/xenobio
		)

/mob/living/simple_mob/slime/xenobio/orange/get_mechanics_info(list/additional_information)
	return ..(list("The slime is immune to burning attacks, and attacks from this slime will burn you, and can ignite you. \
	A firesuit can protect from the burning attacks of this slime.") + additional_information)

/mob/living/simple_mob/slime/xenobio/orange
	desc ="This slime is known to be flammable and can ignite enemies."
	color = "#FFA723"
	slime_color = "orange"
	coretype = /obj/item/slime_extract/orange
	melee_damage_lower = 5
	melee_damage_upper = 5
	heat_resist = 1
	player_msg = "You <b>inflict burning attacks</b>, which causes additional damage, makes the target more flammable, and has a chance to ignite them.<br>\
	You are also immune to burning attacks."

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/dark_purple,
			/mob/living/simple_mob/slime/xenobio/yellow,
			/mob/living/simple_mob/slime/xenobio/red,
			/mob/living/simple_mob/slime/xenobio
		)

/mob/living/simple_mob/slime/xenobio/orange/apply_melee_effects(atom/A)
	..()
	if(isliving(A))
		var/mob/living/L = A
		L.inflict_heat_damage(is_adult ? 10 : 5)
		to_chat(src, span_danger("You burn \the [L]."))
		to_chat(L, span_danger("You've been burned by \the [src]!"))
		L.adjust_fire_stacks(1)
		if(prob(12))
			L.ignite_mob()

/mob/living/simple_mob/slime/xenobio/blue/get_mechanics_info(list/additional_information)
	return ..(list("The slime is resistant to the cold, and attacks from this slime can inject cryotoxin into you. \
	A biosuit or other thick armor can protect from the injection.") + additional_information)

/mob/living/simple_mob/slime/xenobio/blue
	desc ="This slime produces 'cryotoxin' and uses it against their foes.  Very deadly to other slimes."
	color = "#19FFFF"
	slime_color = "blue"
	coretype = /obj/item/slime_extract/blue
	reagent_injected = REAGENT_ID_CRYOTOXIN
	cold_resist = 0.50 // Not as strong as dark blue, which has immunity.
	player_msg = "You <b>inject cryotoxin on attack</b>, which causes them to get very cold, slowing them down and harming them over time.<br>\
	You are also resistant to cold attacks."

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/dark_blue,
			/mob/living/simple_mob/slime/xenobio/silver,
			/mob/living/simple_mob/slime/xenobio/pink,
			/mob/living/simple_mob/slime/xenobio
		)


/mob/living/simple_mob/slime/xenobio/metal/get_mechanics_info(list/additional_information)
	return ..(list("This slime is a lot more durable and tough to damage than the others. It also seems to provoke others to attack it over others.") + additional_information)

/mob/living/simple_mob/slime/xenobio/metal
	desc ="This slime is a lot more resilient than the others, due to having a metamorphic metallic and sloped surface."
	color = "#5F5F5F"
	slime_color = "metal"
	shiny = TRUE
	coretype = /obj/item/slime_extract/metal
	player_msg = "You are <b>more resilient and armored</b> than more slimes. Your attacks will also encourage less intelligent enemies to focus on you."

	endurance = 250
	endurance_adult = 350

	// The sloped armor.
	// It's resistant to most weapons (but a spraybottle still kills it rather fast).
	armor_spec = "melee=25;bullet=25;laser=25;energy=50;bomb=80;bio=100;rad=100"

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/silver,
			/mob/living/simple_mob/slime/xenobio/yellow,
			/mob/living/simple_mob/slime/xenobio/gold,
			/mob/living/simple_mob/slime/xenobio
		)

/mob/living/simple_mob/slime/xenobio/metal/apply_melee_effects(atom/A)
	..()
	if(isliving(A))
		var/mob/living/L = A
		L.taunt(src, TRUE) // We're the party tank now.

// Tier 2

/mob/living/simple_mob/slime/xenobio/yellow/get_mechanics_info(list/additional_information)
	return ..(list("In addition to being immune to electrical shocks, this slime will fire ranged lightning attacks at \
	enemies if they are at range, inflict shocks upon entities they attack, and generate electricity for their stun \
	attack faster than usual. Insulative or reflective armor can protect from these attacks.") + additional_information)

/mob/living/simple_mob/slime/xenobio/yellow
	desc ="This slime is very conductive, and is known to use electricity as a means of defense moreso than usual for slimes."
	color = "#FFF423"
	slime_color = "yellow"
	coretype = /obj/item/slime_extract/yellow
	melee_damage_lower = 5
	melee_damage_upper = 5
	shock_resist = 1

	projectiletype = /obj/item/projectile/beam/lightning/slime
	projectilesound = SFX_EFFECTS_LIGHTNINGBOLT
	glow_toggle = TRUE
	player_msg = "You have a <b>ranged electric attack</b>. You also <b>shock enemies you attack</b>, and your electric stun attack charges passively.<br>\
	You are also immune to shocking attacks."

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/bluespace,
			/mob/living/simple_mob/slime/xenobio/bluespace,
			/mob/living/simple_mob/slime/xenobio/metal,
			/mob/living/simple_mob/slime/xenobio/orange
		)

/mob/living/simple_mob/slime/xenobio/yellow/apply_melee_effects(atom/A)
	..()
	if(isliving(A))
		var/mob/living/L = A
		L.inflict_shock_damage(is_adult ? 10 : 5)
		to_chat(src, span_danger("You shock \the [L]."))
		to_chat(L, span_danger("You've been shocked by \the [src]!"))

/mob/living/simple_mob/slime/xenobio/yellow/life_special_due()
	return TRUE

/mob/living/simple_mob/slime/xenobio/yellow/life_special(datum/seq_frame/life/F)
	if(src.stat == CONSCIOUS)
		if(prob(25))
			src.power_charge = between(0, src.power_charge + 1, 10)
	..()

/obj/item/projectile/beam/lightning/slime
	power = 10
	fire_sound = SFX_EFFECTS_LIGHTNINGBOLT


/mob/living/simple_mob/slime/xenobio/dark_purple/get_mechanics_info(list/additional_information)
	return ..(list("This slime applies phoron to enemies it attacks. A biosuit or other thick armor can protect from the toxic attack. \
	If hit with a burning attack, it will erupt in flames.") + additional_information)

/mob/living/simple_mob/slime/xenobio/dark_purple
	desc ="This slime produces ever-coveted phoron.  Risky to handle but very much worth it."
	color = "#660088"
	slime_color = "dark purple"
	coretype = /obj/item/slime_extract/dark_purple
	reagent_injected = REAGENT_ID_PHORON
	player_msg = "You <b>inject phoron</b> into enemies you attack.<br>\
	<b>You will erupt into flames if harmed by fire!</b>"

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/purple,
			/mob/living/simple_mob/slime/xenobio/orange,
			/mob/living/simple_mob/slime/xenobio/ruby,
			/mob/living/simple_mob/slime/xenobio/ruby
		)

/mob/living/simple_mob/slime/xenobio/dark_purple
	fire_reaction = FIRE_REACTION_TRIGGER
	fire_trigger_proc = TYPE_PROC_REF(/mob/living/simple_mob/slime/xenobio/dark_purple, ignite)

/mob/living/simple_mob/slime/xenobio/dark_purple/proc/ignite()
	act_message(src, null, null, MSG_OTHERS(span_critical("%U% erupts in an inferno!")))
	for(var/turf/simulated/target_turf in view(2, src))
		target_turf.assume_gas(GAS_PHORON, 30, 1500+T0C)
		target_turf.hotspot_expose(1500+T0C, 400)
	destroyed(src, null, BURN)

CAPABILITIES(/mob/living/simple_mob/slime/xenobio/dark_purple)
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(blast_ignite))))

/mob/living/simple_mob/slime/xenobio/dark_purple/proc/blast_ignite(datum/act/A)
	log_and_message_admins("ignited due to a chain reaction with an explosion.", src)
	ignite()
	return TRUE

/mob/living/simple_mob/slime/xenobio/dark_purple/bullet_act(obj/item/projectile/P, def_zone)
	if(P.obj_damage_type() && P.obj_damage_type() == BURN && P.damage) // Most bullets won't trigger the explosion, as a mercy towards Security.
		log_and_message_admins("ignited due to bring hit by a burning projectile[P.firer ? " by [key_name(P.firer)]" : ""].", src)
		ignite()
	else
		..()

EXTEND_INTERACTIONS(/mob/living/simple_mob/slime/xenobio/dark_purple, INTERACT_ITEM(null, PROC_REF(darkpurple_slime_interaction_item)))

/// Old attackby: burning weapons ignite it.
/mob/living/simple_mob/slime/xenobio/dark_purple/proc/darkpurple_slime_interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	. = TRUE
	if(istype(W) && W.force && W.obj_damage_type() == BURN)
		log_and_message_admins("ignited due to being hit with a burning weapon ([W]) by [key_name(user)].", src)
		ignite()
	else
		return FALSE



/mob/living/simple_mob/slime/xenobio/dark_blue/get_mechanics_info(list/additional_information)
	return ..(list("This slime is immune to the cold, however water will still kill it. Its presence, as well as its attacks, will \
	also cause you additional harm from the cold. A winter coat or other cold-resistant clothing can protect from this.") + additional_information)

/mob/living/simple_mob/slime/xenobio/dark_blue
	desc ="This slime makes other entities near it feel much colder, and is more resilient to the cold.  It tends to kill other slimes rather quickly."
	color = "#2398FF"
	glow_toggle = TRUE
	slime_color = "dark blue"
	coretype = /obj/item/slime_extract/dark_blue
	melee_damage_lower = 5
	melee_damage_upper = 5
	cold_resist = 1
	player_msg = "You are <b>immune to the cold</b>, inflict additional cold damage on attack, and cause nearby entities to suffer from coldness."

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/purple,
			/mob/living/simple_mob/slime/xenobio/blue,
			/mob/living/simple_mob/slime/xenobio/cerulean,
			/mob/living/simple_mob/slime/xenobio/cerulean
		)

	minbodytemp = 0
	cold_damage_per_tick = 0

/mob/living/simple_mob/slime/xenobio/dark_blue/life_special_due()
	return TRUE

/mob/living/simple_mob/slime/xenobio/dark_blue/life_special(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.cold_aura()
	..()

/mob/living/simple_mob/slime/xenobio/dark_blue/proc/cold_aura()
	for(var/mob/living/L in view(2, src))
		if(L == src)
			continue
		chill(L)

	var/turf/T = get_turf(src)
	var/datum/gas_mixture/env = T.return_air()
	if(env)
		heat_add(env, -10 * 1000, HEAT_SOURCE_OTHER)

/mob/living/simple_mob/slime/xenobio/dark_blue/apply_melee_effects(atom/A)
	..()
	if(isliving(A))
		var/mob/living/L = A
		chill(L)
		to_chat(src, span_danger("You chill \the [L]."))
		to_chat(L, span_danger("You've been chilled by \the [src]!"))


/mob/living/simple_mob/slime/xenobio/dark_blue/proc/chill(mob/living/L)
	L.inflict_cold_damage(is_adult ? 10 : 5)
	if(L.get_cold_protection() < 1 && (L.ai_brain != null)) // Harmful auras will make the AI react to its bearer.
		L.ai_brain.react_to_attack(src)


/mob/living/simple_mob/slime/xenobio/silver/get_mechanics_info(list/additional_information)
	return ..(list("Tasers, including the slime version, are ineffective against this slime. The slimebaton still works.") + additional_information)

/mob/living/simple_mob/slime/xenobio/silver
	desc ="This slime is shiny, and can deflect lasers or other energy weapons directed at it."
	color = "#AAAAAA"
	slime_color = "silver"
	coretype = /obj/item/slime_extract/silver
	shiny = TRUE
	player_msg = "You <b>automatically reflect</b> lasers, beams, and tasers that hit you."

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/metal,
			/mob/living/simple_mob/slime/xenobio/blue,
			/mob/living/simple_mob/slime/xenobio/amber,
			/mob/living/simple_mob/slime/xenobio/amber
		)

CAPABILITY(/mob/living/simple_mob/slime/xenobio/silver, reflects(list(/obj/item/projectile/beam, /obj/item/projectile/energy), 100))


// Tier 3

/mob/living/simple_mob/slime/xenobio/bluespace/get_mechanics_info(list/additional_information)
	return ..(list("This slime will teleport to attack something if it is within a range of seven tiles. The teleport has a cooldown of five seconds.") + additional_information)

/mob/living/simple_mob/slime/xenobio/bluespace
	desc ="Trapping this slime in a cell is generally futile, as it can teleport at will."
	color = null
	slime_color = "bluespace"
	icon_state_override = "bluespace"
	coretype = /obj/item/slime_extract/bluespace
	player_msg = "You can <b>teleport at will</b> to a specific tile by clicking on it at range. This has a five second cooldown."

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/bluespace,
			/mob/living/simple_mob/slime/xenobio/bluespace,
			/mob/living/simple_mob/slime/xenobio/yellow,
			/mob/living/simple_mob/slime/xenobio/yellow
		)

	special_attack_min_range = 3
	special_attack_max_range = 7
	special_attack_cooldown = 5 SECONDS

/mob/living/simple_mob/slime/xenobio/bluespace/do_special_attack(atom/A, stance)
	// Teleport attack.
	if(!A)
		to_chat(src, span_warning("There's nothing to teleport to."))
		return FALSE

	var/list/nearby_things = range(1, A)
	var/list/valid_turfs = list()

	// All this work to just go to a non-dense tile.
	for(var/turf/potential_turf in nearby_things)
		var/valid_turf = TRUE
		if(potential_turf.density)
			continue
		for(var/atom/movable/AM in potential_turf)
			if(AM.density)
				valid_turf = FALSE
		if(valid_turf)
			valid_turfs.Add(potential_turf)

	if(!(valid_turfs.len))
		to_chat(src, span_warning("There wasn't an unoccupied spot to teleport to."))
		return FALSE

	var/turf/target_turf = pick(valid_turfs)
	var/turf/T = get_turf(src)



	T.visible_message(span_notice("\The [src] vanishes!"))
	fx_sparks(T, 5)

	forceMove(target_turf)
	play_sfx(target_turf, SFX_EFFECTS_PHASEIN, 0.5)
	to_chat(src, span_notice("You teleport to \the [target_turf]."))

	target_turf.visible_message(span_warning("\The [src] appears!"))
	fx_sparks(target_turf, 5)

	if(Adjacent(A))
		attack_target(A)


/mob/living/simple_mob/slime/xenobio/ruby/get_mechanics_info(list/additional_information)
	return ..(list("This slime is unnaturally stronger, allowing it to hit much harder, take less damage, and be stunned for less time. \
	Their glomp attacks also send the victim flying.") + additional_information)

/mob/living/simple_mob/slime/xenobio/ruby
	desc ="This slime has great physical strength."
	color = "#FF3333"
	slime_color = "ruby"
	shiny = TRUE
	glow_toggle = TRUE
	coretype = /obj/item/slime_extract/ruby
	player_msg = "Your <b>attacks knock back the target</b> a fair distance.<br>\
	You also hit harder, take less damage, and stuns affect you for less time."

	melee_attack_delay = 1 SECOND

	slime_mutation = list(
		/mob/living/simple_mob/slime/xenobio/dark_purple,
		/mob/living/simple_mob/slime/xenobio/dark_purple,
		/mob/living/simple_mob/slime/xenobio/ruby,
		/mob/living/simple_mob/slime/xenobio/ruby
	)

/mob/living/simple_mob/slime/xenobio/ruby/Initialize(mapload)
	apply_body_effect(/datum/body_effect/slime_strength, null, src) // Slime is always swole.
	return ..()

/mob/living/simple_mob/slime/xenobio/ruby/apply_melee_effects(atom/A, stance = I_HURT)
	..()

	if(isliving(A) && stance == I_HURT)
		var/mob/living/L = A
		if(L.mob_size <= MOB_MEDIUM)
			act_message(src, L, null, MSG_OTHERS(span_danger("%U% sends %T% flying with the impact!")))
			play_sfx(src, SFX_PUNCH)
			L.status_at_least(EFFECT_WEAKENED, 1)
			var/throwdir = get_dir(src, L)
			L.throw_at(get_edge_target_turf(L, throwdir), 3, 1, src)
		else
			to_chat(L, span_warning("\The [src] hits you with incredible force, but you remain in place."))
			act_message(src, L, null, MSG_OTHERS(span_danger("%U% hits %T% with incredible force, to no visible effect!")))
			play_sfx(src, SFX_PUNCH)


/mob/living/simple_mob/slime/xenobio/amber/get_mechanics_info(list/additional_information)
	return ..(list("This slime feeds nearby entities passively while it is alive. This can cause uncontrollable \
	slime growth and reproduction if not kept in check. The amber slime cannot feed itself, but can be fed by other amber slimes.") + additional_information)

/mob/living/simple_mob/slime/xenobio/amber
	desc ="This slime seems to be an expert in the culinary arts, as they create their own food to share with others.  \
	They would probably be very important to other slimes, if the other colors didn't try to kill them."
	color = "#FFBB00"
	slime_color = "amber"
	shiny = TRUE
	glow_toggle = TRUE
	coretype = /obj/item/slime_extract/amber
	player_msg = "You <b>passively provide nutrition</b> to nearby entities."

	slime_mutation = list(
		/mob/living/simple_mob/slime/xenobio/silver,
		/mob/living/simple_mob/slime/xenobio/silver,
		/mob/living/simple_mob/slime/xenobio/amber,
		/mob/living/simple_mob/slime/xenobio/amber
	)

/mob/living/simple_mob/slime/xenobio/amber/life_special_due()
	return TRUE

/mob/living/simple_mob/slime/xenobio/amber/life_special(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.feed_aura()
	..()

/mob/living/simple_mob/slime/xenobio/amber/proc/feed_aura()
	for(var/mob/living/L in view(1, src))
		if(L.stat == DEAD || !IIsAlly(L))
			continue
		if(L == src || istype(L, /mob/living/simple_mob/slime/xenobio/amber)) // Don't feed themselves, or it is impossible to stop infinite slimes without killing all of the ambers.
			continue
		if(istype(L, /mob/living/simple_mob/slime/xenobio))
			var/mob/living/simple_mob/slime/xenobio/X = L
			X.adjust_nutrition(rand(15, 25), 0)
		if(ishuman(L))
			var/mob/living/carbon/human/H = L
			if(HAS_SYNTHETIC_BIOLOGY(H))
				continue
			H.set_nutrition(between(0, H.nutrition + rand(15, 25), 800))

/mob/living/simple_mob/slime/xenobio/cerulean
	desc = "This slime is generally superior in a wide range of attributes, compared to the common slime.  The jack of all trades, but master of none."
	color = "#4F7EAA"
	slime_color = "cerulean"
	coretype = /obj/item/slime_extract/cerulean

	// Less than the specialized slimes, but higher than the rest.
	endurance = 200
	endurance_adult = 250

	melee_damage_lower = 10
	melee_damage_upper = 30

	movement_cooldown = -1 // This actually isn't any faster due to AI limitations that hopefully the timer subsystem can fix in the future.

	slime_mutation = list(
		/mob/living/simple_mob/slime/xenobio/dark_blue,
		/mob/living/simple_mob/slime/xenobio/dark_blue,
		/mob/living/simple_mob/slime/xenobio/cerulean,
		/mob/living/simple_mob/slime/xenobio/cerulean
	)

// Tier 4

/mob/living/simple_mob/slime/xenobio/red/get_mechanics_info(list/additional_information)
	return ..(list("This slime is faster than the others. Attempting to discipline this slime will always cause it to go rabid and berserk.") + additional_information)

/mob/living/simple_mob/slime/xenobio/red
	desc ="This slime is full of energy, and very aggressive.  'The red ones go faster.' seems to apply here."
	color = "#FF3333"
	slime_color = "red"
	coretype = /obj/item/slime_extract/red
	movement_cooldown = -1 // See above.
	untamable = TRUE // Will enrage if disciplined.

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/red,
			/mob/living/simple_mob/slime/xenobio/oil,
			/mob/living/simple_mob/slime/xenobio/oil,
			/mob/living/simple_mob/slime/xenobio/orange
		)



/mob/living/simple_mob/slime/xenobio/green/get_mechanics_info(list/additional_information)
	return ..(list("This slime will irradiate anything nearby passively, and will inject radium on attack. \
	A radsuit or other thick and radiation-hardened armor can protect from this. It will only radiate while alive.") + additional_information)

/mob/living/simple_mob/slime/xenobio/green
	desc ="This slime is radioactive."
	color = "#14FF20"
	slime_color = "green"
	coretype = /obj/item/slime_extract/green
	glow_toggle = TRUE
	reagent_injected = REAGENT_ID_RADIUM
	var/rads = 25
	player_msg = "You <b>passively irradiate your surroundings</b>.<br>\
	You also inject radium on attack."

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/purple,
			/mob/living/simple_mob/slime/xenobio/green,
			/mob/living/simple_mob/slime/xenobio/emerald,
			/mob/living/simple_mob/slime/xenobio/emerald
		)

/mob/living/simple_mob/slime/xenobio/green/life_special_due()
	return TRUE

/mob/living/simple_mob/slime/xenobio/green/life_special(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.irradiate()
	..()

/mob/living/simple_mob/slime/xenobio/green/proc/irradiate()
	radiation_pulse(
		src,
		max_range = 5,
		threshold = RAD_LIGHT_INSULATION,
		chance = rads * 0.5,
		minimum_exposure_time = URANIUM_RADIATION_MINIMUM_EXPOSURE_TIME,
		strength = rads
	)


/mob/living/simple_mob/slime/xenobio/pink/get_mechanics_info(list/additional_information)
	return ..(list("This slime will passively heal nearby entities within two tiles, including itself. It will only do this while alive.") + additional_information)

/mob/living/simple_mob/slime/xenobio/pink
	desc ="This slime has regenerative properties."
	color = "#FF0080"
	slime_color = "pink"
	coretype = /obj/item/slime_extract/pink
	glow_toggle = TRUE
	player_msg = "You <b>passively heal yourself and nearby allies</b>."

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/blue,
			/mob/living/simple_mob/slime/xenobio/light_pink,
			/mob/living/simple_mob/slime/xenobio/light_pink,
			/mob/living/simple_mob/slime/xenobio/pink
		)

/mob/living/simple_mob/slime/xenobio/pink/life_special_due()
	return TRUE

/mob/living/simple_mob/slime/xenobio/pink/life_special(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.heal_aura()
	..()

/mob/living/simple_mob/slime/xenobio/pink/proc/heal_aura()
	for(var/mob/living/L in view(src, 2))
		if(L.stat == DEAD || !IIsAlly(L))
			continue
		L.apply_body_effect(/datum/body_effect/aura/slime_heal, null, src)

/datum/body_effect/aura/slime_heal
	tick_interval = 2 SECONDS
	name = "slime mending"
	desc = "You feel somewhat gooey."
	mob_overlay_state = "pink_sparkles"
	stacks = MODIFIER_STACK_FORBID
	aura_max_distance = 2

	on_created_text = span_warning("Twinkling spores of goo surround you.  It makes you feel healthier.")
	on_expired_text = span_notice("The spores of goo have faded, although you feel much healthier than before.")

/datum/body_effect/aura/slime_heal/on_tick(mob/living/L)
	if(L.stat == DEAD)
		L.end_body_effect(type)
		return

	if(ishuman(L)) // Every limb, organic or robotic.
		var/mob/living/carbon/human/H = L
		for(var/obj/item/organ/external/E as anything in H.organs)
			H.mend(TREAT_TISSUE_REPAIR, 1, E.organ_tag)
			H.mend(TREAT_BURN_CARE, 1, E.organ_tag)
			H.mend(TREAT_PLATING_REPAIR, 1, E.organ_tag)
			H.mend(TREAT_WIRING_REPAIR, 1, E.organ_tag)
	else
		L.mend(TREAT_TISSUE_REPAIR, 1)
		L.mend(TREAT_BURN_CARE, 1)
		L.mend(TREAT_PLATING_REPAIR, 1)
		L.mend(TREAT_WIRING_REPAIR, 1)

	L.mend(TREAT_ANTITOXIN, 2)
	L.mend(TREAT_OXYGENATION, 2)
	L.mend(TREAT_GENETIC_REPAIR, 1)


/mob/living/simple_mob/slime/xenobio/gold/get_mechanics_info(list/additional_information)
	return ..(list("The slimebaton and taser charge this slime instead of stunning it, though they still discipline it.") + additional_information)

/mob/living/simple_mob/slime/xenobio/gold
	desc ="This slime absorbs energy, and cannot be stunned by normal means."
	color = "#EEAA00"
	shiny = TRUE
	slime_color = "gold"
	coretype = /obj/item/slime_extract/gold

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/metal,
			/mob/living/simple_mob/slime/xenobio/gold,
			/mob/living/simple_mob/slime/xenobio/sapphire,
			/mob/living/simple_mob/slime/xenobio/sapphire
		)

/mob/living/simple_mob/slime/xenobio/gold/slimebatoned(mob/living/user, amount)
	adjust_discipline(round(amount/2))
	power_charge = between(0, power_charge + amount, 10)

/mob/living/simple_mob/slime/xenobio/gold/get_description_interaction() // So it doesn't say to use a baton on them.
	return list()


// Tier 5

/mob/living/simple_mob/slime/xenobio/oil/get_mechanics_info(list/additional_information)
	return ..(list("If this slime suffers damage from a fire or heat based source, or if it is caught inside \
	an explosion, it will explode. Oil slimes will also suicide-bomb themselves when fighting something that is not a monkey or slime.") + additional_information)

/mob/living/simple_mob/slime/xenobio/oil
	desc ="This slime is explosive and volatile.  Smoking near it is probably a bad idea."
	color = "#333333"
	slime_color = "oil"
	shiny = TRUE
	coretype = /obj/item/slime_extract/oil
	player_msg = "You <b>will explode if struck by a burning attack</b>, or if you hit an enemy with a melee attack that is not a monkey or another slime."

	slime_mutation = list(
		/mob/living/simple_mob/slime/xenobio/oil,
		/mob/living/simple_mob/slime/xenobio/oil,
		/mob/living/simple_mob/slime/xenobio/red,
		/mob/living/simple_mob/slime/xenobio/red
	)

/mob/living/simple_mob/slime/xenobio/oil
	fire_reaction = FIRE_REACTION_TRIGGER
	fire_trigger_proc = TYPE_PROC_REF(/mob/living/simple_mob/slime/xenobio/oil, explode)
	fire_trigger_verb = "exploded"

/mob/living/simple_mob/slime/xenobio/oil/proc/explode()
	if(stat != DEAD)
		explosion(src.loc, 0, 2, 4) // A bit weaker since the suicide charger tended to gib the poor sod being targeted.
		if(src) // Delete ourselves if the explosion didn't do it.
			destroyed(src, null, "explosion")

/mob/living/simple_mob/slime/xenobio/oil/proc/suicide_bomb(mob/living/L)
	log_and_message_admins("has suicide-bombed themselves while trying to kill \the [L].", src)
	explode()

/mob/living/simple_mob/slime/xenobio/oil/apply_melee_effects(atom/A)
	if(isliving(A))
		var/mob/living/L = A
		if(ishuman(L))
			var/mob/living/carbon/human/H = A
			if(istype(H.species, /datum/species/monkey))
				return ..()// Don't blow up when just eatting monkeys.

		else if(isslime(L))
			return ..()

		// Otherwise blow ourselves up.
		say(pick("Sacrifice...!", "Sssss...", "Boom...!"))
		ai_busy_begin()
		after(src, 2 SECONDS, PROC_REF(suicide_bomb), with = list(L))

	return ..()

CAPABILITIES(/mob/living/simple_mob/slime/xenobio/oil)
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(blast_explode))))

/mob/living/simple_mob/slime/xenobio/oil/proc/blast_explode(datum/act/A)
	log_and_message_admins("exploded due to a chain reaction with another explosion.", src)
	explode()
	return TRUE

/mob/living/simple_mob/slime/xenobio/oil/bullet_act(obj/item/projectile/P, def_zone)
	if(P.obj_damage_type() && P.obj_damage_type() == BURN && P.damage) // Most bullets won't trigger the explosion, as a mercy towards Security.
		log_and_message_admins("exploded due to bring hit by a burning projectile[P.firer ? " by [key_name(P.firer)]" : ""].", src)
		explode()
	else
		..()

EXTEND_INTERACTIONS(/mob/living/simple_mob/slime/xenobio/oil, INTERACT_ITEM(null, PROC_REF(oilslime_interaction_item)))

/// Old attackby: burning weapons make it explode.
/mob/living/simple_mob/slime/xenobio/oil/proc/oilslime_interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	. = TRUE
	if(istype(W) && W.force && W.obj_damage_type() == BURN)
		log_and_message_admins("exploded due to being hit with a burning weapon ([W]) by [key_name(user)].", src)
		explode()
	else
		return FALSE


/mob/living/simple_mob/slime/xenobio/sapphire/get_mechanics_info(list/additional_information)
	return ..(list("This slime uses more robust tactics when fighting and won't hold back, so it is dangerous to be alone \
	with one if hostile, and especially dangerous if they outnumber you.") + additional_information)

/mob/living/simple_mob/slime/xenobio/sapphire
	desc ="This slime seems a bit brighter than the rest, both figuratively and literally."
	color = "#2398FF"
	slime_color = "sapphire"
	shiny = TRUE
	glow_toggle = TRUE
	coretype = /obj/item/slime_extract/sapphire

	slime_mutation = list(
		/mob/living/simple_mob/slime/xenobio/sapphire,
		/mob/living/simple_mob/slime/xenobio/sapphire,
		/mob/living/simple_mob/slime/xenobio/gold,
		/mob/living/simple_mob/slime/xenobio/gold
	)


/mob/living/simple_mob/slime/xenobio/emerald/get_mechanics_info(list/additional_information)
	return ..(list("This slime will make everything around it, and itself, faster for a few seconds, if close by.") + additional_information)

/mob/living/simple_mob/slime/xenobio/emerald
	desc ="This slime is faster than usual, even more so than the red slimes."
	color = "#22FF22"
	shiny = TRUE
	glow_toggle = TRUE
	slime_color = "emerald"
	coretype = /obj/item/slime_extract/emerald

	slime_mutation = list(
		/mob/living/simple_mob/slime/xenobio/green,
		/mob/living/simple_mob/slime/xenobio/green,
		/mob/living/simple_mob/slime/xenobio/emerald,
		/mob/living/simple_mob/slime/xenobio/emerald
	)

/mob/living/simple_mob/slime/xenobio/emerald/life_special_due()
	return TRUE

/mob/living/simple_mob/slime/xenobio/emerald/life_special(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.zoom_aura()
	..()

/mob/living/simple_mob/slime/xenobio/emerald/proc/zoom_aura()
	for(var/mob/living/L in view(src, 2))
		if(L.stat == DEAD || !IIsAlly(L))
			continue
		L.apply_body_effect(/datum/body_effect/technomancer/haste, 5 SECONDS, src)


/mob/living/simple_mob/slime/xenobio/light_pink/get_mechanics_info(list/additional_information)
	return ..(list("This slime is effectively always disciplined initially.") + additional_information)

/mob/living/simple_mob/slime/xenobio/light_pink
	desc ="This slime seems a lot more peaceful than the others."
	color = "#FF8888"
	slime_color = "light pink"
	coretype = /obj/item/slime_extract/light_pink

	slime_mutation = list(
		/mob/living/simple_mob/slime/xenobio/pink,
		/mob/living/simple_mob/slime/xenobio/pink,
		/mob/living/simple_mob/slime/xenobio/light_pink,
		/mob/living/simple_mob/slime/xenobio/light_pink
	)


// Special
/mob/living/simple_mob/slime/xenobio/rainbow/get_mechanics_info(list/additional_information)
	return ..(list("This slime is considered to be the same color as all other slime colors at the same time for the purposes of \
	other slimes being friendly to them, and therefore will never be harmed by another slime. \
	Attacking this slime will provoke the wrath of all slimes within range.") + additional_information)

/mob/living/simple_mob/slime/xenobio/rainbow
	desc ="This slime changes colors constantly."
	color = null // Uses a special icon_state.
	slime_color = "rainbow"
	coretype = /obj/item/slime_extract/rainbow
	icon_state_override = "rainbow"
	unity = TRUE
	player_msg = "You are <b>considered to be the same color as every slime</b>, \
	meaning that you are considered an ally to all slimes."

	slime_mutation = list(
		/mob/living/simple_mob/slime/xenobio/rainbow,
		/mob/living/simple_mob/slime/xenobio/rainbow,
		/mob/living/simple_mob/slime/xenobio/rainbow,
		/mob/living/simple_mob/slime/xenobio/rainbow
	)

/mob/living/simple_mob/slime/xenobio/rainbow/Initialize(mapload)
	unify()
	return ..()

// The RD's pet slime.
/mob/living/simple_mob/slime/xenobio/rainbow/kendrick
	name = "Kendrick"
	desc = "The " + JOB_RESEARCH_DIRECTOR + "'s pet slime.  It shifts colors constantly."
	rainbow_core_candidate = FALSE
	// Doing pacify() in initialize() won't actually pacify the AI due to the ai_brain not existing due to parent initialize() not being called yet.
	// Instead lets just give them an ai_brain that does that for us.

/mob/living/simple_mob/slime/xenobio/rainbow/kendrick/Initialize(mapload)
	pacify() // So the physical mob also gets made harmless.
	return ..()

// A pacified pink slime for either Admin-spawning or putting in a casino reward or capture crystal.
/mob/living/simple_mob/slime/xenobio/pink/sana
	name = "Sana"
	desc = "A pink slime that seems to be oddly friendly, and doesn't seem interested in eating your face like the rest of them."
	rainbow_core_candidate = FALSE

/mob/living/simple_mob/slime/xenobio/pink/sana/Initialize(mapload)
	pacify() // So the physical mob also gets made harmless.
	return ..()
