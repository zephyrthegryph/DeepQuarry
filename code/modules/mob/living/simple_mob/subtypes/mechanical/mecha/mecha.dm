// Mecha simple_mobs are essentially fake mechs. Generally tough and scary to fight.
// By default, they're automatically piloted by some kind of drone AI. They can be set to be "piloted" instead with a var.
// Tries to be as similar to the real deal as possible.

/mob/living/simple_mob/mechanical/mecha
	name = "mecha"
	desc = "A big stompy mech!"
	icon = 'icons/mecha/mecha.dmi'

	faction = FACTION_SYNDICATE
	movement_cooldown = 1.5
	movement_sound = SFX_MECHSTEP // This gets fed into playsound(), which can also take strings as a 'group' of sound files.
	turn_sound = SFX_MECHA_MECHTURN
	endurance = 300
	mob_size = MOB_LARGE
	damage_threshold = 5 //Anything that's 5 or less damage will not do damage.

	organ_names = /datum/decl/mob_organ_names/mecha

	armor_spec = "melee=20;bullet=10;bio=100;rad=100"

	response_help = "taps on"
	response_disarm = "knocks on"
	response_harm = "uselessly hits"
	harm_intent_damage = 0

	say_list_type = /datum/say_list/malf_drone

	var/wreckage = /obj/effect/decal/mecha_wreckage/gygax/dark
	var/pilot_type = null // Set to spawn a pilot when destroyed. Setting this also makes the mecha vulnerable to things that affect sentient minds.
	var/deflect_chance = 10 // Chance to outright stop an attack, just like a normal exosuit.
	var/has_repair_droid = FALSE // If true, heals 2 damage every tick and gets a repair droid overlay.

/mob/living/simple_mob/mechanical/mecha/Initialize(mapload)
	if(!pilot_type)
		name = "autonomous [initial(name)]"
		desc = "[initial(desc)] It appears to be piloted by a drone intelligence."
	else
		say_list_type = /datum/say_list/merc

	return ..()


/mob/living/simple_mob/mechanical/mecha
	delete_on_death = TRUE

/mob/living/simple_mob/mechanical/mecha
	death_message = "explodes!"

/mob/living/simple_mob/mechanical/mecha/on_death(gibbed)
	..() // Do everything else first.

	// Make the exploding more convincing with an actual explosion and some sparks.
	fx_sparks(src, 3)
	explosion(get_turf(src), 0, 0, 1, 3)

	// 'Eject' our pilot, if one exists.
	if(pilot_type)
		var/mob/living/L = new pilot_type(loc)
		L.faction = src.faction

	if(wreckage)
		new wreckage(loc) // Leave some wreckage.


/mob/living/simple_mob/mechanical/mecha/life_special_due()
	return TRUE

/mob/living/simple_mob/mechanical/mecha/life_special(datum/seq_frame/life/F)
	if(src.has_repair_droid)
		src.mend(TREAT_PLATING_REPAIR, 2)
		src.mend(TREAT_WIRING_REPAIR, 2)
	..()

/mob/living/simple_mob/mechanical/mecha/draw(datum/look/look)
	..()
	look.overlay("repair_droid", has_repair_droid, 'icons/mecha/mecha_equipment.dmi')

/mob/living/simple_mob/mechanical/mecha/speech_bubble_appearance()
	return pilot_type ? "" : ..()

// Piloted mechs are controlled by (presumably) something humanoid so they are vulnerable to certain things.
/mob/living/simple_mob/mechanical/mecha/is_sentient()
	return pilot_type ? TRUE : FALSE

/*
// Real mechs can't turn and run at the same time. This tries to simulate that.
// Commented out because the AI can't handle it sadly.
/mob/living/simple_mob/mechanical/mecha/SelfMove(turf/n, direct)
	if(direct != dir)
		set_dir(direct)
		return FALSE // We didn't actually move, and returning FALSE means the mob can try to actually move almost immediately and not have to wait the full movement cooldown.
	return ..()
*/

/mob/living/simple_mob/mechanical/mecha/bullet_act(obj/item/projectile/P)
	if(prob(deflect_chance))
		act_message(P, src, null, MSG_OTHERS(span_warning("%U% is deflected by %T%'s armor!")))
		deflect_sprite()
		return 0
	fx_sparks(src, 3)
	return ..()

/mob/living/simple_mob/mechanical/mecha/proc/deflect_sprite()
	var/image/deflect_image = image('icons/effects/effects.dmi', "deflect_static")
	add_overlay(deflect_image)
	after(src, 1 SECOND, TYPE_PROC_REF(/atom, cut_overlay), with = list(deflect_image))

CAPABILITIES(/mob/living/simple_mob/mechanical/mecha)
	op("mecha_item", item(/obj/item), then(PROC_REF(mecha_interaction_item)))

/// Old attackby: armour deflection.
/mob/living/simple_mob/mechanical/mecha/proc/mecha_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	. = OP_OK
	if(prob(deflect_chance))
		act_message(user, src, null, MSG_OTHERS(span_warning("%U%'s %I% bounces off %T%'s armor!")), item = I)
		deflect_sprite()
		user.setClickCooldown(user.get_attack_speed(I))
		return
	return OP_DECLINE

/mob/living/simple_mob/mechanical/mecha/ex_act(severity)
	if(prob(deflect_chance))
		severity++ // This somewhat misleadingly makes it less severe.
		deflect_sprite()
	..(severity)

/datum/decl/mob_organ_names/mecha
TYPE_TABLE(/datum/decl/mob_organ_names/mecha, mob_organ_hit_zones, list("central chassis", "control module", "hydraulics", "left arm", "right arm", "left leg", "right leg", "sensor suite", "radiator", "power supply", "left equipment mount", "right equipment mount"))
