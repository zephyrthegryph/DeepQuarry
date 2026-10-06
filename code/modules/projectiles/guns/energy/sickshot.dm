// -------------- Sickshot -------------
/obj/item/gun/energy/sickshot/get_mechanics_info(list/additional_information)
	return ..(list("This gun causes nausea in targets, causing vomiting. It will sometimes also cause them to vomit up prey; repeated shots may help.") + additional_information)

/obj/item/gun/energy/sickshot
	name = "\'Sickshot\' revolver"
	desc = "Need to expel something? Don't mind having to clean up the mess afterwards? The MPA6 'Sickshot' is the answer to your prayers. \
	Using a short-range concentrated blast of disruptive sound, the Sickshot will nauseate the target for several seconds. NOTE: Not suitable \
	for use in vacuum. Usage on animals may cause panic and rage. May cause contraction and release of various 'things' from various 'orifices', even if the target is already dead."
	description_fluff = ""
	description_antag = ""

	icon = 'icons/vore/custom_guns_vr.dmi'
	icon_state = "sickshot"

	icon_override = 'icons/vore/custom_guns_vr.dmi'
	item_state = "gun"

	fire_sound = SFX_WEAPONS_ELUGER
	projectile_type = /obj/item/projectile/sickshot

	charge_cost = 600


//Projectile
/obj/item/projectile/sickshot
	name = "sickshot pulse"
	icon_state = "sound"
	damage = 5
	armor_penetration = 30
	injury_kind = INJURY_BURN
	embed_chance = 0
	vacuum_traversal = 0
	range = 5 //Scary name, but just deletes the projectile after this range

/obj/item/projectile/sickshot/on_hit(atom/movable/target, blocked = 0)
	if(isliving(target))
		var/mob/living/L = target
		if(prob(20))
			L.release_vore_contents()

		if(ishuman(target))
			var/mob/living/carbon/human/H = target
			H.vomit()
			H.status_at_least(STAT_CONFUSED, 2)

		return 1
