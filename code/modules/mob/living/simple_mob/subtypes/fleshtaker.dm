/*
Concept: Mind controlling parasite. Hostile to all mobs.
On attack if our target is a simple mob, and has no mind.
We simply engulf them, evicerating their body and stealing their form as well as some of their stats.
However we dont gain special attacks and verbs, for example, if we evicerate a dragon we dont get a breath attack suddnely.
Only physical attributes are copied.
*/
/mob/living/simple_mob/fleshtaker
	faction = "Fleshtaker"
	name = "Fleshtaker"
	desc = "A strange creature"
	icon = 'icons/mob/synxmanyvoices.dmi'
	icon_living = "939_living"
	icon_dead = "939_dead"
	pixel_x = -15
	//Lets write down our base stats so we can revert easily
	var/list/base_values = list() // ALLOW(instance_list): d: per-mob base_values, sized at creation and filled in place; mobs are few

	var/flesh_mimic = FALSE //are we currently posing as something else?
	var/mimic_icon = null //the icon file of what we pose as (null while we look like ourselves)

TRACKED(/mob/living/simple_mob/fleshtaker, flesh_mimic)
TRACKED(/mob/living/simple_mob/fleshtaker, mimic_icon)

/// Our own look, or the icon file of what we are posing as (its living, dead and rest states are our tracked icon_living/icon_dead).
/mob/living/simple_mob/fleshtaker/draw(datum/look/look)
	..()
	if(flesh_mimic && mimic_icon)
		look.set_icon(mimic_icon)

/mob/living/simple_mob/fleshtaker/Initialize(mapload)
	. = ..()
	base_values["name"] = name
	base_values["desc"] = desc
	base_values["icon_living"] = icon_living
	base_values["icon_dead"] = icon_dead
	base_values["pixel_x"] = pixel_x
	base_values["pixel_y"] = pixel_y //record our default y pixel offset for later reversion
	base_values["melee_damage_lower"] = melee_damage_lower
	base_values["melee_damage_upper"] = melee_damage_upper
	base_values["endurance"] = endurance
	base_values["armor"] = get_armor()


	//copy stats from our engulfed target
/mob/living/simple_mob/fleshtaker/proc/flesh_mimic(mob/living/simple_mob/target)
	set_flesh_mimic(TRUE)
	name = target.name
	desc = target.desc
	set_mimic_icon(target.icon)
	set_icon_living(target.icon_living)
	set_icon_dead(target.icon_dead)
	pixel_x = target.pixel_x
	pixel_y = target.pixel_y
	melee_damage_lower = target.melee_damage_lower
	melee_damage_upper = target.melee_damage_upper
	endurance = target.endurance
	fully_heal()
	set_armor(target.get_armor())
	//steal base stats
	//possibly steal vorgans

//reset to original values
/mob/living/simple_mob/fleshtaker/proc/revert_mimic()
	set_flesh_mimic(FALSE)
	name = base_values["name"]
	desc = base_values["desc"]
	set_mimic_icon(null)
	set_icon_living(base_values["icon_living"])
	set_icon_dead(base_values["icon_dead"])
	pixel_x = base_values["pixel_x"]
	pixel_y = base_values["pixel_y"]
	melee_damage_lower = base_values["melee_damage_lower"]
	melee_damage_upper = base_values["melee_damage_upper"]
	endurance = base_values["endurance"]
	fully_heal()
	set_armor(base_values["armor"])

/mob/living/simple_mob/fleshtaker/apply_melee_effects(atom/A)
	if(istype(A,/mob/living/simple_mob) && !flesh_mimic)
		var/mob/living/simple_mob/M = A
		if(!M.mind)
			flesh_mimic(M)
			M.gib()
	..()
